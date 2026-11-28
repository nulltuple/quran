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

    /// `Quran 4` shipped to TestFlight (practice sessions and evidence); its data must survive the upgrade to `Quran 5`.
    func testUpgradingFromTheFourthModelVersionKeepsPracticeAndAddsMemorizedRangesAndPassages() async throws {
        let oldStore = TemporaryCoreDataStore()
        let fourthModelURL = CoreDataModelResources.quranModel.appendingPathComponent("Quran 4.mom")
        var oldStack: CoreDataStack? = oldStore.stack(modelUrl: fourthModelURL)
        let context = try XCTUnwrap(oldStack).newBackgroundContext()
        try context.performAndWait {
            let storedSession = NSEntityDescription.insertNewObject(forEntityName: "MO_PracticeSession", into: context)
            storedSession.setValue(sessionID, forKey: "id")
            storedSession.setValue(Int32(112), forKey: "firstSura")
            storedSession.setValue(Int32(1), forKey: "firstAyah")
            storedSession.setValue(Int32(112), forKey: "lastSura")
            storedSession.setValue(Int32(4), forKey: "lastAyah")
            storedSession.setValue(date(0), forKey: "startedOn")
            storedSession.setValue(date(10), forKey: "endedOn")
            try context.save()
        }
        oldStack = nil

        stack = oldStore.stack()
        persistence = CoreDataMemorizationPersistence(stack: stack)

        let declaredRange = MemorizedRangeRecord(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            first: MemorizationVerse(sura: 112, ayah: 1),
            last: MemorizationVerse(sura: 114, ayah: 6),
            declaredOn: date(20)
        )
        let passage = PassageRecord(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            first: MemorizationVerse(sura: 112, ayah: 1),
            last: MemorizationVerse(sura: 112, ayah: 4),
            createdOn: date(20),
            modifiedOn: date(20)
        )
        try await persistence.saveDeclaredRange(declaredRange, passages: [passage])

        let history = try await persistence.history()
        XCTAssertEqual(history.sessions, [session])
        XCTAssertEqual(history.declaredRanges, [declaredRange])
        XCTAssertEqual(history.passages, [passage])
    }

    func testDeclaredRangesAndPassagesSaveUpdateAndTombstone() async throws {
        let rangeID = UUID()
        let passageID = UUID()
        let declaredRange = MemorizedRangeRecord(
            id: rangeID,
            first: MemorizationVerse(sura: 67, ayah: 1),
            last: MemorizationVerse(sura: 67, ayah: 30),
            declaredOn: date(10)
        )
        let initialPassage = PassageRecord(
            id: passageID,
            first: MemorizationVerse(sura: 67, ayah: 1),
            last: MemorizationVerse(sura: 67, ayah: 15),
            createdOn: date(10),
            modifiedOn: date(10)
        )
        try await persistence.saveDeclaredRange(declaredRange, passages: [initialPassage])
        // Re-saving same range id does not duplicate it.
        try await persistence.saveDeclaredRange(declaredRange, passages: [])

        var snoozed = initialPassage
        snoozed.snoozedUntil = date(86400)
        snoozed.modifiedOn = date(30)
        try await persistence.savePassages([snoozed])

        var history = try await persistence.history()
        XCTAssertEqual(history.declaredRanges, [declaredRange])
        XCTAssertEqual(history.passages, [snoozed])

        try await persistence.removeDeclaredRanges(withIDs: [rangeID], removingPassageIDs: [passageID], on: date(50))
        // Removing again preserves the first removal date.
        try await persistence.removeDeclaredRanges(withIDs: [rangeID], removingPassageIDs: [passageID], on: date(90))

        history = try await persistence.history()
        XCTAssertEqual(history.declaredRanges.first?.removedOn, date(50))
        XCTAssertEqual(history.passages.first?.removedOn, date(50))
    }

    /// `Quran 5` shipped to TestFlight (memorized ranges and passages); its data must survive the upgrade to `Quran 6`.
    func testUpgradingFromTheFifthModelVersionKeepsRangesAndAddsGoalsAndActivityLogs() async throws {
        let oldStore = TemporaryCoreDataStore()
        let fifthModelURL = CoreDataModelResources.quranModel.appendingPathComponent("Quran 5.mom")
        var oldStack: CoreDataStack? = oldStore.stack(modelUrl: fifthModelURL)
        let context = try XCTUnwrap(oldStack).newBackgroundContext()
        let rangeID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        try context.performAndWait {
            let storedRange = NSEntityDescription.insertNewObject(forEntityName: "MO_MemorizedRange", into: context)
            storedRange.setValue(rangeID, forKey: "id")
            storedRange.setValue(Int32(112), forKey: "firstSura")
            storedRange.setValue(Int32(1), forKey: "firstAyah")
            storedRange.setValue(Int32(112), forKey: "lastSura")
            storedRange.setValue(Int32(4), forKey: "lastAyah")
            storedRange.setValue(date(15), forKey: "declaredOn")
            try context.save()
        }
        oldStack = nil

        stack = oldStore.stack()
        persistence = CoreDataMemorizationPersistence(stack: stack)

        let goal = StudyGoalRecord(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            title: "Ramadan Khatmah",
            kind: .khatmah,
            activity: .read,
            unit: .pages,
            workloadMode: .flexible,
            targetAmount: 604,
            startDate: date(20),
            deadline: date(20 + 29 * 86400),
            createdOn: date(20),
            modifiedOn: date(20)
        )
        let log = ActivityLogRecord(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            activity: .read,
            startedOn: date(25),
            endedOn: date(325),
            durationSeconds: 300,
            pagesCount: 4,
            goalID: goal.id
        )
        try await persistence.saveGoal(goal)
        try await persistence.recordActivityLog(log)

        let history = try await persistence.history()
        XCTAssertEqual(history.declaredRanges.map(\.id), [rangeID])
        XCTAssertEqual(history.goals, [goal])
        XCTAssertEqual(history.activityLogs, [log])
    }

    func testStudyGoalsAndActivityLogsSaveUpdateTombstoneAndRetract() async throws {
        let goalID = UUID()
        let logID = UUID()
        var goal = StudyGoalRecord(
            id: goalID,
            title: "Daily Reading",
            kind: .habit,
            activity: .read,
            unit: .minutes,
            workloadMode: .fixed,
            targetAmount: 15,
            startDate: date(10),
            createdOn: date(10),
            modifiedOn: date(10)
        )
        try await persistence.saveGoal(goal)
        goal.targetAmount = 20
        goal.modifiedOn = date(20)
        try await persistence.saveGoal(goal)

        let log = ActivityLogRecord(
            id: logID,
            activity: .listen,
            startedOn: date(30),
            endedOn: date(150),
            durationSeconds: 120,
            pagesCount: 1,
            ayahsCount: 5
        )
        try await persistence.recordActivityLog(log)
        try await persistence.recordActivityLog(log) // idempotent

        try await persistence.removeGoal(withID: goalID, on: date(40))
        try await persistence.removeGoal(withID: goalID, on: date(50)) // keeps first removal date
        try await persistence.retractActivityLogs(withIDs: [logID], on: date(45))
        try await persistence.retractActivityLogs(withIDs: [logID], on: date(55)) // keeps first retraction date

        let history = try await persistence.history()
        XCTAssertEqual(history.goals.count, 1)
        XCTAssertEqual(history.goals.first?.targetAmount, 20)
        XCTAssertEqual(history.goals.first?.removedOn, date(40))
        XCTAssertEqual(history.activityLogs.count, 1)
        XCTAssertEqual(history.activityLogs.first?.retractedOn, date(45))
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
