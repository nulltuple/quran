//
//  VerseOverlaysCollectionIndicatorTests.swift
//
//  Collection and note indicators exist in both builds; reading bookmarks are covered by
//  `VerseOverlaysIndicatorTests` (sync only).
//

import QuranKit
import XCTest
@testable import QuranAnnotations

final class VerseOverlaysCollectionIndicatorTests: XCTestCase {
    func test_indicators_markNotedAndCollectedAyahsOnly() {
        let page = Quran.hafsMadani1405.pages[0]
        var overlays = VerseOverlays()
        overlays.notedVerses = [page.verses[0]]
        overlays.collectionVerses = [page.verses[0], page.verses[1]]
        overlays.colorHighlights = [page.verses[2]: .green]

        XCTAssertEqual(overlays.indicators(for: page.verses[0]), [.note, .collection])
        XCTAssertEqual(overlays.indicators(for: page.verses[1]), [.collection])
        XCTAssertTrue(overlays.indicators(for: page.verses[2]).isEmpty, "A highlight alone has no indicator")
    }

    func test_restricted_keepsOnlyTheCollectedAyahsOnThePage() {
        let page = Quran.hafsMadani1405.pages[0]
        let otherPage = Quran.hafsMadani1405.pages[1]
        var overlays = VerseOverlays()
        overlays.collectionVerses = [page.firstVerse, otherPage.firstVerse]

        let restricted = overlays.restricted(to: page)

        XCTAssertEqual(restricted.collectionVerses, [page.firstVerse])
        XCTAssertEqual(restricted.indicators(for: page.firstVerse), [.collection])
        XCTAssertTrue(restricted.indicators(for: otherPage.firstVerse).isEmpty)
    }

    func test_collectionChanges_doNotScrollTheReader() {
        let original = VerseOverlays()
        var updated = original
        updated.collectionVerses = [Quran.hafsMadani1405.suras[1].verses[4]]

        XCTAssertNotEqual(updated, original)
        XCTAssertFalse(updated.needsScrolling(comparingTo: original))
        XCTAssertNil(updated.verseToScrollTo(comparingTo: original))
    }
}
