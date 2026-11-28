//
//  MistakeHeatmapTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import QuranAnnotations
import QuranKit
import XCTest

final class MistakeHeatmapTests: XCTestCase {
    private let quran = Quran.hafsMadani1405

    func testRestrictedFiltersToPage() throws {
        let fatiha1 = try XCTUnwrap(AyahNumber(quran: quran, sura: 1, ayah: 1))
        let ikhlas1 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 1))
        let wordFatiha = Word(verse: fatiha1, wordNumber: 2)
        let wordIkhlas = Word(verse: ikhlas1, wordNumber: 3)

        let heatmap = MistakeHeatmapOverlay(
            verseLevels: [fatiha1: .low, ikhlas1: .high],
            wordLevels: [wordFatiha: .low, wordIkhlas: .high]
        )

        let page604 = heatmap.restricted(to: ikhlas1.page)
        XCTAssertEqual(page604.verseLevels, [ikhlas1: .high])
        XCTAssertEqual(page604.wordLevels, [wordIkhlas: .high])
        XCTAssertTrue(page604.hasWordHeat(for: ikhlas1))
        XCTAssertFalse(page604.hasWordHeat(for: fatiha1))
    }

    func testActiveMistakeHeatmapSuppressedDuringPractice() throws {
        let ikhlas1 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 1))
        var overlays = VerseOverlays()
        overlays.mistakeHeatmap = MistakeHeatmapOverlay(verseLevels: [ikhlas1: .medium])

        XCTAssertEqual(overlays.activeMistakeHeatmap?.verseLevels[ikhlas1], .medium)

        overlays.practiceMask = PracticeMask(hiddenVerses: [ikhlas1], partialVerse: nil, revealedWords: 0)
        XCTAssertNil(overlays.activeMistakeHeatmap)
    }
}
