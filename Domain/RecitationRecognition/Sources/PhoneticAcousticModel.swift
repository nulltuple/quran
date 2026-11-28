//
//  PhoneticAcousticModel.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreML
import Foundation

/// A single decoded symbol from the Quran Phonetic Script (QPS) CTC head.
/// Uses `Unicode.Scalar` (not Swift `Character`) because Arabic diacritics (`َ`, `ُ`, `ِ`) are
/// independent CTC tokens with their own frame timing and probability, never combined into grapheme clusters.
public struct PhoneticSymbol: Equatable, Sendable {
    public let symbol: Unicode.Scalar
    /// Softmax probability (0...1) of the winning symbol at its CTC emission frame.
    public let probability: Float
    /// Center timestamp in seconds from the start of the input audio (may be slightly negative near onset).
    public let centerSeconds: Double
    /// 0-based encoder frame index (50 frames/s).
    public let frameIndex: Int

    public init(symbol: Unicode.Scalar, probability: Float, centerSeconds: Double, frameIndex: Int) {
        self.symbol = symbol
        self.probability = probability
        self.centerSeconds = centerSeconds
        self.frameIndex = frameIndex
    }
}

/// The output of a phonetic acoustic model over an audio clip.
public struct PhoneticTranscription: Equatable, Sendable {
    public let symbols: [PhoneticSymbol]
    /// End timestamp in seconds of the last non-blank emission (used for madd duration timing in V5).
    public let endSeconds: Double
    public let frameCount: Int
    public let audioSeconds: Double
    /// Per-frame argmax class indices from optional sifat heads (0 = blank), preserved for V5.
    public let qalqalahFrames: [UInt8]
    public let ghunnahFrames: [UInt8]
    public let tafkheemFrames: [UInt8]

    public var text: String {
        String(String.UnicodeScalarView(symbols.map(\.symbol)))
    }

    public init(
        symbols: [PhoneticSymbol],
        endSeconds: Double,
        frameCount: Int,
        audioSeconds: Double,
        qalqalahFrames: [UInt8] = [],
        ghunnahFrames: [UInt8] = [],
        tafkheemFrames: [UInt8] = []
    ) {
        self.symbols = symbols
        self.endSeconds = endSeconds
        self.frameCount = frameCount
        self.audioSeconds = audioSeconds
        self.qalqalahFrames = qalqalahFrames
        self.ghunnahFrames = ghunnahFrames
        self.tafkheemFrames = tafkheemFrames
    }
}

/// The QPS phonetic vocabulary and model timing constants loaded from `vocab.json`.
public struct PhoneticVocabulary: Equatable, Sendable {
    public static let defaultPhonemes: [Unicode.Scalar] = [
        "ء", "ب", "ت", "ث", "ج", "ح", "خ", "د", "ذ", "ر", "ز", "س", "ش", "ص", "ض", "ط", "ظ",
        "ع", "غ", "ف", "ق", "ك", "ل", "م", "ن", "ه", "و", "ي", "ا", "ۦ", "ۥ", "َ", "ُ", "ِ",
        "۪", "ـ", "ٲ", "ڇ", "ں", "۾", "ۜ", "ؙ",
    ].compactMap(\.unicodeScalars.first)

    public static let defaultQPS = PhoneticVocabulary(
        phonemes: defaultPhonemes,
        blankID: 0,
        leadSamples: WhisperMelSpectrogram.leadSamples,
        maxMelFrames: WhisperMelSpectrogram.maxFrames
    )

    public let phonemes: [Unicode.Scalar]
    public let blankID: Int
    public let leadSamples: Int
    public let maxMelFrames: Int

    public init(phonemes: [Unicode.Scalar], blankID: Int = 0, leadSamples: Int = WhisperMelSpectrogram.leadSamples, maxMelFrames: Int = WhisperMelSpectrogram.maxFrames) {
        self.phonemes = phonemes
        self.blankID = blankID
        self.leadSamples = leadSamples
        self.maxMelFrames = maxMelFrames
    }

    public init(jsonData: Data) throws {
        struct Payload: Decodable {
            let phonemes: [String]
            let blank_id: Int?
            let lead_samples: Int?
            let max_mel_frames: Int?
        }
        let decoded = try JSONDecoder().decode(Payload.self, from: jsonData)
        let scalars = decoded.phonemes.compactMap(\.unicodeScalars.first)
        guard scalars.count == decoded.phonemes.count, !scalars.isEmpty else {
            throw PhoneticModelError.invalidVocabulary
        }
        self.init(
            phonemes: scalars,
            blankID: decoded.blank_id ?? 0,
            leadSamples: decoded.lead_samples ?? WhisperMelSpectrogram.leadSamples,
            maxMelFrames: decoded.max_mel_frames ?? WhisperMelSpectrogram.maxFrames
        )
    }

    /// Greedy CTC decode over a `[frameCount, vocabSize]` row-major log-probability buffer.
    public func decodeGreedy(
        logProbabilities: [Float],
        frameCount: Int,
        vocabularySize: Int,
        paddedSampleCount: Int,
        timeOffsetSeconds: Double = 0,
        frameOffset: Int = 0
    ) -> (symbols: [PhoneticSymbol], endSeconds: Double) {
        guard frameCount > 0, vocabularySize > 1 else {
            return ([], timeOffsetSeconds)
        }
        let stepSeconds = Double(paddedSampleCount) / Double(RecitationAudio.sampleRate) / Double(frameCount)
        let leadSeconds = Double(leadSamples) / Double(RecitationAudio.sampleRate)

        var symbols: [PhoneticSymbol] = []
        var previous = blankID
        var lastNonBlankFrame: Int?

        for frame in 0 ..< frameCount {
            let base = frame * vocabularySize
            var bestID = 0
            var bestLogProb = logProbabilities[base]
            for token in 1 ..< vocabularySize {
                let value = logProbabilities[base + token]
                if value > bestLogProb {
                    bestLogProb = value
                    bestID = token
                }
            }
            if bestID != blankID {
                lastNonBlankFrame = frame
            }
            if bestID != previous, bestID != blankID {
                let index = bestID > blankID ? bestID - 1 : bestID
                if index >= 0, index < phonemes.count {
                    let center = timeOffsetSeconds + (Double(frame) + 0.5) * stepSeconds - leadSeconds
                    symbols.append(PhoneticSymbol(
                        symbol: phonemes[index],
                        probability: min(1, max(0, expf(bestLogProb))),
                        centerSeconds: center,
                        frameIndex: frameOffset + frame
                    ))
                }
            }
            previous = bestID
        }

        let endSeconds: Double = if let last = lastNonBlankFrame {
            timeOffsetSeconds + Double(last + 1) * stepSeconds - leadSeconds
        } else {
            timeOffsetSeconds
        }
        return (symbols, endSeconds)
    }
}

/// A phonetic acoustic model that turns 16 kHz mono audio into a timed Quran Phonetic Script transcription.
public protocol PhoneticAcousticModel: Sendable {
    func transcribe(_ samples: [Float]) async throws -> PhoneticTranscription
}

/// Core ML runner for `HisnLabsTajweedV2Int8.mlpackage` (20.6M-parameter Whisper-base CTC model
/// distilled from `obadx/muaalem-model-v3_2`). Uses dynamic mel length `[1, 80, 4..3000]` and
/// defaults to `.cpuOnly` to avoid dynamic-shape Neural Engine recompilation stalls (~13 ms p50 on CPU).
public actor CoreMLPhoneticModel: PhoneticAcousticModel {
    // MARK: Lifecycle

    public init(
        compiledModelURL: URL,
        vocabulary: PhoneticVocabulary = .defaultQPS,
        computeUnits: MLComputeUnits = .cpuOnly
    ) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
        self.vocabulary = vocabulary
    }

    // MARK: Public

    /// Maximum raw samples per window (28 s, leaving room for 0.4 s lead + 0.4 s trail within 30 s).
    public static let maxWindowSamples = 28 * RecitationAudio.sampleRate

    public func transcribe(_ samples: [Float]) async throws -> PhoneticTranscription {
        let audioSeconds = Double(samples.count) / Double(RecitationAudio.sampleRate)
        guard !samples.isEmpty else {
            return PhoneticTranscription(symbols: [], endSeconds: 0, frameCount: 0, audioSeconds: 0)
        }

        var allSymbols: [PhoneticSymbol] = []
        var allQalqalah: [UInt8] = []
        var allGhunnah: [UInt8] = []
        var allTafkheem: [UInt8] = []
        var totalFrames = 0
        var lastEndSeconds = 0.0

        var start = 0
        while start < samples.count {
            let end = min(start + Self.maxWindowSamples, samples.count)
            let timeOffset = Double(start) / Double(RecitationAudio.sampleRate)
            let mel = WhisperMelSpectrogram.compute(
                from: samples[start ..< end],
                leadSamples: vocabulary.leadSamples,
                maxFrames: vocabulary.maxMelFrames
            )

            let inputArray = try MLMultiArray(shape: [1, NSNumber(value: WhisperMelSpectrogram.melBins), NSNumber(value: mel.frameCount)], dataType: .float32)
            let pointer = inputArray.dataPointer.bindMemory(to: Float.self, capacity: mel.features.count)
            mel.features.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    pointer.update(from: base, count: mel.features.count)
                }
            }

            let provider = try MLDictionaryFeatureProvider(dictionary: ["mel": inputArray])
            let output = try await model.prediction(from: provider)
            guard let phonemeArray = output.featureValue(for: "phoneme_log_probs")?.multiArrayValue else {
                throw PhoneticModelError.missingOutput
            }

            let (values, frameCount, vocabSize) = try Self.extractLogProbs(phonemeArray)
            let decoded = vocabulary.decodeGreedy(
                logProbabilities: values,
                frameCount: frameCount,
                vocabularySize: vocabSize,
                paddedSampleCount: mel.paddedSampleCount,
                timeOffsetSeconds: timeOffset,
                frameOffset: totalFrames
            )
            allSymbols.append(contentsOf: decoded.symbols)
            if !decoded.symbols.isEmpty {
                lastEndSeconds = decoded.endSeconds
            }

            if let qArray = output.featureValue(for: "qalqalah_log_probs")?.multiArrayValue {
                allQalqalah.append(contentsOf: Self.argmaxClasses(qArray))
            }
            if let gArray = output.featureValue(for: "ghunnah_log_probs")?.multiArrayValue {
                allGhunnah.append(contentsOf: Self.argmaxClasses(gArray))
            }
            if let tArray = output.featureValue(for: "tafkheem_log_probs")?.multiArrayValue {
                allTafkheem.append(contentsOf: Self.argmaxClasses(tArray))
            }

            totalFrames += frameCount
            start = end
        }

        return PhoneticTranscription(
            symbols: allSymbols,
            endSeconds: lastEndSeconds,
            frameCount: totalFrames,
            audioSeconds: audioSeconds,
            qalqalahFrames: allQalqalah,
            ghunnahFrames: allGhunnah,
            tafkheemFrames: allTafkheem
        )
    }

    // MARK: Private

    private let model: MLModel
    private let vocabulary: PhoneticVocabulary

    private static func extractLogProbs(_ array: MLMultiArray) throws -> (values: [Float], frameCount: Int, vocabSize: Int) {
        guard array.shape.count == 3 else {
            throw PhoneticModelError.unexpectedOutputShape(array.shape.map(\.intValue))
        }
        let frameCount = array.shape[1].intValue
        let vocabSize = array.shape[2].intValue
        let frameStride = array.strides[1].intValue
        let tokenStride = array.strides[2].intValue
        var values = [Float](repeating: 0, count: frameCount * vocabSize)
        if array.dataType == .float32 {
            let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            for f in 0 ..< frameCount {
                let dstRow = f * vocabSize
                let srcRow = f * frameStride
                for t in 0 ..< vocabSize {
                    values[dstRow + t] = ptr[srcRow + t * tokenStride]
                }
            }
        } else {
            for f in 0 ..< frameCount {
                for t in 0 ..< vocabSize {
                    values[f * vocabSize + t] = array[[0, f, t] as [NSNumber]].floatValue
                }
            }
        }
        return (values, frameCount, vocabSize)
    }

    private static func argmaxClasses(_ array: MLMultiArray) -> [UInt8] {
        guard array.shape.count == 3 else { return [] }
        let frameCount = array.shape[1].intValue
        let classCount = array.shape[2].intValue
        let frameStride = array.strides[1].intValue
        let tokenStride = array.strides[2].intValue
        var result = [UInt8](repeating: 0, count: frameCount)
        if array.dataType == .float32 {
            let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            for f in 0 ..< frameCount {
                let row = f * frameStride
                var best = 0
                var bestVal = ptr[row]
                for c in 1 ..< classCount {
                    let v = ptr[row + c * tokenStride]
                    if v > bestVal {
                        bestVal = v
                        best = c
                    }
                }
                result[f] = UInt8(min(best, 255))
            }
        }
        return result
    }
}

public enum PhoneticModelError: Error, Equatable {
    case invalidVocabulary
    case missingOutput
    case unexpectedOutputShape([Int])
}
