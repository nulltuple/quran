//
//  WordTests.swift
//
//
//  Created by Claude Code on 2026-11-25.
//

import QuranKit
import XCTest

final class WordTests: XCTestCase {
    func test_wordsOrderByVerseThenWordNumber() throws {
        let quran = Quran.hafsMadani1405
        let first = try XCTUnwrap(AyahNumber(quran: quran, sura: 1, ayah: 1))
        let second = try XCTUnwrap(AyahNumber(quran: quran, sura: 1, ayah: 2))
        XCTAssertLessThan(Word(verse: first, wordNumber: 4), Word(verse: second, wordNumber: 1))
        XCTAssertLessThan(Word(verse: first, wordNumber: 1), Word(verse: first, wordNumber: 2))
    }

    /// Words cross concurrency boundaries (Arabican's content store returns them from database reads).
    func test_wordIsSendable() async throws {
        let verse = try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 1))
        let word = Word(verse: verse, wordNumber: 1)
        let sent = await Task.detached { word }.value
        XCTAssertEqual(sent, word)
    }
}
