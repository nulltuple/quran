//
//  CoreDataMemorizationPersistenceTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import CoreData
import CoreDataModel
import CoreDataPersistence
import CoreDataPersistenceTestSupport
import XCTest
@testable import MemorizationPersistence

final class CoreDataMemorizationPersistenceTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        stack = store.stack()
        persistence = CoreDataMemorizationPersistence(stack: stack)
    }

    override func tearDown() {
        persistence = nil
        stack = nil
        store = nil
        super.tearDown()
    }

    func testRecordedSessionAndEvidenceAreReadBack() async throws {
        try await persistence.record(session, evidence: [correct, mistake])

        let history = try await persistence.history()
        XCTAssertEqual(history.sessions, [session])
        XCTAssertEqual(Set(history.evidence), [correct, mistake])
    }

    func testRecordingTheSameIDsAgainStoresNothingNew() async throws {
        try await persistence.record(session, evidence: [correct])
        try await persistence.record(session, evidence: [correct, mistake])

        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(Set(history.evidence.map(\.id)), [correct.id, mistake.id])
    }

    func testRetractedEvidenceStaysStoredWithItsDate() async throws {
        try await persistence.record(session, evidence: [correct, mistake])
        try await persistence.retractEvidence(withIDs: [mistake.id], on: date(50))
        // Retracting again keeps the first date.
        try await persistence.retractEvidence(withIDs: [mistake.id], on: date(60))

        let evidence = try await persistence.history().evidence
        XCTAssertEqual(evidence.first { $0.id == mistake.id }?.retractedOn, date(50))
        XCTAssertNil(evidence.first { $0.id == correct.id }?.retractedOn)
    }

    func testRecordsFromANewerVersionWithUnknownOutcomesAreSkipped() async throws {
        try await persistence.record(session, evidence: [correct])
        let context = stack.newBackgroundContext()
        try context.performAndWait {
            let future = MO_RecallEvidence(context: context)
            mistake.write(to: future)
            future.outcome = 99
            try context.save()
        }

        let actual = try await persistence.history().evidence
        XCTAssertEqual(actual, [correct])
    }

    /// `Quran 3` shipped to TestFlight (collections); its data must survive the upgrade to `Quran 4`.
    func testUpgradingFromTheThirdModelVersionKeepsCollectionsAndAddsLearningRecords() async throws {
        let oldStore = TemporaryCoreDataStore()
        let thirdModelURL = CoreDataModelResources.quranModel.appendingPathComponent("Quran 3.mom")
        var oldStack: CoreDataStack? = oldStore.stack(modelUrl: thirdModelURL)
        let context = try XCTUnwrap(oldStack).newBackgroundContext()
        try context.performAndWait {
            let collection = NSEntityDescription.insertNewObject(forEntityName: "MO_Collection", into: context)
            collection.setValue("Hifz", forKey: "name")
            let note = NSEntityDescription.insertNewObject(forEntityName: "MO_Note", into: context)
            note.setValue("Patience", forKey: "note")
            try context.save()
        }
        oldStack = nil

        stack = oldStore.stack()
        persistence = CoreDataMemorizationPersistence(stack: stack)
        let upgraded = stack.newBackgroundContext()
        try upgraded.performAndWait {
            let collections = try upgraded.fetch(NSFetchRequest<NSManagedObject>(entityName: "MO_Collection"))
            XCTAssertEqual(collections.compactMap { $0.value(forKey: "name") as? String }, ["Hifz"])
            XCTAssertEqual(try upgraded.count(for: NSFetchRequest<NSManagedObject>(entityName: "MO_Note")), 1)
        }

        try await persistence.record(session, evidence: [correct])
        let actual = try await persistence.history().sessions
        XCTAssertEqual(actual, [session])
    }

    // MARK: Private

    private let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private var persistence: CoreDataMemorizationPersistence!
    private var store: TemporaryCoreDataStore!
    private var stack: CoreDataStack!

    private var session: PracticeSessionRecord {
        PracticeSessionRecord(
            id: sessionID,
            first: MemorizationVerse(sura: 112, ayah: 1),
            last: MemorizationVerse(sura: 112, ayah: 4),
            startedOn: date(0),
            endedOn: date(10)
        )
    }

    private var correct: RecallEvidenceRecord {
        evidence("22222222-2222-2222-2222-222222222222", ayah: 1, word: 0, .correct)
    }

    private var mistake: RecallEvidenceRecord {
        evidence("33333333-3333-3333-3333-333333333333", ayah: 2, word: 2, .mistake)
    }

    private func evidence(_ id: String, ayah: Int, word: Int, _ outcome: RecallOutcome) -> RecallEvidenceRecord {
        RecallEvidenceRecord(
            id: UUID(uuidString: id)!,
            sessionID: sessionID,
            verse: MemorizationVerse(sura: 112, ayah: ayah),
            word: word,
            outcome: outcome,
            assistance: 1,
            provenance: .manual,
            recordedOn: date(10)
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }
}
