//
//  WhisperMelSpectrogramTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import XCTest
@testable import RecitationRecognition

final class WhisperMelSpectrogramTests: XCTestCase {
    func testMatchesHuggingFaceWhisperFeatureExtractorOnSineWave() {
        // 1 s 440 Hz sine wave, amplitude 0.25 (exact match to Python reference probes).
        let n = 16000
        let samples: [Float] = (0 ..< n).map { i in
            0.25 * sinf(2.0 * .pi * 440.0 * Float(i) / 16000.0)
        }
        let result = WhisperMelSpectrogram.compute(from: samples[...])

        XCTAssertEqual(result.frameCount, 180)
        XCTAssertEqual(result.paddedSampleCount, 16000 + 2 * 6400)
        XCTAssertEqual(result.features.count, 80 * 180)

        let minVal = result.features.min() ?? 0
        let maxVal = result.features.max() ?? 0
        let meanVal = result.features.reduce(0, +) / Float(result.features.count)

        XCTAssertEqual(minVal, -0.712311, accuracy: 1e-3)
        XCTAssertEqual(maxVal, 1.287689, accuracy: 1e-3)
        XCTAssertEqual(meanVal, -0.642703, accuracy: 1e-3)

        // Probe specific (melBin, frame) coordinates verified against HF WhisperFeatureExtractor.
        XCTAssertEqual(result.features[0 * 180 + 0], -0.712311, accuracy: 1e-3)
        XCTAssertEqual(result.features[10 * 180 + 50], 1.198223, accuracy: 1e-3)
        XCTAssertEqual(result.features[20 * 180 + 80], -0.712311, accuracy: 1e-3)
        XCTAssertEqual(result.features[40 * 180 + 100], -0.712311, accuracy: 1e-3)
        XCTAssertEqual(result.features[79 * 180 + 179], -0.712311, accuracy: 1e-3)
    }

    func testSilenceProducesFiniteEvenFrameFeatures() {
        let silence = [Float](repeating: 0, count: 8000)
        let result = WhisperMelSpectrogram.compute(from: silence[...])
        XCTAssertEqual(result.frameCount % 2, 0)
        XCTAssertGreaterThanOrEqual(result.frameCount, 4)
        XCTAssertTrue(result.features.allSatisfy(\.isFinite))
    }
}
