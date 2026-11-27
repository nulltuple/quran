//
//  RecitationAudioTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import XCTest
@testable import RecitationRecognition

final class RecitationAudioTests: XCTestCase {
    func testMicrophoneSamplesAreResampledTo16Kilohertz() throws {
        // One second of a 440 Hz tone at 48 kHz, as a microphone delivers it.
        let input = (0 ..< 48000).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48000)) * 0.5 }
        let output = try RecitationAudio.resample(mono: input, sampleRate: 48000)
        XCTAssertEqual(Double(output.count), 16000, accuracy: 64)
        // The tone survives: its peak stays near 0.5.
        XCTAssertEqual(Double(output.dropFirst(100).max() ?? 0), 0.5, accuracy: 0.05)
    }

    func testSamplesAlreadyAt16KilohertzKeepTheirLength() throws {
        let input = [Float](repeating: 0.25, count: 8000)
        XCTAssertEqual(try RecitationAudio.resample(mono: input, sampleRate: 16000).count, 8000)
    }

    func testNoSamplesGiveNoSamples() throws {
        XCTAssertEqual(try RecitationAudio.resample(mono: [], sampleRate: 48000), [])
    }
}
