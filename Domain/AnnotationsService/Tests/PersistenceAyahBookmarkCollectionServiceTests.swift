//
//  PersistenceAyahBookmarkCollectionServiceTests.swift
//
//
//  Created by Claude Code on 2026-11-25.
//

#if !QURAN_SYNC
import CollectionPersistence
import CoreDataPersistence
import CoreDataPersistenceTestSupport
import QuranAnnotations
import QuranKit
import XCTest
@testable import AnnotationsService

final class PersistenceAyahBookmarkCollectionServiceTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        stack = store.stack()
        persistence = CoreDataCollectionPersistence(stack: stack)
        service = AyahBookmarkCollectionService(persistence: persistence)
    }

    override func tearDown() {
        service = nil
        persistence = nil
        stack = nil
        store = nil
        super.tearDown()
    }

    func testFavoritesIsListedFirstBeforeItIsStored() async throws {
        let collections = try await currentCollections()

        XCTAssertEqual(collections.map(\.id), [favoritesID])
        XCTAssertEqual(collections.first?.name, "Favorites")
        XCTAssertEqual(collections.first?.kind, .defaultBookmarks)
        XCTAssertEqual(collections.first?.isReadOnly, true)
        XCTAssertEqual(collections.first?.bookmarks.map(\.ayah), [])
    }

    func testAddingAyahsToFavoritesStoresItOnce() async throws {
        try await service.addAyahs([ayah(1, 1), ayah(1, 2)], toCollectionWithID: favoritesID)
        try await service.addAyahBookmarkToCollection(collectionId: favoritesID, ayah: ayah(2, 255))
        try await service.addAyahs([ayah(1, 2)], toCollectionWithID: favoritesID)

        let collections = try await currentCollections()
        XCTAssertEqual(collections.map(\.id), [favoritesID])
        XCTAssertEqual(collections.first?.bookmarks.map(\.ayah), [ayah(1, 1), ayah(1, 2), ayah(2, 255)])
        XCTAssertEqual(collections.first?.bookmarks.map(\.collectionID), [favoritesID, favoritesID, favoritesID])
    }

    func testUserCollectionsFollowFavoritesOldestFirst() async throws {
        try await service.createCollection(named: "  Duas  ")
        try await service.createCollection(named: "Hifz review")

        let collections = try await currentCollections()
        XCTAssertEqual(collections.map(\.name), ["Favorites", "Duas", "Hifz review"])
        XCTAssertEqual(collections.map(\.kind), [.defaultBookmarks, .user, .user])
        XCTAssertEqual(collections.map(\.canRename), [false, true, true])
    }

    func testAyahsCanBeAddedToAndRemovedFromAUserCollection() async throws {
        try await service.createCollection(named: "Duas")
        let duas = try await collection(named: "Duas")

        try await service.addAyahs([ayah(2, 201), ayah(2, 286), ayah(3, 8)], toCollectionWithID: duas.id)
        try await service.removeAyahs([ayah(2, 286)], fromCollectionWithID: duas.id)
        let filledDuas = try await collection(named: "Duas")
        let bookmark = try XCTUnwrap(filledDuas.bookmarks.last)
        try await service.removeBookmarkFromCollection(bookmark)

        let updatedDuas = try await collection(named: "Duas")
        XCTAssertEqual(updatedDuas.bookmarks.map(\.ayah), [ayah(2, 201)])
    }

    func testRemovingAllAyahsKeepsFavorites() async throws {
        try await service.addAyahs([ayah(1, 1), ayah(1, 2)], toCollectionWithID: favoritesID)

        try await service.removeAllAyahs(fromCollectionWithID: favoritesID)

        let collections = try await currentCollections()
        XCTAssertEqual(collections.map(\.id), [favoritesID])
        XCTAssertEqual(collections.first?.bookmarks.map(\.ayah), [])
    }

    func testRenamingAndRemovingAUserCollection() async throws {
        try await service.createCollection(named: "Duas")
        let duas = try await collection(named: "Duas")

        try await service.renameCollection(id: duas.id, to: "Morning duas")
        let collections = try await currentCollections()
        XCTAssertEqual(collections.map(\.name), ["Favorites", "Morning duas"])

        try await service.removeCollection(id: duas.id)
        let remaining = try await currentCollections()
        XCTAssertEqual(remaining.map(\.name), ["Favorites"])
    }

    func testFavoritesCannotBeRenamedOrRemoved() async throws {
        try await service.addAyahs([ayah(1, 1)], toCollectionWithID: favoritesID)

        await assertThrows(ReadOnlyCollectionError(collectionID: favoritesID)) {
            try await service.renameCollection(id: favoritesID, to: "Saved")
        }
        await assertThrows(ReadOnlyCollectionError(collectionID: favoritesID)) {
            try await service.removeCollection(id: favoritesID)
        }
        let collections = try await currentCollections()
        XCTAssertEqual(collections.first?.bookmarks.map(\.ayah), [ayah(1, 1)])
    }

    func testReservedNamesAreRejected() async throws {
        await assertThrows(ReservedCollectionNameError(name: "favorites")) {
            try await service.createCollection(named: " favorites ")
        }
        await assertThrows(ReservedCollectionNameError(name: "System:Highlights")) {
            try await service.createCollection(named: "System:Highlights")
        }
        try await service.createCollection(named: "Duas")
        let duas = try await collection(named: "Duas")
        await assertThrows(ReservedCollectionNameError(name: "Favorites")) {
            try await service.renameCollection(id: duas.id, to: "Favorites")
        }
    }

    func testDuplicateNamesAreRejectedWithTheExistingName() async throws {
        try await service.createCollection(named: "Duas")
        try await service.createCollection(named: "Hifz")
        let hifz = try await collection(named: "Hifz")

        await assertThrows(DuplicateCollectionNameError(name: "Duas")) {
            try await service.createCollection(named: "DUAS")
        }
        await assertThrows(DuplicateCollectionNameError(name: "Duas")) {
            try await service.renameCollection(id: hifz.id, to: " duas")
        }
    }

    func testNameLengthIsMeasuredAfterTrimming() async throws {
        await assertThrows(TextLengthLimitError(field: .collectionName, bound: .tooShort, limit: 1)) {
            try await service.createCollection(named: "   ")
        }
        await assertThrows(TextLengthLimitError(field: .collectionName, bound: .tooLong, limit: 255)) {
            try await service.createCollection(named: String(repeating: "a", count: 256))
        }
        try await service.createCollection(named: " " + String(repeating: "a", count: 255) + " ")

        let collections = try await currentCollections()
        XCTAssertEqual(collections.last?.name.count, 255)
    }

    func testAyahsMissingFromTheReadingAreLeftOut() async throws {
        try await service.addAyahs([ayah(2, 286)], toCollectionWithID: favoritesID)
        try await persistence.addVerses(
            [CollectionVerseID(sura: 2, ayah: 400), CollectionVerseID(sura: 115, ayah: 1)],
            toCollectionWithID: AyahBookmarkCollectionService.defaultCollectionID
        )

        let collections = try await currentCollections()
        XCTAssertEqual(collections.first?.bookmarks.map(\.ayah), [ayah(2, 286)])
    }

    func testInvalidCollectionIDsAreIgnored() async throws {
        try await service.addAyahs([ayah(1, 1)], toCollectionWithID: "not-a-uuid")
        try await service.removeCollection(id: "not-a-uuid")
        try await service.renameCollection(id: "not-a-uuid", to: "Duas")

        let collections = try await currentCollections()
        XCTAssertEqual(collections.map(\.id), [favoritesID])
        XCTAssertEqual(collections.first?.bookmarks.map(\.ayah), [])
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405
    private let favoritesID = AyahBookmarkCollectionService.defaultCollectionID.uuidString

    private var store: TemporaryCoreDataStore!
    private var stack: CoreDataStack!
    private var persistence: CoreDataCollectionPersistence!
    private var service: AyahBookmarkCollectionService!

    private func ayah(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }

    private func currentCollections() async throws -> [AyahBookmarkCollection] {
        var iterator = service.collectionsSequence(quran: quran).makeAsyncIterator()
        let next = try await iterator.next()
        return try XCTUnwrap(next)
    }

    private func collection(named name: String) async throws -> AyahBookmarkCollection {
        let collections = try await currentCollections()
        return try XCTUnwrap(collections.first { $0.name == name })
    }

    private func assertThrows<E: Error & Equatable>(
        _ expected: E,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? E, expected, file: file, line: line)
        }
    }
}
#endif
