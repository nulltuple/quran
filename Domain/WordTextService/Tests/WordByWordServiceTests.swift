//
//  WordByWordServiceTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import QuranKit
import QuranText
import TestResources
import WordTextService
import XCTest

final class WordByWordServiceTests: XCTestCase {
    // MARK: Internal

    func test_meaningsInEnglish() async throws {
        let meanings = try await service.meanings(for: [verse(2, 2)], language: .english)

        XCTAssertEqual(meanings[word(2, 2, 1)], "That")
        XCTAssertEqual(meanings[word(2, 2, 7)], "for the God-conscious")
        XCTAssertNil(meanings[word(2, 2, 8)], "The ayah-number marker has no meaning")
    }

    func test_meaningsInBengali() async throws {
        let meanings = try await service.meanings(for: [verse(1, 1)], language: .bengali)

        XCTAssertEqual(meanings[word(1, 1, 1)], "নামে")
        XCTAssertEqual(meanings.count, 4)
    }

    func test_noMeaningsWhenOff() async throws {
        let meanings = try await service.meanings(for: [verse(1, 1)], language: .off)

        XCTAssertEqual(meanings, [:])
    }

    func test_meaningsOnlyForTheRequestedVerses() async throws {
        let meanings = try await service.meanings(for: [verse(1, 7), verse(2, 2)], language: .english)

        XCTAssertEqual(Set(meanings.keys.map(\.verse)), [verse(1, 7), verse(2, 2)])
    }

    func test_imageWordsSkipPauseMarkGlyphs() async throws {
        // In the Madani 1405 images, 2:2 has pause marks after its 4th and 5th words.
        let words = try await service.imageWords(for: [verse(2, 2)], reading: .hafs_1405)

        XCTAssertEqual(
            (1 ... 7).map { words[word(2, 2, $0)]?.wordNumber },
            [1, 2, 3, 4, 6, 8, 9]
        )
    }

    func test_imageWordsSkipTheRubElHizbGlyph() async throws {
        // 2:26 starts a quarter; the ۞ sign is its first glyph.
        let words = try await service.imageWords(for: [verse(2, 26)], reading: .hafs_1405)

        XCTAssertEqual(words[word(2, 26, 1)]?.wordNumber, 2)
    }

    func test_noImageWordsForAnotherReading() async throws {
        let words = try await service.imageWords(for: [verse(2, 2)], reading: .hafs_1421)

        XCTAssertEqual(words, [:])
    }

    func test_wordCounts() async throws {
        let counts = try await service.wordCounts(for: [verse(1, 1), verse(2, 2)])

        XCTAssertEqual(counts, [verse(1, 1): 4, verse(2, 2): 7])
    }

    // MARK: Private

    private let service = WordByWordService(fileURL: TestResources.resourceURL("word_by_word.db"))
    private let quran = Quran.hafsMadani1405

    private func verse(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: verse(sura, ayah), wordNumber: number)
    }
}
