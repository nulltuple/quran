//
//  ExpectedWordsReaderTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranKit
import QuranResources
import TestResources
import VerseTextPersistence
import WordTextService
import XCTest
@testable import RecitationRecognition

/// The reader over the bundled Uthmani text and the test copy of `word_by_word.db` (suras 1, 2:1–30,
/// 13:37, 15:7, 37:130 and 78–114).
final class ExpectedWordsReaderTests: XCTestCase {
    // MARK: Internal

    static func makeReader() -> ExpectedWordsReader {
        ExpectedWordsReader(
            uthmaniText: GRDBQuranVerseTextPersistence(fileURL: QuranResources.quranUthmaniV2Database),
            wordByWord: WordByWordService(fileURL: TestResources.resourceURL("word_by_word.db"))
        )
    }

    func testEachUthmaniTokenIsOneWordInQuranOrder() async throws {
        let words = try await Self.makeReader().expectedWords(for: [verse(1, 3), verse(1, 2)])
        XCTAssertEqual(words.map(\.text), ["ٱلۡحَمۡدُ", "لِلَّهِ", "رَبِّ", "ٱلۡعَٰلَمِينَ", "ٱلرَّحۡمَٰنِ", "ٱلرَّحِيمِ"])
        XCTAssertEqual(words.flatMap(\.words), [
            word(1, 2, 1), word(1, 2, 2), word(1, 2, 3), word(1, 2, 4), word(1, 3, 1), word(1, 3, 2),
        ])
    }

    func testATokenThatWritesTwoWordsCoversBoth() async throws {
        let words = try await Self.makeReader().expectedWords(for: [verse(15, 7)])
        XCTAssertEqual(words.first, ExpectedWordText(words: [word(15, 7, 1), word(15, 7, 2)], text: "لَّوۡمَا"))
        XCTAssertEqual(words.flatMap(\.words), (1 ... 8).map { word(15, 7, $0) })
    }

    func testAWordWrittenAsTwoTokensJoinsThem() async throws {
        let words = try await Self.makeReader().expectedWords(for: [verse(37, 130)])
        XCTAssertEqual(words.last, ExpectedWordText(words: [word(37, 130, 3)], text: "إِلۡ يَاسِينَ"))
        XCTAssertEqual(words.count, 3)
    }

    func testAVerseWithoutWordsThrows() async throws {
        do {
            _ = try await Self.makeReader().expectedWords(for: [verse(3, 1)])
            XCTFail("3:1 is not in the test word database")
        } catch {
            XCTAssertEqual(error as? ExpectedWordsError, .noWordLayout(verse(3, 1)))
        }
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405

    private func verse(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: verse(sura, ayah), wordNumber: number)
    }
}
