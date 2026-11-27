//
//  BackupServiceTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import BackupPersistence
import CoreDataPersistence
import CoreDataPersistenceTestSupport
import MemorizationPersistence
import XCTest
@testable import BackupService

final class BackupServiceTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        stack = store.stack()
        persistence = CoreDataBackupPersistence(stack: stack)
        service = BackupService(persistence: persistence, appVersion: "1.20.3 (990)", now: { Date(timeIntervalSince1970: 1_800_000_000.25) })
    }

    override func tearDown() {
        service = nil
        persistence = nil
        stack = nil
        store = nil
        super.tearDown()
    }

    func testExportedBackupReadsBackWithItsCounts() async throws {
        try await persistence.restore(sample, mode: .replace)

        let exported = try await service.exportBackup()
        let backup = try service.readBackup(exported.data)

        XCTAssertEqual(backup.snapshot, sample)
        XCTAssertEqual(backup.summary, exported.summary)
        XCTAssertEqual(backup.summary.notes, 1)
        XCTAssertEqual(backup.summary.highlights, 1)
        XCTAssertEqual(backup.summary.pageBookmarks, 1)
        XCTAssertEqual(backup.summary.recentPages, 1)
        XCTAssertEqual(backup.summary.collections, 1)
        XCTAssertEqual(backup.summary.collectionVerses, 2)
        XCTAssertEqual(backup.summary.practiceSessions, 1)
        XCTAssertEqual(backup.summary.memorizedRanges, 1)
        XCTAssertEqual(backup.summary.appVersion, "1.20.3 (990)")
        XCTAssertEqual(backup.summary.exportedAt, Date(timeIntervalSince1970: 1_800_000_000.25))
    }

    func testTheFileNamesItsFormatVersionAndUsesReadableDates() async throws {
        let exported = try await service.exportBackup()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: exported.data) as? [String: Any])

        XCTAssertEqual(json["format"] as? String, "com.nulltup.memquran.backup")
        XCTAssertEqual(json["schemaVersion"] as? Int, 3)
        XCTAssertEqual(json["appVersion"] as? String, "1.20.3 (990)")
        XCTAssertEqual(json["exportedAt"] as? String, "2027-01-15T08:00:00.250Z")
        XCTAssertTrue(exported.summary.isEmpty)
        XCTAssertEqual(service.exportFileName(), "Quran Backup 2027-01-15.json")
    }

    func testRestoringAValidatedBackupMergesOrReplaces() async throws {
        let backup = try service.readBackup(try BackupService.encoder().encode(document(sample)))
        let other = BackupSnapshot(pageBookmarks: [BackupPage(mushafID: 0, page: 300, createdOn: date(1), modifiedOn: date(1))])
        try await persistence.restore(other, mode: .replace)

        try await service.restore(backup, mode: .merge)
        let merged = try await persistence.snapshot()
        try await service.restore(backup, mode: .merge)
        let mergedTwice = try await persistence.snapshot()
        try await service.restore(backup, mode: .replace)
        let replaced = try await persistence.snapshot()

        XCTAssertEqual(merged.pageBookmarks.map(\.page), [5, 300])
        XCTAssertEqual(mergedTwice, merged)
        XCTAssertEqual(replaced, sample)
    }

    /// Schema 1 (F2, before H1) has no learning records; its files still restore, keeping stored practice on merge.
    func testASchemaOneBackupRestoresWithoutLearningRecords() async throws {
        let json = #"""
        {"format": "com.nulltup.memquran.backup", "schemaVersion": 1, "appVersion": "1", "exportedAt": "2026-11-26T00:00:00Z",
         "data": {"notes": [], "pageBookmarks": [{"mushafID": 0, "page": 5, "createdOn": "2026-11-26T00:00:00Z",
         "modifiedOn": "2026-11-26T00:00:00Z"}], "recentPages": [], "collections": []}}
        """#
        try await persistence.restore(BackupSnapshot(practiceSessions: [session()], recallEvidence: [evidence()]), mode: .replace)

        let backup = try service.readBackup(Data(json.utf8))
        XCTAssertEqual(backup.summary.practiceSessions, 0)
        XCTAssertEqual(backup.summary.pageBookmarks, 1)
        try await service.restore(backup, mode: .merge)

        let merged = try await persistence.snapshot()
        XCTAssertEqual(merged.practiceSessions, [session()])
        XCTAssertEqual(merged.recallEvidence, [evidence()])
        XCTAssertEqual(merged.pageBookmarks.map(\.page), [5])
    }

    /// Schema 2 (H1, before H3) has sessions and evidence but no memorized ranges or passages.
    func testASchemaTwoBackupRestoresWithoutMemorizedRangesOrPassages() async throws {
        let json = #"""
        {"format": "com.nulltup.memquran.backup", "schemaVersion": 2, "appVersion": "1.20.3", "exportedAt": "2026-11-27T00:00:00Z",
         "data": {"notes": [], "pageBookmarks": [], "recentPages": [], "collections": [],
         "practiceSessions": [{"id": "8B9F2C3D-0000-4000-8000-0000000000A1",
         "first": {"sura": 112, "ayah": 1}, "last": {"sura": 112, "ayah": 4},
         "startedOn": "1970-01-01T00:00:50.000Z", "endedOn": "1970-01-01T00:00:51.000Z"}],
         "recallEvidence": []}}
        """#
        try await persistence.restore(BackupSnapshot(memorizedRanges: [memorizedRange()], passages: [passage()]), mode: .replace)

        let backup = try service.readBackup(Data(json.utf8))
        XCTAssertEqual(backup.summary.practiceSessions, 1)
        XCTAssertEqual(backup.summary.memorizedRanges, 0)
        try await service.restore(backup, mode: .merge)

        let merged = try await persistence.snapshot()
        XCTAssertEqual(merged.practiceSessions, [session()])
        XCTAssertEqual(merged.memorizedRanges, [memorizedRange()])
        XCTAssertEqual(merged.passages, [passage()])
    }

    func testABackupFromANewerAppIsRefused() throws {
        let json = #"{"format": "com.nulltup.memquran.backup", "schemaVersion": 4, "data": {"something": "new"}}"#

        XCTAssertThrowsError(try service.readBackup(Data(json.utf8))) { error in
            XCTAssertEqual(error as? BackupError, .newerVersion)
        }
    }

    func testFilesThatAreNotBackupsAreRefused() {
        for text in ["not json", #"{"format": "other", "schemaVersion": 1}"#, "[]", #"{"format": "com.nulltup.memquran.backup", "schemaVersion": 0}"#] {
            XCTAssertThrowsError(try service.readBackup(Data(text.utf8)), text) { error in
                XCTAssertEqual(error as? BackupError, .notABackup, text)
            }
        }
    }

    func testABackupWithMissingFieldsIsDamaged() {
        let json = #"{"format": "com.nulltup.memquran.backup", "schemaVersion": 1, "appVersion": "1", "exportedAt": "2026-11-26T00:00:00Z", "data": {"notes": [{"verses": []}]}}"#

        XCTAssertThrowsError(try service.readBackup(Data(json.utf8))) { error in
            XCTAssertEqual(error as? BackupError, .damaged)
        }
    }

    func testRecordsThatCannotExistAreRefused() throws {
        let invalid: [BackupSnapshot] = [
            BackupSnapshot(notes: [note([BackupVerse(sura: 115, ayah: 1)])]),
            BackupSnapshot(notes: [note([BackupVerse(sura: 1, ayah: 8)])]),
            BackupSnapshot(notes: [note([])]),
            BackupSnapshot(notes: [note([BackupVerse(sura: 1, ayah: 1)], color: 99)]),
            BackupSnapshot(pageBookmarks: [BackupPage(mushafID: 0, page: 605, createdOn: date(1), modifiedOn: date(1))]),
            BackupSnapshot(recentPages: [BackupPage(mushafID: 9, page: 1, createdOn: date(1), modifiedOn: date(1))]),
            BackupSnapshot(collections: [collection(name: "  ")]),
            BackupSnapshot(collections: [collection(name: String(repeating: "a", count: 256))]),
            BackupSnapshot(collections: [collection(name: "Duas", verses: [BackupVerse(sura: 2, ayah: 300)])]),
            BackupSnapshot(practiceSessions: [session(first: 5)]),
            BackupSnapshot(practiceSessions: [session(first: 3, last: 2)]),
            BackupSnapshot(recallEvidence: [evidence(ayah: 9)]),
            BackupSnapshot(recallEvidence: [evidence(word: -1)]),
            BackupSnapshot(recallEvidence: [evidence(assistance: -1)]),
            BackupSnapshot(memorizedRanges: [memorizedRange(first: 5)]),
            BackupSnapshot(memorizedRanges: [memorizedRange(first: 3, last: 2)]),
            BackupSnapshot(passages: [passage(first: 5)]),
            BackupSnapshot(passages: [passage(first: 3, last: 2)]),
        ]
        for snapshot in invalid {
            let data = try BackupService.encoder().encode(document(snapshot))
            XCTAssertThrowsError(try service.readBackup(data), "\(snapshot)") { error in
                XCTAssertEqual(error as? BackupError, .invalidRecord, "\(snapshot)")
            }
        }
    }

    func testARefusedBackupLeavesTheStoredRecords() async throws {
        try await persistence.restore(sample, mode: .replace)
        var corrupted = try BackupService.encoder().encode(document(BackupSnapshot()))
        corrupted.removeLast(10)

        XCTAssertThrowsError(try service.readBackup(corrupted))

        let snapshot = try await persistence.snapshot()
        XCTAssertEqual(snapshot, sample)
    }

    func testOversizedFilesAreRefusedBeforeDecoding() {
        let data = Data(count: BackupService.maximumFileSize + 1)

        XCTAssertThrowsError(try service.readBackup(data)) { error in
            XCTAssertEqual(error as? BackupError, .tooLarge)
        }
    }

    func testDatesKeepMilliseconds() throws {
        let snapshot = BackupSnapshot(recentPages: [
            BackupPage(mushafID: 1, page: 2, createdOn: date(1.5), modifiedOn: date(2.125)),
        ])

        let backup = try service.readBackup(try BackupService.encoder().encode(document(snapshot)))

        XCTAssertEqual(backup.snapshot, snapshot)
    }

    // MARK: Private

    private var store: TemporaryCoreDataStore!
    private var stack: CoreDataStack!
    private var persistence: CoreDataBackupPersistence!
    private var service: BackupService!

    private var sample: BackupSnapshot {
        BackupSnapshot(
            notes: [
                BackupNote(verses: [BackupVerse(sura: 1, ayah: 1)], text: "Opening", color: 0, createdOn: date(10), modifiedOn: date(11)),
                BackupNote(verses: [BackupVerse(sura: 2, ayah: 255)], text: "", color: 2, createdOn: date(12), modifiedOn: date(12)),
            ],
            pageBookmarks: [BackupPage(mushafID: 0, page: 5, createdOn: date(20), modifiedOn: date(20))],
            recentPages: [BackupPage(mushafID: 1, page: 9, createdOn: date(30), modifiedOn: date(31))],
            collections: [collection(name: "Duas", verses: [BackupVerse(sura: 2, ayah: 201), BackupVerse(sura: 3, ayah: 8)])],
            practiceSessions: [session()],
            recallEvidence: [evidence()],
            memorizedRanges: [memorizedRange()],
            passages: [passage()]
        )
    }

    private func memorizedRange(first: Int = 1, last: Int = 4) -> MemorizedRangeRecord {
        MemorizedRangeRecord(
            id: UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000C1")!,
            first: MemorizationVerse(sura: 112, ayah: first),
            last: MemorizationVerse(sura: 112, ayah: last),
            declaredOn: date(60)
        )
    }

    private func passage(first: Int = 1, last: Int = 4) -> PassageRecord {
        PassageRecord(
            id: UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000D1")!,
            first: MemorizationVerse(sura: 112, ayah: first),
            last: MemorizationVerse(sura: 112, ayah: last),
            createdOn: date(60),
            modifiedOn: date(61)
        )
    }

    private func session(first: Int = 1, last: Int = 4) -> PracticeSessionRecord {
        PracticeSessionRecord(
            id: UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000A1")!,
            first: MemorizationVerse(sura: 112, ayah: first),
            last: MemorizationVerse(sura: 112, ayah: last),
            startedOn: date(50),
            endedOn: date(51)
        )
    }

    private func evidence(ayah: Int = 2, word: Int = 0, assistance: Int = 0) -> RecallEvidenceRecord {
        RecallEvidenceRecord(
            id: UUID(uuidString: "8B9F2C3D-0000-4000-8000-0000000000B1")!,
            sessionID: session().id,
            verse: MemorizationVerse(sura: 112, ayah: ayah),
            word: word,
            outcome: .hint,
            assistance: assistance,
            provenance: .model,
            recordedOn: date(51)
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func document(_ snapshot: BackupSnapshot) -> BackupDocument {
        BackupDocument(format: BackupService.format, schemaVersion: BackupService.schemaVersion, appVersion: "1", exportedAt: date(0), data: snapshot)
    }

    private func note(_ verses: [BackupVerse], color: Int = 0) -> BackupNote {
        BackupNote(verses: verses, text: "x", color: color, createdOn: date(1), modifiedOn: date(1))
    }

    private func collection(name: String, verses: [BackupVerse] = []) -> BackupCollection {
        BackupCollection(
            id: UUID(uuidString: "8B9F2C3D-0000-4000-8000-000000000002")!,
            name: name,
            isDefault: false,
            createdOn: date(40),
            modifiedOn: date(40),
            verses: verses.map { BackupCollectionVerse(verse: $0, createdOn: date(41)) }
        )
    }
}
