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
            (1 ... 7).map { words[word(2, 2, $0)]?.first.wordNumber },
            [1, 2, 3, 4, 6, 8, 9]
        )
    }

    func test_imageWordsSkipTheRubElHizbGlyph() async throws {
        // 2:26 starts a quarter; the ۞ sign is its first glyph.
        let words = try await service.imageWords(for: [verse(2, 26)], reading: .hafs_1405)

        XCTAssertEqual(words[word(2, 26, 1)]?.first.wordNumber, 2)
    }

    func test_imageWordsCoverAWordDrawnAsTwoGlyphs() async throws {
        // 37:130 draws its third word, إِلْ يَاسِينَ, as two glyphs; the heuristic mapping left it unmapped.
        let words = try await service.imageWords(for: [verse(37, 130)], reading: .hafs_1405)

        XCTAssertEqual(words[word(37, 130, 3)], ImageWordGlyphs(first: word(37, 130, 3), last: word(37, 130, 4)))
        XCTAssertEqual(words.count, 3)
    }

    func test_imageWordsShareTheGlyphOfTwoWordsDrawnAsOne() async throws {
        // 13:37 draws بَعْدَ مَا, QUL's words 8 and 9, as one glyph after a pause mark.
        let words = try await service.imageWords(for: [verse(13, 37)], reading: .hafs_1405)

        XCTAssertEqual(words[word(13, 37, 8)]?.first, word(13, 37, 9))
        XCTAssertEqual(words[word(13, 37, 9)]?.first, word(13, 37, 9))
        XCTAssertEqual(words[word(13, 37, 10)]?.first, word(13, 37, 10))
    }

    func test_wordAtAGlyph() async throws {
        let wordAtGlyph = { glyph in try await self.service.word(atImageGlyph: self.word(2, 2, glyph), reading: .hafs_1405) }

        let afterPauseMarks = try await wordAtGlyph(8)
        let pauseMark = try await wordAtGlyph(5)
        let ayahNumber = try await wordAtGlyph(10)
        XCTAssertEqual(afterPauseMarks, word(2, 2, 6))
        XCTAssertNil(pauseMark, "A pause mark is not a word")
        XCTAssertNil(ayahNumber, "The ayah-number glyph is not a word")
    }

    func test_noWordAtAGlyphOfAnotherReading() async throws {
        let found = try await service.word(atImageGlyph: word(2, 2, 1), reading: .hafs_1421)

        XCTAssertNil(found)
    }

    func test_everyWordHasMeaningsEvenWhereTheHeuristicFailed() async throws {
        // QUL's translations skip 2:181 word 4; the builder realigned it with the recitation.
        let english = try await service.meanings(for: [verse(2, 181)], language: .english)
        let bengali = try await service.meanings(for: [verse(2, 181)], language: .bengali)

        XCTAssertEqual(english.count, 14)
        XCTAssertEqual(bengali.count, 14)
        XCTAssertEqual(english[word(2, 181, 3)], "after what")
        XCTAssertEqual(english[word(2, 181, 4)], "after what", "مَا shares بَعْدَ's meaning")
        XCTAssertEqual(english[word(2, 181, 5)], "he (has) heard [it]")
    }

    func test_textInEachTypeAndLanguage() async throws {
        let word = word(1, 1, 2)

        let english = try await service.text(for: word, type: .translation, language: .english)
        let bengali = try await service.text(for: word, type: .translation, language: .bengali)
        let transliteration = try await service.text(for: word, type: .transliteration, language: .off)
        let off = try await service.text(for: word, type: .translation, language: .off)
        XCTAssertEqual(english, "(of) Allah")
        XCTAssertEqual(bengali, "আল্লাহ (র)")
        XCTAssertEqual(transliteration, "l-lahi")
        XCTAssertNil(off)
    }

    func test_textLayoutsRegroupTheSixAyahsWhoseTextSplitsDifferently() async throws {
        let layouts = try await service.textLayouts(for: [verse(15, 7), verse(37, 130), verse(1, 1)])

        let lawma = try XCTUnwrap(layouts[verse(15, 7)]?.units(tokenCount: 7))
        XCTAssertEqual(lawma.first, UthmaniWordLayout.Unit(tokens: 1 ... 1, words: 1 ... 2))
        XCTAssertEqual(lawma.count, 7)
        let ilyasin = try XCTUnwrap(layouts[verse(37, 130)]?.units(tokenCount: 4))
        XCTAssertEqual(ilyasin.last, UthmaniWordLayout.Unit(tokens: 3 ... 4, words: 3 ... 3))
        XCTAssertEqual(layouts[verse(1, 1)]?.units(tokenCount: 4)?.count, 4)
        XCTAssertNil(layouts[verse(1, 1)]?.units(tokenCount: 5), "A text splitting otherwise gets no words")
        XCTAssertNil(layouts[verse(15, 7)]?.units(tokenCount: 8))
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
