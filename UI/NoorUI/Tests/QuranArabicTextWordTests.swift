//
//  QuranArabicTextWordTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import QuranKit
import QuranText
import XCTest
@testable import NoorUI

final class QuranArabicTextWordTests: XCTestCase {
    func testWordRangeCountsSpaceSeparatedWordsFromOne() {
        let text = "ذَٰلِكَ ٱلۡكِتَٰبُ لَا رَيۡبَۛ فِيهِۛ"

        XCTAssertEqual(text.wordRange(at: 1).map { String(text[$0]) }, "ذَٰلِكَ")
        XCTAssertEqual(text.wordRange(at: 4).map { String(text[$0]) }, "رَيۡبَۛ")
        XCTAssertEqual(text.wordRange(at: 5).map { String(text[$0]) }, "فِيهِۛ")
    }

    func testWordRangeIgnoresRepeatedSpaces() {
        let text = " one  two "

        XCTAssertEqual(text.wordRange(at: 2).map { String(text[$0]) }, "two")
    }

    func testNoWordRangeOutsideTheText() {
        XCTAssertNil("one two".wordRange(at: 0))
        XCTAssertNil("one two".wordRange(at: 3))
    }

    func testHighlightsTheRecitedWord() {
        let text = QuranText("بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ ١")
        let view = QuranArabicText(
            verse: Quran.hafsMadani1405.suras[0].verses[0],
            text: text,
            quranFont: .uthmanicHafs,
            fontSize: .medium,
            highlightedWords: 2 ... 2
        )

        XCTAssertEqual(view.wordHighlighting.map { String(text.text[$0.range]) }, ["ٱللَّهِ"])
    }

    func testHighlightsAWordWrittenInTwoParts() {
        // 37:130 writes the one word إِلۡ يَاسِينَ as two tokens.
        let text = QuranText("سَلَٰمٌ عَلَىٰٓ إِلۡ يَاسِينَ ١٣٠")
        let view = QuranArabicText(
            verse: Quran.hafsMadani1405.suras[36].verses[129],
            text: text,
            quranFont: .uthmanicHafs,
            fontSize: .medium,
            highlightedWords: 3 ... 4
        )

        XCTAssertEqual(view.wordHighlighting.map { String(text.text[$0.range]) }, ["إِلۡ يَاسِينَ"])
    }

    func testNoHighlightWithoutARecitedWord() {
        let view = QuranArabicText(
            verse: Quran.hafsMadani1405.suras[0].verses[0],
            text: QuranText("بِسۡمِ ٱللَّهِ"),
            quranFont: .uthmanicHafs,
            fontSize: .medium
        )

        XCTAssertTrue(view.wordHighlighting.isEmpty)
    }
}
