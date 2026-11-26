//
//  LocalBookmarkCollectionsTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

#if !QURAN_SYNC
import AnalyticsFake
import AnnotationsService
import CollectionPersistence
import CoreDataPersistence
import CoreDataPersistenceTestSupport
import PageBookmarkPersistence
import QuranAnnotations
import QuranKit
import QuranResources
import QuranTextKit
import ReadingService
import UIKit
import XCTest
@testable import BookmarksFeature

/// The no-sync Bookmarks tab and collection editor, over the real Core Data stores.
@MainActor
final class LocalBookmarkCollectionsTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        ReadingPreferences.shared.reading = .hafs_1405
        BookmarksPreferences.shared.isCollectionsIntroRetired = false
        store = TemporaryCoreDataStore()
        let stack = store.stack()
        collectionService = AyahBookmarkCollectionService(persistence: CoreDataCollectionPersistence(stack: stack))
        pageBookmarkService = PageBookmarkService(persistence: CoreDataPageBookmarkPersistence(stack: stack))
    }

    override func tearDown() async throws {
        startTask?.cancel()
        startTask = nil
        BookmarksPreferences.shared.isCollectionsIntroRetired = false
        collectionService = nil
        pageBookmarkService = nil
        store = nil
        try await super.tearDown()
    }

    func testBookmarksListsFavoritesFirstThenCollectionsByName() async throws {
        try await collectionService.createCollection(named: "Zeta")
        try await collectionService.createCollection(named: "Alpha")
        let sut = makeCollectionsViewModel()

        start(sut)
        try await eventually { sut.collections.count == 3 }

        XCTAssertEqual(sut.displayedCollections.map(\.kind), [.defaultBookmarks, .user, .user])
        XCTAssertEqual(sut.displayedCollections.dropFirst().map(\.name), ["Alpha", "Zeta"])
        XCTAssertTrue(sut.hasDeletableItems)
    }

    func testCreatingACollectionStoresItWithoutASignInReminder() async throws {
        let sut = makeCollectionsViewModel()
        start(sut)
        try await eventually { sut.collections.count == 1 }

        sut.presentAddCollection()
        sut.newCollectionName = "  Duas  "
        let toast = await sut.createPendingCollection()

        XCTAssertNil(toast)
        XCTAssertEqual(sut.nameAlert, .hidden)
        try await eventually { sut.collections.contains { $0.name == "Duas" } }
    }

    func testDeletingAnEmptyCollectionRemovesItAtOnce() async throws {
        try await collectionService.createCollection(named: "Review")
        let sut = makeCollectionsViewModel()
        start(sut)
        try await eventually { sut.collections.count == 2 }
        let review = try XCTUnwrap(sut.collections.first { $0.name == "Review" })

        await sut.requestDeleteCollection(review)

        XCTAssertNil(sut.collectionPendingDeletion)
        try await eventually { sut.collections.count == 1 }
    }

    func testPageBookmarksMakeTheListEditableWithoutCollections() async throws {
        let sut = makeCollectionsViewModel()
        start(sut)
        try await eventually { sut.collections.count == 1 }
        XCTAssertFalse(sut.hasDeletableItems, "Favorites alone can't be deleted")

        try await pageBookmarkService.insertPageBookmark(quran.pages[1])

        try await eventually { sut.pageBookmarks.bookmarks.map(\.page) == [quran.pages[1]] }
        XCTAssertTrue(sut.hasDeletableItems)
    }

    func testEditorAddsAndRemovesTheSelectedAyahsInFavorites() async throws {
        let verses = [quran.suras[0].verses[0], quran.suras[0].verses[1]]
        let sut = BookmarkAyahsViewModel(
            verses: verses,
            collections: [],
            analytics: AnalyticsLibrarySpy(),
            ayahBookmarkCollectionService: collectionService
        )
        let observeTask = Task { await sut.start() }
        defer { observeTask.cancel() }
        try await eventually { sut.displayedCollections.count == 1 }
        let favorites = try XCTUnwrap(sut.displayedCollections.first)

        await sut.toggleCollection(favorites)

        try await eventually { sut.collectionSelection(for: favorites) == .selected }
        let storedAfterAdding = try await storedFavorites()
        XCTAssertEqual(storedAfterAdding, verses)
        XCTAssertTrue(BookmarksPreferences.shared.isCollectionsIntroRetired, "Using a collection retires the intro next time")

        await sut.toggleCollection(favorites)

        try await eventually { sut.collectionSelection(for: favorites) == .unselected }
        let storedAfterRemoving = try await storedFavorites()
        XCTAssertEqual(storedAfterRemoving, [])
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405
    private var store: TemporaryCoreDataStore!
    private var collectionService: AyahBookmarkCollectionService!
    private var pageBookmarkService: PageBookmarkService!
    private var startTask: Task<Void, Never>?

    private func makeCollectionsViewModel() -> BookmarkCollectionsViewModel {
        let ayahSetBuilder = AyahSetBuilder(
            ayahBookmarkCollectionService: collectionService,
            quranTextDataService: QuranTextDataService(
                databasesURL: FileManager.default.temporaryDirectory,
                quranFileURL: QuranResources.quranUthmaniV2Database
            ),
            navigateToAyah: { _ in }
        )
        return BookmarkCollectionsViewModel(
            ayahBookmarkCollectionService: collectionService,
            pageBookmarks: BookmarksViewModel(
                analytics: AnalyticsLibrarySpy(),
                service: pageBookmarkService,
                navigateTo: { _ in }
            ),
            ayahSetBuilder: ayahSetBuilder,
            navigationController: UINavigationController()
        )
    }

    private func start(_ sut: BookmarkCollectionsViewModel) {
        startTask = Task { await sut.start() }
    }

    private func storedFavorites() async throws -> [AyahNumber] {
        for try await collections in collectionService.collectionsSequence(quran: quran) {
            let favorites = collections.first { $0.kind == .defaultBookmarks }
            return favorites?.bookmarks.map(\.ayah).sorted() ?? []
        }
        return []
    }

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
