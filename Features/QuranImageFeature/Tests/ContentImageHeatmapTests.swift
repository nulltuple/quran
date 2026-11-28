//
//  ContentImageHeatmapTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import QuranAnnotations
import QuranKit
import WordTextService
import XCTest
@testable import QuranImageFeature

@MainActor
final class ContentImageHeatmapTests: XCTestCase {
    func testWordHeatmapMapsCanonicalWordToImageGlyphsAndSuppressesOnTajweed() throws {
        let quran = Quran.hafsMadani1405
        let verse = try XCTUnwrap(AyahNumber(quran: quran, sura: 2, ayah: 7))
        let canonical = Word(verse: verse, wordNumber: 7)
        let glyphStart = Word(verse: verse, wordNumber: 8)
        let glyphEnd = Word(verse: verse, wordNumber: 9)

        let heatmap = MistakeHeatmapOverlay(
            verseLevels: [verse: .high],
            wordLevels: [canonical: .high]
        )
        let mapping = [canonical: ImageWordGlyphs(first: glyphStart, last: glyphEnd)]

        let madaniHighlights = ContentImageViewModel.wordHeatmapHighlights(
            heatmap,
            reading: .hafs_1405,
            imageWords: mapping
        )
        XCTAssertEqual(madaniHighlights.count, 1)
        XCTAssertEqual(madaniHighlights[0].first, glyphStart)
        XCTAssertEqual(madaniHighlights[0].last, glyphEnd)

        // Overlay must NEVER mix with Tajweed Mushaf coloring.
        let tajweedHighlights = ContentImageViewModel.wordHeatmapHighlights(
            heatmap,
            reading: .tajweed,
            imageWords: mapping
        )
        XCTAssertTrue(tajweedHighlights.isEmpty)
    }

    func testPracticeMistakeHighlightsRenderOnlyForRevealedWords() throws {
        let quran = Quran.hafsMadani1405
        let verse = try XCTUnwrap(AyahNumber(quran: quran, sura: 42, ayah: 8))
        let revealedMistake = Word(verse: verse, wordNumber: 13)
        let hiddenMistake = Word(verse: verse, wordNumber: 14)

        let mask = PracticeMask(
            hiddenVerses: [],
            partialVerse: verse,
            revealedWords: 13,
            mistakeWords: [revealedMistake, hiddenMistake]
        )
        let highlights = ContentImageViewModel.practiceMistakeHighlights(
            mask,
            maskedWords: [hiddenMistake],
            imageWords: [:]
        )
        XCTAssertEqual(highlights.map(\.first), [revealedMistake])
        XCTAssertEqual(highlights.first?.dottedUnderline, true)
    }

    func testPracticeGlyphTintsActiveWordGreenMistakeWordRedAndSkipsHiddenWords() throws {
        let quran = Quran.hafsMadani1405
        let verse = try XCTUnwrap(AyahNumber(quran: quran, sura: 42, ayah: 8))
        let active = Word(verse: verse, wordNumber: 12)
        let mistake = Word(verse: verse, wordNumber: 10)
        let hiddenPending = Word(verse: verse, wordNumber: 13)

        let mask = PracticeMask(
            hiddenVerses: [],
            partialVerse: verse,
            revealedWords: 12,
            mistakeWords: [mistake],
            activeWord: active,
            pendingMistakeWord: hiddenPending
        )
        let masked: Set<Word> = [hiddenPending]
        let tints = ContentImageViewModel.practiceGlyphTints(mask, maskedWords: masked, imageWords: [:])
        XCTAssertEqual(tints.map(\.first), [active, mistake])
        XCTAssertEqual(tints[0].color, .practiceActiveWord)
        XCTAssertEqual(tints[1].color, .practiceMistakeWord)

        let pendingMask = ContentImageViewModel.practicePendingMistakeMaskWords(mask, maskedWords: masked, imageWords: [:])
        XCTAssertEqual(pendingMask, [hiddenPending])
    }
}
