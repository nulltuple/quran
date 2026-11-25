//
//  AyahWordTimingsTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import QuranAudio
import XCTest

final class AyahWordTimingsTests: XCTestCase {
    func test_noWordBeforeTheFirstWordStarts() {
        let timings = AyahWordTimings([WordTiming(word: 1, start: 2, end: 3)])

        XCTAssertNil(timings.word(at: 1.99))
    }

    func test_eachWordFromItsStart() {
        let timings = AyahWordTimings([
            WordTiming(word: 1, start: 0, end: 0.75),
            WordTiming(word: 2, start: 0.8, end: 1.55),
            WordTiming(word: 3, start: 1.6, end: 2.71),
        ])

        XCTAssertEqual(timings.word(at: 0), 1)
        XCTAssertEqual(timings.word(at: 0.8), 2)
        XCTAssertEqual(timings.word(at: 2), 3)
    }

    func test_aPauseBetweenWordsKeepsThePreviousWord() {
        let timings = AyahWordTimings([
            WordTiming(word: 1, start: 0, end: 0.75),
            WordTiming(word: 2, start: 0.8, end: 1.55),
        ])

        XCTAssertEqual(timings.word(at: 0.77), 1)
        XCTAssertEqual(timings.word(at: 9), 2, "The last word stays until the next ayah")
    }

    func test_aRepeatedWordIsRecitedAgain() {
        // QUL 3:2, where the reciter goes back to word 1 after word 2.
        let timings = AyahWordTimings([
            WordTiming(word: 2, start: 6.56, end: 6.83),
            WordTiming(word: 1, start: 6.88, end: 7.43),
            WordTiming(word: 2, start: 7.48, end: 9.47),
        ])

        XCTAssertEqual(timings.word(at: 6.6), 2)
        XCTAssertEqual(timings.word(at: 7), 1)
        XCTAssertEqual(timings.word(at: 8), 2)
    }

    func test_wordsOutOfOrderAreSortedByStart() {
        let timings = AyahWordTimings([
            WordTiming(word: 2, start: 1, end: 2),
            WordTiming(word: 1, start: 0, end: 1),
        ])

        XCTAssertEqual(timings.words.map(\.word), [1, 2])
        XCTAssertEqual(timings.word(at: 0.5), 1)
    }

    func test_noWordsHasNoWord() {
        XCTAssertNil(AyahWordTimings([]).word(at: 1))
    }
}
