//
//  PracticePlanTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranKit
import XCTest
@testable import MemorizationService

final class PracticePlanTests: XCTestCase {
    // MARK: Internal

    func testStraightOrderPracticesEachAyahOnceInQuranOrder() {
        let steps = PracticePlan.steps(for: [verse(3), verse(1), verse(2)], order: .straight)
        XCTAssertEqual(steps.map(\.verses), [[verse(1)], [verse(2)], [verse(3)]])
        XCTAssertFalse(steps.contains(where: \.isReview))
    }

    func testCumulativeOrderAddsEachAyahAloneThenEverythingSoFar() {
        let steps = PracticePlan.steps(for: [verse(1), verse(2), verse(3)], order: .cumulative)
        XCTAssertEqual(steps.map(\.verses), [
            [verse(1)],
            [verse(2)],
            [verse(1), verse(2)],
            [verse(3)],
            [verse(1), verse(2), verse(3)],
        ])
        XCTAssertEqual(steps.map(\.isReview), [false, false, true, false, true])
    }

    func testCumulativeOrderOfOneAyahIsOneStep() {
        XCTAssertEqual(PracticePlan.steps(for: [verse(1)], order: .cumulative).map(\.verses), [[verse(1)]])
        XCTAssertEqual(PracticePlan.steps(for: [], order: .cumulative), [])
    }

    func testCueLevelsKeepFewerWordsVisible() {
        XCTAssertEqual(PracticeCueLevel.alternateWords.cueWords(wordCount: 5), [1, 3, 5])
        XCTAssertEqual(PracticeCueLevel.alternateWords.cueWords(wordCount: 4), [1, 3])
        XCTAssertEqual(PracticeCueLevel.firstWord.cueWords(wordCount: 5), [1])
        XCTAssertEqual(PracticeCueLevel.none.cueWords(wordCount: 5), [])
        XCTAssertEqual(PracticeCueLevel.firstWord.cueWords(wordCount: 0), [], "an ayah without words has no cue")
    }

    // MARK: Private

    private func verse(_ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: ayah)!
    }
}
