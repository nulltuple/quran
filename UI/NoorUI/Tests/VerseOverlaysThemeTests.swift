import QuranAnnotations
import QuranKit
import UIKit
import XCTest
@testable import NoorUI

final class VerseOverlaysThemeTests: XCTestCase {
    func testNavigationHighlightPaintsOverTheSavedColor() {
        let verse = Quran.hafsMadani1405.firstVerse
        var overlays = VerseOverlays()
        overlays.colorHighlights = [verse: .green]
        overlays.navigationHighlight = verse

        XCTAssertEqual(overlays.versesByHighlights(), [verse: VerseOverlays.navigationColor])
    }

    func testNavigationTargetAloneDoesNotPaint() {
        let verse = Quran.hafsMadani1405.firstVerse
        var overlays = VerseOverlays()
        overlays.colorHighlights = [verse: .green]
        overlays.navigationTarget = verse

        let colors = overlays.versesByHighlights()
        XCTAssertEqual(Set(colors.keys), [verse])
        XCTAssertEqual(
            colors[verse].map(resolved),
            resolved(HighlightColor.green.uiColor.withAlphaComponent(VerseOverlays.opacity))
        )
    }

    func testPlaybackAndSelectionPaintOverTheNavigationHighlight() {
        let verses = Quran.hafsMadani1405.pages[0].verses
        var overlays = VerseOverlays()
        overlays.navigationHighlight = verses[0]
        overlays.playingVerses = [verses[0]]
        overlays.selectedVerses = [verses[1]]
        overlays.colorHighlights = [verses[1]: .blue]

        XCTAssertEqual(overlays.versesByHighlights(), [
            verses[0]: VerseOverlays.playingColor,
            verses[1]: VerseOverlays.selectionColor,
        ])
    }

    func testMistakeHeatmapPaintsWordlessVersesAndYieldsToSavedHighlights() {
        let verses = Quran.hafsMadani1405.pages[0].verses
        let v0 = verses[0]
        let v1 = verses[1]
        let v2 = verses[2]
        var overlays = VerseOverlays()
        overlays.mistakeHeatmap = MistakeHeatmapOverlay(
            verseLevels: [v0: .high, v1: .medium, v2: .low],
            wordLevels: [Word(verse: v1, wordNumber: 1): .medium]
        )
        overlays.colorHighlights = [v2: .green]

        // Default mode (word-capable): v0 gets ayah tint, v1 uses word heat (omitted from ayah tint), v2 yields to green highlight.
        let wordCapable = overlays.versesByHighlights()
        XCTAssertEqual(wordCapable[v0].map(resolved), resolved(MistakeHeatLevel.high.uiColor))
        XCTAssertNil(wordCapable[v1])
        XCTAssertEqual(wordCapable[v2].map(resolved), resolved(HighlightColor.green.uiColor.withAlphaComponent(VerseOverlays.opacity)))

        // Ayah-only mode (line pages): v1 also gets its ayah tint.
        let ayahOnly = overlays.versesByHighlights(includeAllHeatmapVerses: true)
        XCTAssertEqual(ayahOnly[v1].map(resolved), resolved(MistakeHeatLevel.medium.uiColor))
    }

    private func resolved(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }
}
