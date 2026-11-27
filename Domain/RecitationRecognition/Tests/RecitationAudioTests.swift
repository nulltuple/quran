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

/// Where `RecitationRecognizer` cuts a long recording into model windows.
final class RecitationWindowEndTests: XCTestCase {
    private let frame = 1280
    private let length = 320_000

    func testAShortRecordingIsOneWindow() {
        let samples = [Float](repeating: 0.5, count: length - 1)
        XCTAssertEqual(RecitationRecognizer.windowEnd(samples, from: 0, length: length, frame: frame), samples.count)
    }

    func testALongRecordingIsCutInThePauseBeforeTheWindowEnds() {
        let rate = RecitationAudio.sampleRate
        var samples = [Float](repeating: 0.5, count: 25 * rate)
        let pause = 18 * rate ..< 18 * rate + 2 * rate / 5
        samples.replaceSubrange(pause, with: [Float](repeating: 0, count: pause.count))
        let end = RecitationRecognizer.windowEnd(samples, from: frame * 3, length: length, frame: frame)
        XCTAssertTrue(pause.contains(end - 1), "\(end) ends inside the pause")
        XCTAssertEqual((end - frame * 3) % frame, 0, "whole frames from the window's start")
    }

    func testWithoutAPauseTheWindowHasTheModelsLength() {
        let samples = [Float](repeating: 0.5, count: 25 * RecitationAudio.sampleRate)
        XCTAssertEqual(RecitationRecognizer.windowEnd(samples, from: 0, length: length, frame: frame), length)
    }
}
