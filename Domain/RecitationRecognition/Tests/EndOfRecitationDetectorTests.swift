//
//  EndOfRecitationDetectorTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import RecitationRecognition
import XCTest

final class EndOfRecitationDetectorTests: XCTestCase {
    func testAPauseAfterSpeechEndsTheRecitation() {
        var detector = EndOfRecitationDetector()
        // 3 s of speech, then quiet, sampled every 0.2 s.
        let decisions = levels(speech: 3, quiet: 3).map { detector.update(elapsed: $0.time, peak: $0.peak) }
        let finished = decisions.firstIndex(of: .finished)
        XCTAssertEqual(finished.map { Double($0) * 0.2 } ?? -1, 5, accuracy: 0.01, "2 s after the speech stopped")
        XCTAssertFalse(decisions.prefix(finished ?? 0).contains(.finished))
    }

    func testShortBreathsBetweenWordsKeepListening() {
        var detector = EndOfRecitationDetector()
        var decisions: [EndOfRecitationDetector.Decision] = []
        // Speech with a 1.4 s pause every 2 s, for 20 s.
        for step in 0 ..< 100 {
            let time = Double(step) * 0.2
            let peak: Float = time.truncatingRemainder(dividingBy: 3.4) < 2 ? 0.5 : 0.01
            decisions.append(detector.update(elapsed: time, peak: peak))
        }
        XCTAssertEqual(Set(decisions), [.keepListening])
    }

    func testQuietIsRelativeToTheLoudestLevel() {
        var detector = EndOfRecitationDetector()
        // A loud room (0.08) under loud speech (0.9): the room counts as quiet.
        var decisions: [EndOfRecitationDetector.Decision] = []
        for step in 0 ..< 40 {
            let time = Double(step) * 0.2
            decisions.append(detector.update(elapsed: time, peak: time < 3 ? 0.9 : 0.08))
        }
        XCTAssertTrue(decisions.contains(.finished))
    }

    func testQuietIsMeasuredFromTheRoomsNoise() {
        // A distant speaker barely above a noisy room (as the simulator hears the Mac's speakers):
        // noise 0.01, speech 0.04, then the noise again.
        var detector = EndOfRecitationDetector()
        var decisions: [EndOfRecitationDetector.Decision] = []
        for step in 0 ..< 50 {
            let time = Double(step) * 0.2
            let peak: Float = (1 ..< 5).contains(time) ? 0.04 : 0.01
            decisions.append(detector.update(elapsed: time, peak: peak))
        }
        let finished = decisions.firstIndex(of: .finished).map { Double($0) * 0.2 }
        XCTAssertEqual(finished ?? -1, 7, accuracy: 0.01, "2 s after the speech stopped")
    }

    func testANoisyRoomAloneIsNotSpeech() {
        // Room noise between 0.02 and 0.04, well above the speech floor, and nobody reciting.
        var detector = EndOfRecitationDetector()
        var decision = EndOfRecitationDetector.Decision.keepListening
        var time = 0.0
        while decision == .keepListening, time < 20 {
            decision = detector.update(elapsed: time, peak: [0.02, 0.03, 0.04][Int(time * 5) % 3])
            time += 0.2
        }
        XCTAssertEqual(decision, .heardNothing)
        XCTAssertFalse(detector.heardSpeech)
    }

    func testSilenceGivesUpWithoutSpeech() {
        var detector = EndOfRecitationDetector()
        var decision = EndOfRecitationDetector.Decision.keepListening
        var time = 0.0
        while decision == .keepListening, time < 20 {
            decision = detector.update(elapsed: time, peak: 0.002)
            time += 0.2
        }
        XCTAssertEqual(decision, .heardNothing)
        XCTAssertEqual(time, 8.2, accuracy: 0.01)
        XCTAssertFalse(detector.heardSpeech)
    }

    func testTheTimeLimitEndsALongRecitation() {
        var detector = EndOfRecitationDetector(maximumSeconds: 10)
        XCTAssertEqual(detector.update(elapsed: 0.2, peak: 0.01), .keepListening)
        XCTAssertEqual(detector.update(elapsed: 9.8, peak: 0.6), .keepListening)
        XCTAssertEqual(detector.update(elapsed: 10, peak: 0.6), .finished)
    }

    // MARK: Private

    private func levels(speech: Double, quiet: Double) -> [(time: Double, peak: Float)] {
        stride(from: 0.0, to: speech + quiet, by: 0.2).map { time in
            (time, time < speech ? 0.4 : 0.004)
        }
    }
}
