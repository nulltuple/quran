//
//  RecitationAcousticModel.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import CoreML
import Foundation

/// A speech model that turns a window of 16 kHz mono samples into CTC log-probabilities.
public protocol RecitationAcousticModel: Sendable {
    /// The longest window one call accepts, in samples.
    var windowSampleCount: Int { get }

    /// The samples one output frame covers; `windowSampleCount` is a multiple of it.
    var samplesPerFrame: Int { get }

    /// Log-probabilities for the frames that cover `samples` (at most `windowSampleCount` of them).
    func logProbabilities(for samples: ArraySlice<Float>) async throws -> CTCLogProbabilities
}

/// The Tilawi FastConformer CTC model converted to Core ML by `Tools/recitation-model.py convert`:
/// inputs `audio_signal` float32 [1, 320000] (20 s, zero padded) and `length` int32 [1]; output
/// `log_probs` float32 [1, 251, 1025]. A frame covers 1,280 samples (80 ms). The package computes in
/// float32 with int8 (iOS 16) or int4 (iOS 18) weights; float16 compute was wrong on the CPU.
public actor CoreMLRecitationModel: RecitationAcousticModel {
    // MARK: Lifecycle

    /// `compiledModelURL`: an `.mlmodelc` directory (`MLModel.compileModel(at:)` of the package).
    public init(compiledModelURL: URL, computeUnits: MLComputeUnits = .all) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
    }

    // MARK: Public

    public static let samplesPerFrame = 1280

    public nonisolated let windowSampleCount = 320_000

    public nonisolated var samplesPerFrame: Int { Self.samplesPerFrame }

    public func logProbabilities(for samples: ArraySlice<Float>) async throws -> CTCLogProbabilities {
        precondition(samples.count <= windowSampleCount, "a window holds at most \(windowSampleCount) samples")
        let audio = try MLMultiArray(shape: [1, NSNumber(value: windowSampleCount)], dataType: .float32)
        let audioPointer = audio.dataPointer.bindMemory(to: Float.self, capacity: windowSampleCount)
        audioPointer.initialize(repeating: 0, count: windowSampleCount)
        samples.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                audioPointer.update(from: base, count: buffer.count)
            }
        }
        let length = try MLMultiArray(shape: [1], dataType: .int32)
        length[0] = NSNumber(value: samples.count)

        let input = try MLDictionaryFeatureProvider(dictionary: ["audio_signal": audio, "length": length])
        let output = try await model.prediction(from: input)
        guard let logProbabilities = output.featureValue(for: "log_probs")?.multiArrayValue else {
            throw RecitationModelError.missingOutput
        }
        return try Self.frames(of: logProbabilities, covering: samples.count)
    }

    // MARK: Internal

    /// The frames of `array` ([1, frames, vocabulary], float32 or float16) that cover `sampleCount`.
    static func frames(of array: MLMultiArray, covering sampleCount: Int) throws -> CTCLogProbabilities {
        guard array.shape.count == 3 else {
            throw RecitationModelError.unexpectedOutputShape(array.shape.map(\.intValue))
        }
        let totalFrames = array.shape[1].intValue
        let vocabularySize = array.shape[2].intValue
        let frameCount = min(totalFrames, (sampleCount + samplesPerFrame - 1) / samplesPerFrame)
        let frameStride = array.strides[1].intValue
        let tokenStride = array.strides[2].intValue
        var values = [Float](repeating: 0, count: frameCount * vocabularySize)
        switch array.dataType {
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            for frame in 0 ..< frameCount {
                for token in 0 ..< vocabularySize {
                    values[frame * vocabularySize + token] = pointer[frame * frameStride + token * tokenStride]
                }
            }
        default:
            for frame in 0 ..< frameCount {
                for token in 0 ..< vocabularySize {
                    values[frame * vocabularySize + token] = array[[0, frame, token] as [NSNumber]].floatValue
                }
            }
        }
        return CTCLogProbabilities(frameCount: frameCount, vocabularySize: vocabularySize, values: values)
    }

    // MARK: Private

    private let model: MLModel
}

public enum RecitationModelError: Error, Equatable {
    case missingOutput
    case unexpectedOutputShape([Int])
}
