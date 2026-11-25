//
//  CoreDataCollectionPersistenceTests.swift
//
//
//  Created by Claude Code on 2026-11-25.
//

import AsyncUtilitiesForTesting
import Combine
import CoreData
import CoreDataModel
import CoreDataPersistence
import CoreDataPersistenceTestSupport
import XCTest
@testable import CollectionPersistence

final class CoreDataCollectionPersistenceTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        stack = store.stack()
        persistence = makePersistence(stack: stack)
    }

    override func tearDown() {
        persistence = nil
        stack = nil
        store = nil
        super.tearDown()
    }

    func testCreatedCollectionsAreListedOldestFirst() async throws {
        let collector = PublisherCollector(persistence.collections())

        try await persistence.createCollection(id: favoritesID, name: "Favorites", isDefault: true)
        try await persistence.createCollection(id: duasID, name: "Duas", isDefault: false)

        XCTAssertEqual(collector.items.last?.map(\.name), ["Favorites", "Duas"])
        XCTAssertEqual(collector.items.last?.map(\.id), [favoritesID, duasID])
        XCTAssertEqual(collector.items.last?.map(\.isDefault), [true, false])
        XCTAssertEqual(collector.items.last?.first?.createdOn, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(collector.items.last?.last?.createdOn, Date(timeIntervalSince1970: 2))
    }

    func testAddingVersesKeepsOrderAndSkipsVersesAlreadyInTheCollection() async throws {
        try await persistence.createCollection(id: duasID, name: "Duas", isDefault: false)
        let collector = PublisherCollector(persistence.collections())

        try await persistence.addVerses([verse(2, 201), verse(2, 286)], toCollectionWithID: duasID)
        try await persistence.addVerses([verse(2, 286), verse(3, 8), verse(3, 8)], toCollectionWithID: duasID)

        let collection = try XCTUnwrap(collector.items.last?.first)
        XCTAssertEqual(collection.verses.map(\.verse), [verse(2, 201), verse(2, 286), verse(3, 8)])
        XCTAssertEqual(Set(collection.verses.map(\.id)).count, 3)
        XCTAssertEqual(collection.modifiedOn, Date(timeIntervalSince1970: 3))
    }

    func testTheSameVerseCanBeInSeveralCollections() async throws {
        try await persistence.createCollection(id: favoritesID, name: "Favorites", isDefault: true)
        try await persistence.createCollection(id: duasID, name: "Duas", isDefault: false)
        let collector = PublisherCollector(persistence.collections())

        try await persistence.addVerses([verse(1, 1)], toCollectionWithID: favoritesID)
        try await persistence.addVerses([verse(1, 1)], toCollectionWithID: duasID)
        try await persistence.removeVerses([verse(1, 1)], fromCollectionWithID: favoritesID)

        XCTAssertEqual(collector.items.last?.map { $0.verses.map(\.verse) }, [[], [verse(1, 1)]])
    }

    func testRemovingVersesKeepsTheOthers() async throws {
        try await persistence.createCollection(id: duasID, name: "Duas", isDefault: false)
        try await persistence.addVerses([verse(2, 201), verse(2, 286), verse(3, 8)], toCollectionWithID: duasID)
        let collector = PublisherCollector(persistence.collections())

        try await persistence.removeVerses([verse(2, 286), verse(9, 9)], fromCollectionWithID: duasID)

        XCTAssertEqual(collector.items.last?.first?.verses.map(\.verse), [verse(2, 201), verse(3, 8)])
    }

    func testRemovingAllVersesKeepsTheCollection() async throws {
        try await persistence.createCollection(id: favoritesID, name: "Favorites", isDefault: true)
        try await persistence.addVerses([verse(1, 1), verse(1, 2)], toCollectionWithID: favoritesID)
        let collector = PublisherCollector(persistence.collections())

        try await persistence.removeAllVerses(fromCollectionWithID: favoritesID)

        XCTAssertEqual(collector.items.last?.map(\.id), [favoritesID])
        XCTAssertEqual(collector.items.last?.first?.verses, [])
    }

    func testRemovingACollectionRemovesItsVerses() async throws {
        try await persistence.createCollection(id: duasID, name: "Duas", isDefault: false)
        try await persistence.addVerses([verse(2, 201)], toCollectionWithID: duasID)

        try await persistence.removeCollection(id: duasID)

        let collector = PublisherCollector(persistence.collections())
        XCTAssertEqual(collector.items.last, [])
        XCTAssertEqual(try storedCount(entityName: "MO_CollectionVerse"), 0)
    }

    func testRenamingChangesTheNameAndModifiedDate() async throws {
        try await persistence.createCollection(id: duasID, name: "Duas", isDefault: false)
        let collector = PublisherCollector(persistence.collections())

        try await persistence.renameCollection(id: duasID, to: "Morning duas")

        XCTAssertEqual(collector.items.last?.first?.name, "Morning duas")
        XCTAssertEqual(collector.items.last?.first?.createdOn, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(collector.items.last?.first?.modifiedOn, Date(timeIntervalSince1970: 2))
    }

    func testNamesAreUniqueIgnoringCaseAndSurroundingSpaces() async throws {
        try await persistence.createCollection(id: duasID, name: "Duas", isDefault: false)
        try await persistence.createCollection(id: hifzID, name: "Hifz", isDefault: false)

        await assertThrows(CollectionNameTakenError(existingName: "Duas")) {
            try await persistence.createCollection(id: UUID(), name: " duas ", isDefault: false)
        }
        await assertThrows(CollectionNameTakenError(existingName: "Duas")) {
            try await persistence.renameCollection(id: hifzID, to: "DUAS")
        }
        // A collection can be renamed to its own name in another case.
        try await persistence.renameCollection(id: duasID, to: "duas")

        let collector = PublisherCollector(persistence.collections())
        XCTAssertEqual(collector.items.last?.map(\.name), ["duas", "Hifz"])
    }

    func testChangesToAMissingCollectionDoNothing() async throws {
        let missingID = UUID()
        try await persistence.renameCollection(id: missingID, to: "Duas")
        try await persistence.addVerses([verse(1, 1)], toCollectionWithID: missingID)
        try await persistence.removeVerses([verse(1, 1)], fromCollectionWithID: missingID)
        try await persistence.removeAllVerses(fromCollectionWithID: missingID)
        try await persistence.removeCollection(id: missingID)

        XCTAssertEqual(try storedCount(entityName: "MO_Collection"), 0)
        XCTAssertEqual(try storedCount(entityName: "MO_CollectionVerse"), 0)
    }

    func testCollectionsSurviveReopeningTheStore() async throws {
        try await persistence.createCollection(id: duasID, name: "Duas", isDefault: false)
        try await persistence.addVerses([verse(2, 201)], toCollectionWithID: duasID)
        persistence = nil
        stack = nil

        let reopened = makePersistence(stack: store.stack())

        let collector = PublisherCollector(reopened.collections())
        XCTAssertEqual(collector.items.last?.map(\.name), ["Duas"])
        XCTAssertEqual(collector.items.last?.first?.verses.map(\.verse), [verse(2, 201)])
    }

    /// The model version that shipped before collections existed. Its data must survive the upgrade.
    func testUpgradingFromTheSecondModelVersionKeepsNotesBookmarksAndLastPages() async throws {
        // setUp already opened `store` with the current model, so the old store needs its own file.
        let oldStore = TemporaryCoreDataStore()
        let secondModelURL = CoreDataModelResources.quranModel.appendingPathComponent("Quran 2.mom")
        var oldStack: CoreDataStack? = oldStore.stack(modelUrl: secondModelURL)
        try insertSecondVersionRecords(into: XCTUnwrap(oldStack))
        oldStack = nil

        stack = oldStore.stack()
        persistence = makePersistence(stack: stack)

        XCTAssertEqual(try storedValues(entityName: "MO_Note", key: "note"), ["Patience"])
        XCTAssertEqual(try storedValues(entityName: "MO_Verse", key: "ayah"), [153])
        XCTAssertEqual(try storedValues(entityName: "MO_PageBookmark", key: "page"), [42])
        XCTAssertEqual(try storedValues(entityName: "MO_LastPage", key: "mushafID"), [2])
        XCTAssertEqual(try storedCount(entityName: "MO_Collection"), 0)

        try await persistence.createCollection(id: duasID, name: "Duas", isDefault: false)
        try await persistence.addVerses([verse(2, 153)], toCollectionWithID: duasID)
        let collector = PublisherCollector(persistence.collections())
        XCTAssertEqual(collector.items.last?.first?.verses.map(\.verse), [verse(2, 153)])
    }

    // MARK: Private

    private let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let duasID = UUID(uuidString: "6A0C3E1B-3C0A-4C93-9B49-2E7A7D3D9C11")!
    private let hifzID = UUID(uuidString: "0B9E4E4E-1F45-4A55-8C36-7C2B8A1A3B22")!

    private var persistence: CoreDataCollectionPersistence!
    private var store: TemporaryCoreDataStore!
    private var stack: CoreDataStack!

    private func makePersistence(stack: CoreDataStack) -> CoreDataCollectionPersistence {
        let clock = TickingClock()
        return CoreDataCollectionPersistence(stack: stack, now: { clock.tick() })
    }

    private func verse(_ sura: Int, _ ayah: Int) -> CollectionVerseID {
        CollectionVerseID(sura: sura, ayah: ayah)
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

    private func storedCount(entityName: String) throws -> Int {
        let context = try XCTUnwrap(stack).newBackgroundContext()
        return try context.performAndWait {
            try context.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))
        }
    }

    private func storedValues(entityName: String, key: String) throws -> [AnyHashable] {
        let context = try XCTUnwrap(stack).newBackgroundContext()
        return try context.performAndWait {
            try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entityName))
                .compactMap { $0.value(forKey: key) as? AnyHashable }
        }
    }

    private func insertSecondVersionRecords(into stack: CoreDataStack) throws {
        let context = stack.newBackgroundContext()
        try context.performAndWait {
            func insert(_ entityName: String, _ values: [String: Any]) throws -> NSManagedObject {
                let entity = try XCTUnwrap(NSEntityDescription.entity(forEntityName: entityName, in: context))
                let object = NSManagedObject(entity: entity, insertInto: context)
                object.setValuesForKeys(values)
                return object
            }
            let date = Date(timeIntervalSince1970: 1000)
            let note = try insert("MO_Note", ["note": "Patience", "color": 2, "createdOn": date, "modifiedOn": date])
            let verse = try insert("MO_Verse", ["sura": 2, "ayah": 153])
            verse.setValue(note, forKey: "note")
            _ = try insert("MO_PageBookmark", ["page": 42, "mushafID": 0, "createdOn": date, "modifiedOn": date])
            _ = try insert("MO_LastPage", ["page": 7, "mushafID": 2, "createdOn": date, "modifiedOn": date])
            try context.save()
        }
    }
}

/// Returns 1 s, 2 s, 3 s… after 1970 on each call, so tests can tell writes apart.
private final class TickingClock: @unchecked Sendable {
    func tick() -> Date {
        lock.lock()
        defer { lock.unlock() }
        ticks += 1
        return Date(timeIntervalSince1970: TimeInterval(ticks))
    }

    private let lock = NSLock()
    private var ticks = 0
}
