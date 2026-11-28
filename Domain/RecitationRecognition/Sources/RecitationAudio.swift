//
//  RecitationAudio.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import AVFoundation
import Foundation

/// Audio in the recognizer's input format: 16 kHz mono float samples.
public enum RecitationAudio {
    // MARK: Public

    public static let sampleRate = 16000

    /// Decodes an audio file (MP3, M4A, WAV, ...) and resamples it to 16 kHz mono.
    public static func samples(contentsOf url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw RecitationAudioError.cannotAllocateBuffer
        }
        try file.read(into: input)
        return try resample(input)
    }

    /// Converts a PCM buffer of any rate and channel count to 16 kHz mono float samples.
    public static func resample(_ input: AVAudioPCMBuffer) throws -> [Float] {
        guard let converter = AVAudioConverter(from: input.format, to: outputFormat) else {
            throw RecitationAudioError.unsupportedFormat
        }
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw RecitationAudioError.cannotAllocateBuffer
        }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            throw conversionError ?? RecitationAudioError.unsupportedFormat
        }
        guard let channel = output.floatChannelData?[0] else {
            return []
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    /// Resamples mono float samples recorded at `sampleRate` (a microphone's) to 16 kHz.
    public static func resample(mono samples: [Float], sampleRate: Double) throws -> [Float] {
        guard !samples.isEmpty else {
            return []
        }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else {
            throw RecitationAudioError.cannotAllocateBuffer
        }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return try resample(buffer)
    }

    /// Trims a rolling 16 kHz audio buffer so its start falls on the quietest `frame`-sample slice
    /// near `targetSeconds` before the end (within ±`searchSeconds`/2). Starting a FastConformer
    /// streaming window at a pause instead of mid-word prevents front-end corruption and stabilizes
    /// live transcription.
    public static func quietAnchoredWindow(
        _ samples: [Float],
        targetSeconds: Double = 14.0,
        searchSeconds: Double = 4.0,
        frame: Int = CoreMLRecitationModel.samplesPerFrame
    ) -> [Float] {
        let targetCount = Int(targetSeconds * Double(sampleRate))
        guard samples.count > targetCount, frame > 0 else {
            return samples
        }
        let rawStart = samples.count - targetCount
        let halfSearch = Int((searchSeconds / 2.0) * Double(sampleRate))
        let minimumKeep = min(targetCount, 4 * sampleRate)
        let lower = max(0, rawStart - halfSearch)
        let upper = min(samples.count - minimumKeep, rawStart + halfSearch)
        guard upper > lower + frame else {
            return Array(samples[rawStart...])
        }
        var bestStart = rawStart
        var quietest = Float.infinity
        var cursor = lower
        while cursor + frame <= upper {
            var energy: Float = 0
            for sample in samples[cursor ..< cursor + frame] {
                energy += sample * sample
            }
            if energy < quietest {
                quietest = energy
                bestStart = cursor
            }
            cursor += frame
        }
        return Array(samples[bestStart...])
    }

    /// Gently normalizes quiet speech windows so FastConformer's internal log-mel floor does not
    /// swallow soft human recitation or laptop-speaker playback. Leaves pure silence/room-floor
    /// buffers untouched (`peak < minPeak`) and caps gain at `maxGain`.
    public static func normalizeForRecognition(
        _ samples: [Float],
        minPeak: Float = 0.004,
        targetPeak: Float = 0.5,
        maxGain: Float = 20.0
    ) -> [Float] {
        var peak: Float = 0
        for sample in samples {
            let magnitude = abs(sample)
            if magnitude > peak {
                peak = magnitude
            }
        }
        guard peak >= minPeak, peak < targetPeak * 0.5 else {
            return samples
        }
        let gain = min(maxGain, targetPeak / peak)
        return samples.map { max(-1.0, min(1.0, $0 * gain)) }
    }

    // MARK: Private

    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(sampleRate),
        channels: 1,
        interleaved: false
    )!
}

public enum RecitationAudioError: Error {
    case cannotAllocateBuffer
    case unsupportedFormat
}
