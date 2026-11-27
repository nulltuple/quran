//
//  WordStudyReaderFollowerTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import QuranKit
import XCTest
@testable import WordStudyFeature

@MainActor
final class WordStudyReaderFollowerTests: XCTestCase {
    // MARK: Internal

    func test_theOriginDoesNotMoveTheReader() {
        let follower = WordStudyReaderFollower(origin: verse(2, 3)) { self.shown.append($0) }

        follower.show(verse(2, 3))
        follower.returnToOrigin()

        XCTAssertEqual(shown, [])
    }

    func test_anotherWordMovesTheReaderOnce() {
        let follower = WordStudyReaderFollower(origin: verse(2, 3)) { self.shown.append($0) }

        follower.show(verse(7, 40))
        follower.show(verse(7, 40))

        XCTAssertEqual(shown, [verse(7, 40)])
        XCTAssertEqual(follower.shownVerse, verse(7, 40))
    }

    func test_closingTheSheetReturnsTheReaderToTheOrigin() {
        let follower = WordStudyReaderFollower(origin: verse(2, 3)) { self.shown.append($0) }
        follower.show(verse(7, 40))

        follower.returnToOrigin()

        XCTAssertEqual(shown, [verse(7, 40), verse(2, 3)])
    }

    func test_goingBackToTheFirstStudyReturnsTheReaderAndClosingThenDoesNothing() {
        let follower = WordStudyReaderFollower(origin: verse(2, 3)) { self.shown.append($0) }
        follower.show(verse(7, 40))
        // The first study reappears when the reader goes back to it.
        follower.show(verse(2, 3))

        follower.returnToOrigin()

        XCTAssertEqual(shown, [verse(7, 40), verse(2, 3)])
    }

    // MARK: Private

    private var shown: [AyahNumber] = []

    private func verse(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: sura, ayah: ayah)!
    }
}
