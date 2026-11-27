//
//  CoreDataBackupPersistenceTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import CoreData
import CoreDataModel
import CoreDataPersistence
import CoreDataPersistenceTestSupport
import MemorizationPersistence
import XCTest
@testable import BackupPersistence

final class CoreDataBackupPersistenceTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        stack = store.stack()
        persistence = CoreDataBackupPersistence(stack: stack)
    }

    override func tearDown() {
        persistence = nil
        stack = nil
        store = nil
        super.tearDown()
    }

    func testSnapshotReadsEveryRecordKindInAStableOrder() async throws {
        try stack.write { context in
            let note = context.newNote("Patience", modifiedOn: 20)
            note.createdOn = date(10)
            note.color = 2
            note.addToVerses(context.newVerse(sura: 2, ayah: 154))
            note.addToVerses(context.newVerse(sura: 2, ayah: 153))
            // A note without verses is not shown anywhere, so it is not backed up.
            _ = context.newNote("Orphan", modifiedOn: 30)

            for (page, modified) in [(50, 40.0), (3, 41.0)] {
                let bookmark = MO_PageBookmark(context: context)
                bookmark.page = Int32(page)
                bookmark.mushafID = 1
                bookmark.createdOn = date(modified)
                bookmark.modifiedOn = date(modified)
            }
            // A last page with no dates gets the Unix epoch.
            let lastPage = MO_LastPage(context: context)
            lastPage.page = 7

            let collection = MO_Collection(context: context)
            collection.id = duasID
            collection.name = "Duas"
            collection.createdOn = date(5)
            collection.modifiedOn = date(6)
            for (sura, ayah, created) in [(3, 8, 2.0), (2, 201, 1.0)] {
                let verse = MO_CollectionVerse(context: context)
                verse.id = UUID()
                verse.sura = Int32(sura)
                verse.ayah = Int32(ayah)
                verse.createdOn = date(created)
                verse.collection = collection
            }
        }

        let snapshot = try await persistence.snapshot()

        XCTAssertEqual(snapshot.notes, [
            BackupNote(verses: [verse(2, 153), verse(2, 154)], text: "Patience", color: 2, createdOn: date(10), modifiedOn: date(20)),
        ])
        XCTAssertEqual(snapshot.pageBookmarks.map(\.page), [3, 50])
        XCTAssertEqual(snapshot.recentPages, [BackupPage(mushafID: 0, page: 7, createdOn: date(0), modifiedOn: date(0))])
        XCTAssertEqual(snapshot.collections.count, 1)
        XCTAssertEqual(snapshot.collections.first?.verses.map(\.verse), [verse(2, 201), verse(3, 8)])
        XCTAssertEqual(snapshot.collections.first?.name, "Duas")
    }

    func testReplacingAnEmptyStoreReproducesTheSnapshot() async throws {
        try await persistence.restore(sample, mode: .replace)

        let otherStore = TemporaryCoreDataStore()
        let other = CoreDataBackupPersistence(stack: otherStore.stack())
        try await other.restore(try await persistence.snapshot(), mode: .replace)

        let restored = try await other.snapshot()
        XCTAssertEqual(restored, sample)
    }

    func testMergingTheSameBackupTwiceChangesNothing() async throws {
        try await persistence.restore(existing, mode: .replace)
        try await persistence.restore(sample, mode: .merge)
        let once = try await persistence.snapshot()

        try await persistence.restore(sample, mode: .merge)

        let twice = try await persistence.snapshot()
        XCTAssertEqual(twice, once)
        XCTAssertEqual(once.collections.count, 2, "Duas matched by name, Favorites by ID")
        XCTAssertEqual(once.pageBookmarks.count, 3)
    }

    func testMergeSavesNothingWhenTheBackupIsAlreadyThere() async throws {
        try await persistence.restore(sample, mode: .replace)
        let token = try currentHistoryToken()

        try await persistence.restore(sample, mode: .merge)

        XCTAssertEqual(try currentHistoryToken(), token)
    }

    func testReplaceDeletesRecordsTheBackupDoesNotHave() async throws {
        try await persistence.restore(existing, mode: .replace)

        try await persistence.restore(sample, mode: .replace)

        let snapshot = try await persistence.snapshot()
        XCTAssertEqual(snapshot, sample)
    }

    func testReplacingWithAnEmptyBackupDeletesEverything() async throws {
        try await persistence.restore(sample, mode: .replace)

        try await persistence.restore(BackupSnapshot(), mode: .replace)

        let snapshot = try await persistence.snapshot()
        XCTAssertTrue(snapshot.isEmpty)
        let context = stack.newBackgroundContext()
        let verseCount = try context.performAndWait { try context.count(for: MO_Verse.fetchRequest()) }
        XCTAssertEqual(verseCount, 0, "note verses are deleted too")
    }

    func testANewerBackupOfTheSameNoteReplacesItsTextAndColor() async throws {
        try await persistence.restore(BackupSnapshot(notes: [note([verse(1, 1)], "old", color: 0, modified: 10)]), mode: .replace)

        try await persistence.restore(BackupSnapshot(notes: [note([verse(1, 1)], "new", color: 3, modified: 20)]), mode: .merge)

        let notes = try await persistence.snapshot().notes
        XCTAssertEqual(notes.map(\.text), ["new"])
        XCTAssertEqual(notes.map(\.color), [3])
        XCTAssertEqual(notes.map(\.modifiedOn), [date(20)])
    }

    func testAnOlderBackupOfTheSameNoteKeepsTheStoredText() async throws {
        try await persistence.restore(BackupSnapshot(notes: [note([verse(1, 1)], "edited", color: 0, modified: 20)]), mode: .replace)

        try await persistence.restore(BackupSnapshot(notes: [note([verse(1, 1)], "draft", color: 3, modified: 10)]), mode: .merge)

        let notes = try await persistence.snapshot().notes
        XCTAssertEqual(notes.map(\.text), ["edited"])
        XCTAssertEqual(notes.map(\.color), [0])
        XCTAssertEqual(notes.map(\.createdOn), [date(10)], "the earlier creation date is kept")
    }

    func testANewerHighlightKeepsTheOlderNoteText() async throws {
        try await persistence.restore(BackupSnapshot(notes: [note([verse(1, 1)], "", color: 4, modified: 20)]), mode: .replace)

        try await persistence.restore(BackupSnapshot(notes: [note([verse(1, 1)], "Reflection", color: 0, modified: 10)]), mode: .merge)

        let notes = try await persistence.snapshot().notes
        XCTAssertEqual(notes.map(\.text), ["Reflection"])
        XCTAssertEqual(notes.map(\.color), [4])
    }

    func testAnOverlappingNoteJoinsTheStoredNoteOnce() async throws {
        try await persistence.restore(BackupSnapshot(notes: [
            note([verse(2, 1), verse(2, 2)], "First", color: 0, modified: 10),
            note([verse(2, 5)], "Second", color: 0, modified: 11),
        ]), mode: .replace)
        let backup = BackupSnapshot(notes: [note([verse(2, 2), verse(2, 3), verse(2, 5)], "Backup", color: 1, modified: 30)])

        try await persistence.restore(backup, mode: .merge)
        let once = try await persistence.snapshot()
        try await persistence.restore(backup, mode: .merge)

        XCTAssertEqual(once.notes.count, 1)
        XCTAssertEqual(once.notes.first?.verses, [verse(2, 1), verse(2, 2), verse(2, 3), verse(2, 5)])
        XCTAssertEqual(once.notes.first?.text, "First\n\nSecond\n\nBackup")
        XCTAssertEqual(once.notes.first?.color, 1)
        let twice = try await persistence.snapshot()
        XCTAssertEqual(twice, once)
    }

    func testACollectionMatchedByNameGetsTheMissingVersesAndKeepsItsID() async throws {
        let storedID = UUID()
        try await persistence.restore(BackupSnapshot(collections: [
            collection(storedID, "Duas", modified: 10, verses: [verse(2, 201)]),
        ]), mode: .replace)

        try await persistence.restore(BackupSnapshot(collections: [
            collection(UUID(), " duas ", modified: 5, verses: [verse(2, 201), verse(3, 8)]),
        ]), mode: .merge)

        let collections = try await persistence.snapshot().collections
        XCTAssertEqual(collections.map(\.id), [storedID])
        XCTAssertEqual(collections.map(\.name), ["Duas"])
        XCTAssertEqual(collections.first?.verses.map(\.verse), [verse(3, 8), verse(2, 201)], "oldest first")
    }

    func testANewerCollectionRenamesTheStoredOneOnlyWhenTheNameIsFree() async throws {
        let renamedID = UUID()
        let blockedID = UUID()
        try await persistence.restore(BackupSnapshot(collections: [
            collection(renamedID, "Morning", modified: 10, verses: []),
            collection(blockedID, "Evening", modified: 11, verses: []),
            collection(UUID(), "Night", modified: 12, verses: []),
        ]), mode: .replace)

        try await persistence.restore(BackupSnapshot(collections: [
            collection(renamedID, "Morning Duas", modified: 20, verses: []),
            collection(blockedID, "Night", modified: 20, verses: []),
        ]), mode: .merge)

        let names = try await persistence.snapshot().collections.map(\.name)
        XCTAssertEqual(names, ["Morning Duas", "Evening", "Night"])
    }

    func testMergingLearningRecordsAddsNewIDsAndCarriesRetractions() async throws {
        let stored = evidence(retractedEvidenceID, .mistake)
        let storedOnly = evidence(UUID(), .hint)
        try await persistence.restore(
            BackupSnapshot(practiceSessions: [session], recallEvidence: [stored, storedOnly]),
            mode: .replace
        )

        try await persistence.restore(sample, mode: .merge)

        let snapshot = try await persistence.snapshot()
        XCTAssertEqual(snapshot.practiceSessions, [session])
        XCTAssertEqual(snapshot.recallEvidence.count, 3)
        XCTAssertEqual(snapshot.recallEvidence.first { $0.id == retractedEvidenceID }?.retractedOn, date(120))
        XCTAssertNotNil(snapshot.recallEvidence.first { $0.id == storedOnly.id })
        XCTAssertNotNil(snapshot.recallEvidence.first { $0.id == sampleEvidenceID })
    }

    func testMergingMemorizedRangesAndPassagesCarriesRemovalsAndNewerSnoozes() async throws {
        let initialRange = MemorizedRangeRecord(
            id: removedRangeID,
            first: MemorizationVerse(sura: 114, ayah: 1),
            last: MemorizationVerse(sura: 114, ayah: 6),
            declaredOn: date(100)
        )
        let olderPassage = PassageRecord(
            id: passageID,
            first: MemorizationVerse(sura: 112, ayah: 1),
            last: MemorizationVerse(sura: 112, ayah: 4),
            createdOn: date(100),
            modifiedOn: date(105),
            snoozedUntil: nil
        )
        try await persistence.restore(
            BackupSnapshot(memorizedRanges: [initialRange], passages: [olderPassage]),
            mode: .replace
        )

        try await persistence.restore(sample, mode: .merge)

        let snapshot = try await persistence.snapshot()
        XCTAssertEqual(snapshot.memorizedRanges.count, 2)
        XCTAssertEqual(snapshot.memorizedRanges.first { $0.id == removedRangeID }?.removedOn, date(125))
        XCTAssertEqual(snapshot.passages.first { $0.id == passageID }?.snoozedUntil, date(500))
        XCTAssertEqual(snapshot.passages.first { $0.id == passageID }?.modifiedOn, date(130))
    }

    func testJoinedTextsSkipBlankAndContainedTexts() {
        XCTAssertEqual(joinedDistinctTexts(["First", " ", "Second ", "First"]), "First\n\nSecond")
        XCTAssertEqual(joinedDistinctTexts(["First\n\nSecond", "Second", ""]), "First\n\nSecond")
    }

    // MARK: Private

    private let duasID = UUID(uuidString: "8B9F2C3D-0000-4000-8000-000000000001")!
    private let favoritesID = UUID(uuidString: "4D1F7A52-6E0B-4E43-9A0C-0F2B5A3C8E01")!

    private var store: TemporaryCoreDataStore!
    private var stack: CoreDataStack!
    private var persistence: CoreDataBackupPersistence!

    private var sample: BackupSnapshot {
        BackupSnapshot(
            notes: [
                note([verse(1, 1), verse(1, 2)], "Opening", color: 0, modified: 100),
                note([verse(2, 255)], nil, color: 3, modified: 101),
            ],
            pageBookmarks: [
                BackupPage(mushafID: 0, page: 1, createdOn: date(90), modifiedOn: date(90)),
                BackupPage(mushafID: 1, page: 604, createdOn: date(91), modifiedOn: date(92)),
            ],
            recentPages: [
                BackupPage(mushafID: 0, page: 42, createdOn: date(95), modifiedOn: date(99)),
                BackupPage(mushafID: 0, page: 41, createdOn: date(94), modifiedOn: date(98)),
            ],
            collections: [
                collection(favoritesID, "Favorites", isDefault: true, modified: 80, verses: [verse(1, 1)]),
                collection(duasID, "Duas", modified: 81, verses: [verse(2, 201), verse(3, 8)]),
            ],
            practiceSessions: [session],
            recallEvidence: [evidence(sampleEvidenceID, .correct), evidence(retractedEvidenceID, .mistake, retractedOn: 120)],
            memorizedRanges: [
                MemorizedRangeRecord(
                    id: activeRangeID,
                    first: MemorizationVerse(sura: 112, ayah: 1),
                    last: MemorizationVerse(sura: 113, ayah: 5),
                    declaredOn: date(100)
                ),
                MemorizedRangeRecord(
                    id: removedRangeID,
                    first: MemorizationVerse(sura: 114, ayah: 1),
                    last: MemorizationVerse(sura: 114, ayah: 6),
                    declaredOn: date(100),
                    removedOn: date(125)
                ),
            ],
            passages: [
                PassageRecord(
                    id: passageID,
                    first: MemorizationVerse(sura: 112, ayah: 1),
                    last: MemorizationVerse(sura: 112, ayah: 4),
                    createdOn: date(100),
                    modifiedOn: date(130),
                    snoozedUntil: date(500)
                ),
            ]
        )
    }

    private let sessionID = UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000A1")!
    private let sampleEvidenceID = UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000B1")!
    private let retractedEvidenceID = UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000B2")!
    private let activeRangeID = UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000C1")!
    private let removedRangeID = UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000C2")!
    private let passageID = UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000D1")!

    private var session: PracticeSessionRecord {
        PracticeSessionRecord(
            id: sessionID,
            first: MemorizationVerse(sura: 112, ayah: 1),
            last: MemorizationVerse(sura: 112, ayah: 4),
            startedOn: date(110),
            endedOn: date(111)
        )
    }

    private func evidence(_ id: UUID, _ outcome: RecallOutcome, retractedOn: TimeInterval? = nil) -> RecallEvidenceRecord {
        RecallEvidenceRecord(
            id: id,
            sessionID: sessionID,
            verse: MemorizationVerse(sura: 112, ayah: 2),
            word: outcome == .mistake ? 3 : 0,
            outcome: outcome,
            assistance: 1,
            provenance: .manual,
            recordedOn: date(111),
            retractedOn: retractedOn.map(date)
        )
    }

    private var existing: BackupSnapshot {
        BackupSnapshot(
            notes: [note([verse(18, 10)], "Cave", color: 1, modified: 50)],
            pageBookmarks: [BackupPage(mushafID: 0, page: 1, createdOn: date(10), modifiedOn: date(10)),
                            BackupPage(mushafID: 0, page: 300, createdOn: date(11), modifiedOn: date(11))],
            recentPages: [BackupPage(mushafID: 0, page: 7, createdOn: date(12), modifiedOn: date(12))],
            collections: [
                collection(favoritesID, "Favorites", isDefault: true, modified: 60, verses: [verse(36, 1)]),
                collection(UUID(), "DUAS", modified: 61, verses: [verse(2, 201)]),
            ]
        )
    }

    private func currentHistoryToken() throws -> NSPersistentHistoryToken? {
        try stack.openStore()
        let coordinator = stack.viewContext.persistentStoreCoordinator
        return coordinator?.currentPersistentHistoryToken(fromStores: nil)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func verse(_ sura: Int, _ ayah: Int) -> BackupVerse {
        BackupVerse(sura: sura, ayah: ayah)
    }

    private func note(_ verses: [BackupVerse], _ text: String?, color: Int, modified: TimeInterval) -> BackupNote {
        BackupNote(verses: verses, text: text, color: color, createdOn: date(modified), modifiedOn: date(modified))
    }

    private func collection(
        _ id: UUID,
        _ name: String,
        isDefault: Bool = false,
        modified: TimeInterval,
        verses: [BackupVerse]
    ) -> BackupCollection {
        BackupCollection(
            id: id,
            name: name,
            isDefault: isDefault,
            createdOn: date(modified),
            modifiedOn: date(modified),
            verses: verses.enumerated().map { BackupCollectionVerse(verse: $1, createdOn: date(modified + Double($0))) }
        )
    }
}
