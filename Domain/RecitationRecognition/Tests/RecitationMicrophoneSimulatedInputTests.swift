//
//  RecitationMicrophoneSimulatedInputTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import TestResources
import XCTest
@testable import RecitationRecognition

/// The developer loopback that plays audio files into a recording instead of the microphone.
@MainActor
final class RecitationMicrophoneSimulatedInputTests: XCTestCase {
    func testTheDefaultListsCommaSeparatedFiles() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        XCTAssertNil(RecitationMicrophone.simulatedInputFiles(defaults))
        defaults.set("/a/one.mp3,/b/two.mp3", forKey: RecitationMicrophone.simulatedInputKey)
        XCTAssertEqual(RecitationMicrophone.simulatedInputFiles(defaults)?.map(\.path), ["/a/one.mp3", "/b/two.mp3"])
    }

    func testTheSignalPutsAQuietGapBeforeEachClip() {
        let signal = RecitationMicrophone.simulatedSignal([[0.5, 0.5], [0.7]])
        let gap = RecitationAudio.sampleRate
        XCTAssertEqual(signal.count, 2 * gap + 3)
        XCTAssertLessThanOrEqual(SpeechLevel.peak(of: signal[0 ..< gap]), RecitationMicrophone.simulatedNoiseAmplitude)
        XCTAssertEqual(Array(signal[gap ..< gap + 2]), [0.5, 0.5])
        XCTAssertEqual(signal.last, 0.7)
    }

    func testAFilePlaysIntoTheRecordingInRealTime() async throws {
        let microphone = RecitationMicrophone(keepingLatestSeconds: 10)
        try microphone.startSimulatedInput([TestResources.resourceURL("recitation/Husary_112001.mp3")])
        XCTAssertTrue(microphone.isRecording)
        try await Task.sleep(for: .seconds(2))
        XCTAssertGreaterThan(microphone.recentPeak(seconds: 1), 0.05, "the clip is playing after the 1 s gap")
        let samples = try microphone.stop()
        XCTAssertFalse(microphone.isRecording)
        // About 2 s were fed, in real time, not the whole clip at once.
        XCTAssertGreaterThan(samples.count, RecitationAudio.sampleRate * 3 / 2)
        XCTAssertLessThan(samples.count, RecitationAudio.sampleRate * 3)
    }
}
