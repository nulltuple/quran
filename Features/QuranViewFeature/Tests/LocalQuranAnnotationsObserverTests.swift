//
//  LocalQuranAnnotationsObserverTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

#if !QURAN_SYNC
import AnalyticsFake
import AnnotationsService
import CollectionPersistence
import CoreDataPersistenceTestSupport
import NotePersistence
import QuranAnnotations
import QuranKit
import XCTest
@testable import QuranViewFeature

/// Without sync the reader reads collections from the local store, so the ayah menu knows which ayahs are saved.
@MainActor
final class LocalQuranAnnotationsObserverTests: XCTestCase {
    func test_start_followsCollectionsInTheLocalStore() async throws {
        let store = TemporaryCoreDataStore()
        let stack = store.stack()
        let collectionService = AyahBookmarkCollectionService(persistence: CoreDataCollectionPersistence(stack: stack))
        let sut = QuranAnnotationsObserver(
            noteService: NoteService(persistence: CoreDataNotePersistence(stack: stack), analytics: AnalyticsLibrarySpy()),
            collectionService: collectionService,
            quran: quran,
            overlayService: VerseOverlayService()
        )
        let ayah = quran.suras[1].verses[254]

        sut.start()
        defer { sut.stop() }
        try await collectionService.addAyahs([ayah], toCollectionWithID: AyahBookmarkCollectionService.defaultCollectionID.uuidString)

        try await eventually {
            sut.collections.contains { $0.bookmarks.map(\.ayah) == [ayah] }
        }
    }

    func test_start_marksCollectedAyahsForTheTranslationView() async throws {
        let store = TemporaryCoreDataStore()
        let stack = store.stack()
        let collectionService = AyahBookmarkCollectionService(persistence: CoreDataCollectionPersistence(stack: stack))
        let overlayService = VerseOverlayService()
        let sut = QuranAnnotationsObserver(
            noteService: NoteService(persistence: CoreDataNotePersistence(stack: stack), analytics: AnalyticsLibrarySpy()),
            collectionService: collectionService,
            quran: quran,
            overlayService: overlayService
        )
        let ayah = quran.suras[1].verses[254]

        sut.start()
        defer { sut.stop() }
        try await collectionService.addAyahs([ayah], toCollectionWithID: AyahBookmarkCollectionService.defaultCollectionID.uuidString)
        try await eventually { overlayService.overlays.collectionVerses == [ayah] }
        XCTAssertEqual(overlayService.overlays.indicators(for: ayah), [.collection])

        try await collectionService.removeAyahs([ayah], fromCollectionWithID: AyahBookmarkCollectionService.defaultCollectionID.uuidString)
        try await eventually { overlayService.overlays.collectionVerses.isEmpty }
    }

    func test_start_marksNotesWithTextButNotHighlightsAlone() async throws {
        let store = TemporaryCoreDataStore()
        let stack = store.stack()
        let noteService = NoteService(persistence: CoreDataNotePersistence(stack: stack), analytics: AnalyticsLibrarySpy())
        let overlayService = VerseOverlayService()
        let sut = QuranAnnotationsObserver(
            noteService: noteService,
            collectionService: AyahBookmarkCollectionService(persistence: CoreDataCollectionPersistence(stack: stack)),
            quran: quran,
            overlayService: overlayService
        )
        let highlighted = quran.suras[1].verses[0]
        let noted = quran.suras[1].verses[1]
        let lastUsedColor = HighlightPreferences.shared.lastUsedHighlightColor
        defer { HighlightPreferences.shared.lastUsedHighlightColor = lastUsedColor }

        sut.start()
        defer { sut.stop() }
        _ = try await noteService.updateHighlight(verses: [highlighted], color: .green, quran: quran)
        try await noteService.setNote("Reflect on this", verses: [noted], color: .blue)

        try await eventually { overlayService.overlays.colorHighlights.keys.contains(noted) }
        XCTAssertEqual(overlayService.overlays.colorHighlights[highlighted], .green)
        XCTAssertEqual(overlayService.overlays.notedVerses, [noted])
        XCTAssertTrue(overlayService.overlays.indicators(for: highlighted).isEmpty)
    }

    func test_stop_stopsFollowingCollections() async throws {
        let store = TemporaryCoreDataStore()
        let stack = store.stack()
        let collectionService = AyahBookmarkCollectionService(persistence: CoreDataCollectionPersistence(stack: stack))
        let sut = QuranAnnotationsObserver(
            noteService: NoteService(persistence: CoreDataNotePersistence(stack: stack), analytics: AnalyticsLibrarySpy()),
            collectionService: collectionService,
            quran: quran,
            overlayService: VerseOverlayService()
        )
        sut.start()
        try await eventually { !sut.collections.isEmpty }

        sut.stop()
        try await collectionService.createCollection(named: "Later")
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(sut.collections.contains { $0.name == "Later" })
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405

    private func eventually(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Condition not met within \(timeout) s", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
#endif
