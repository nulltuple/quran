//
//  WhisperMelSpectrogram.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Accelerate
import Foundation

/// Computes the 80-bin Whisper log-mel spectrogram matching OpenAI Whisper / Hugging Face
/// `WhisperFeatureExtractor` (and `Hisnlabs/tajweed-v2`'s training preprocessing):
/// 16 kHz mono float32, padded with 0.4 s (`6,400` samples) silence on each end, center-reflected
/// STFT (`n_fft = 400`, `hop_length = 160`, periodic Hann window), Slaney 80-bin mel filterbank,
/// `log10(max(x, 1e-10))`, clamped to `max - 8.0`, scaled `(x + 4.0) / 4.0`.
public enum WhisperMelSpectrogram {
    public struct Result: Equatable, Sendable {
        /// Row-major `[80, frameCount]` float32 log-mel features (`frameCount` is even, `<= maxFrames`).
        public let features: [Float]
        public let frameCount: Int
        /// Total length in samples of the lead/trail-padded audio fed to the STFT.
        public let paddedSampleCount: Int
    }

    // MARK: Public

    public static let melBins = 80
    public static let fftSize = 400
    public static let hopLength = 160
    public static let frequencyBins = fftSize / 2 + 1 // 201
    public static let leadSamples = 6400 // 0.4 s at 16 kHz
    public static let maxFrames = 3000 // 30 s at 100 mel frames/s

    /// Computes `[80, T]` log-mel features for 16 kHz mono `samples`.
    public static func compute(
        from samples: ArraySlice<Float>,
        leadSamples: Int = Self.leadSamples,
        maxFrames: Int = Self.maxFrames
    ) -> Result {
        let paddedCount = samples.count + 2 * leadSamples
        let halfFFT = fftSize / 2 // 200

        // Center reflect-padding of length 200 on each side, matching `torch.stft(..., center=True)`.
        var signal = [Float](repeating: 0, count: paddedCount + 2 * halfFFT)
        if !samples.isEmpty {
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    signal.withUnsafeMutableBufferPointer { dst in
                        dst.baseAddress!
                            .advanced(by: halfFFT + leadSamples)
                            .update(from: base, count: samples.count)
                    }
                }
            }
        }
        // Reflect pad edges (note: when leadSamples >= halfFFT, edges are zero, but handle general leadSamples cleanly).
        if paddedCount > 1 {
            for i in 0 ..< halfFFT {
                let leftSrc = min(paddedCount - 1, halfFFT - i)
                signal[i] = signal[halfFFT + leftSrc]
                let rightSrc = max(0, paddedCount - 2 - i)
                signal[halfFFT + paddedCount + i] = signal[halfFFT + rightSrc]
            }
        }

        // `torch.stft` produces `1 + paddedCount / hopLength` frames; Whisper drops the last frame (`[:-1]`).
        let rawFrames = 1 + paddedCount / hopLength
        let usableFrames = max(0, rawFrames - 1)
        let frameCount = min(maxFrames, max(4, (usableFrames / 2) * 2))

        // Build windowed frames matrix X of shape [frameCount, fftSize] (row-major).
        let tables = Tables.shared
        var windowed = [Float](repeating: 0, count: frameCount * fftSize)
        signal.withUnsafeBufferPointer { sig in
            tables.hannWindow.withUnsafeBufferPointer { win in
                windowed.withUnsafeMutableBufferPointer { out in
                    for frame in 0 ..< frameCount {
                        let start = frame * hopLength
                        if start + fftSize <= sig.count {
                            vDSP_vmul(
                                sig.baseAddress!.advanced(by: start), 1,
                                win.baseAddress!, 1,
                                out.baseAddress!.advanced(by: frame * fftSize), 1,
                                vDSP_Length(fftSize)
                            )
                        }
                    }
                }
            }
        }

        // Real & imaginary DFT components via BLAS-backed matrix multiply:
        // [frameCount, 400] x [400, 201] -> [frameCount, 201].
        var realPart = [Float](repeating: 0, count: frameCount * frequencyBins)
        var imagPart = [Float](repeating: 0, count: frameCount * frequencyBins)
        vDSP_mmul(
            windowed, 1,
            tables.dftCosTransposed, 1,
            &realPart, 1,
            vDSP_Length(frameCount),
            vDSP_Length(frequencyBins),
            vDSP_Length(fftSize)
        )
        vDSP_mmul(
            windowed, 1,
            tables.dftSinTransposed, 1,
            &imagPart, 1,
            vDSP_Length(frameCount),
            vDSP_Length(frequencyBins),
            vDSP_Length(fftSize)
        )

        // Power spectrum: real^2 + imag^2, shape [frameCount, 201].
        var power = [Float](repeating: 0, count: frameCount * frequencyBins)
        vDSP_vsq(realPart, 1, &realPart, 1, vDSP_Length(power.count))
        vDSP_vsq(imagPart, 1, &imagPart, 1, vDSP_Length(power.count))
        vDSP_vadd(realPart, 1, imagPart, 1, &power, 1, vDSP_Length(power.count))

        // Transpose power to [201, frameCount] so melFilterbank [80, 201] x [201, frameCount] -> [80, frameCount].
        var powerTransposed = [Float](repeating: 0, count: frequencyBins * frameCount)
        vDSP_mtrans(power, 1, &powerTransposed, 1, vDSP_Length(frequencyBins), vDSP_Length(frameCount))

        var mel = [Float](repeating: 0, count: melBins * frameCount)
        vDSP_mmul(
            tables.melFilterbank, 1,
            powerTransposed, 1,
            &mel, 1,
            vDSP_Length(melBins),
            vDSP_Length(frameCount),
            vDSP_Length(frequencyBins)
        )

        // log10(max(mel, 1e-10)), clamp to max - 8.0, then (x + 4.0) / 4.0.
        var maxLog: Float = -.greatestFiniteMagnitude
        for i in 0 ..< mel.count {
            let value = log10f(max(mel[i], 1e-10))
            mel[i] = value
            if value > maxLog {
                maxLog = value
            }
        }
        let floorLog = maxLog - 8.0
        for i in 0 ..< mel.count {
            mel[i] = (max(mel[i], floorLog) + 4.0) / 4.0
        }

        return Result(features: mel, frameCount: frameCount, paddedSampleCount: paddedCount)
    }

    // MARK: Private

    private struct Tables: Sendable {
        static let shared = Tables()

        let hannWindow: [Float]
        /// `[fftSize, frequencyBins]` (400 x 201) cosine basis.
        let dftCosTransposed: [Float]
        /// `[fftSize, frequencyBins]` (400 x 201) -sine basis.
        let dftSinTransposed: [Float]
        /// `[melBins, frequencyBins]` (80 x 201) Slaney mel filterbank.
        let melFilterbank: [Float]

        private init() {
            // Periodic Hann window matching `torch.hann_window(400)`.
            hannWindow = (0 ..< fftSize).map { n in
                Float(0.5 - 0.5 * cos(2.0 * Double.pi * Double(n) / Double(fftSize)))
            }

            var cosMatrix = [Float](repeating: 0, count: fftSize * frequencyBins)
            var sinMatrix = [Float](repeating: 0, count: fftSize * frequencyBins)
            let twoPiOverN = 2.0 * Double.pi / Double(fftSize)
            for n in 0 ..< fftSize {
                let row = n * frequencyBins
                for k in 0 ..< frequencyBins {
                    let angle = twoPiOverN * Double(n * k)
                    cosMatrix[row + k] = Float(cos(angle))
                    sinMatrix[row + k] = Float(-sin(angle))
                }
            }
            dftCosTransposed = cosMatrix
            dftSinTransposed = sinMatrix
            melFilterbank = Self.makeSlaneyMelFilterbank(
                sampleRate: Double(RecitationAudio.sampleRate),
                fftSize: fftSize,
                melBins: melBins
            )
        }

        private static func makeSlaneyMelFilterbank(sampleRate: Double, fftSize: Int, melBins: Int) -> [Float] {
            let fSp = 200.0 / 3.0
            let minLogHz = 1000.0
            let minLogMel = minLogHz / fSp
            let logStep = log(6.4) / 27.0

            func hzToMel(_ f: Double) -> Double {
                f >= minLogHz ? minLogMel + log(f / minLogHz) / logStep : f / fSp
            }
            func melToHz(_ m: Double) -> Double {
                m >= minLogMel ? minLogHz * exp(logStep * (m - minLogMel)) : fSp * m
            }

            let bins = fftSize / 2 + 1
            let nyquist = sampleRate / 2.0
            let allFreqs = (0 ..< bins).map { nyquist * Double($0) / Double(bins - 1) }

            let mMin = hzToMel(0.0)
            let mMax = hzToMel(nyquist)
            let fPts = (0 ..< melBins + 2).map { i in
                melToHz(mMin + (mMax - mMin) * Double(i) / Double(melBins + 1))
            }

            var fb = [Float](repeating: 0, count: melBins * bins)
            for m in 0 ..< melBins {
                let fLeft = fPts[m]
                let fCenter = fPts[m + 1]
                let fRight = fPts[m + 2]
                let enorm = 2.0 / (fRight - fLeft)
                let row = m * bins
                for b in 0 ..< bins {
                    let f = allFreqs[b]
                    let down = (f - fLeft) / (fCenter - fLeft)
                    let up = (fRight - f) / (fRight - fCenter)
                    let weight = max(0.0, min(down, up)) * enorm
                    fb[row + b] = Float(weight)
                }
            }
            return fb
        }
    }
}
