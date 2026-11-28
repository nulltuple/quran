//
//  MistakeHistoryTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import Foundation
import MemorizationPersistence
import MemorizationService
import QuranAnnotations
import QuranKit
import XCTest

final class MistakeHistoryTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        try super.setUpWithError()
        now = Date(timeIntervalSince1970: 1_764_200_000)
        store = TemporaryCoreDataStore()
        persistence = CoreDataMemorizationPersistence(stack: store.stack())
        service = MemorizationService(
            persistence: persistence,
            quran: quran,
            now: { [unowned self] in now }
        )
    }

    override func tearDownWithError() throws {
        service = nil
        persistence = nil
        store = nil
        try super.tearDownWithError()
    }

    func testDecayPolicyCleanRecallsAndTimeHalfLife() {
        let policy = MistakeDecayPolicy.default
        // Fresh mistake: 1.0 -> medium
        let fresh = policy.weight(ageDays: 0, cleanRecallsAfter: 0)
        XCTAssertEqual(fresh, 1.0, accuracy: 0.0001)
        XCTAssertEqual(policy.heatLevel(for: fresh), .medium)

        // 1 clean recall: 0.5 -> low
        let afterOneClean = policy.weight(ageDays: 0, cleanRecallsAfter: 1)
        XCTAssertEqual(afterOneClean, 0.5, accuracy: 0.0001)
        XCTAssertEqual(policy.heatLevel(for: afterOneClean), .low)

        // 2 clean recalls: 0.25 -> low (at boundary)
        let afterTwoClean = policy.weight(ageDays: 0, cleanRecallsAfter: 2)
        XCTAssertEqual(afterTwoClean, 0.25, accuracy: 0.0001)
        XCTAssertEqual(policy.heatLevel(for: afterTwoClean), .low)

        // 3 clean recalls: 0.125 -> cleared (< 0.25)
        let afterThreeClean = policy.weight(ageDays: 0, cleanRecallsAfter: 3)
        XCTAssertEqual(afterThreeClean, 0.125, accuracy: 0.0001)
        XCTAssertNil(policy.heatLevel(for: afterThreeClean))

        // Time decay: 60 days = 0.5, 130 days < 0.25 (cleared)
        XCTAssertEqual(policy.weight(ageDays: 60, cleanRecallsAfter: 0), 0.5, accuracy: 0.0001)
        XCTAssertNil(policy.heatLevel(for: policy.weight(ageDays: 130, cleanRecallsAfter: 0)))

        // Repeated mistakes -> high (>= 2.0)
        XCTAssertEqual(policy.heatLevel(for: 2.0), .high)
    }

    func testOneCountPerWordPerSession() throws {
        let v1 = try verse(112, 1)
        let sessionID = UUID()
        let session = PracticeSessionRecord(
            id: sessionID,
            first: MemorizationVerse(sura: 112, ayah: 1),
            last: MemorizationVerse(sura: 112, ayah: 4),
            startedOn: now,
            endedOn: now
        )
        // Duplicate word-2 mistake records inside the same session.
        let e1 = RecallEvidenceRecord(
            id: UUID(),
            sessionID: sessionID,
            verse: MemorizationVerse(sura: 112, ayah: 1),
            word: 2,
            outcome: .mistake,
            assistance: 0,
            provenance: .manual,
            recordedOn: now
        )
        let e2 = RecallEvidenceRecord(
            id: UUID(),
            sessionID: sessionID,
            verse: MemorizationVerse(sura: 112, ayah: 1),
            word: 2,
            outcome: .mistake,
            assistance: 0,
            provenance: .model,
            recordedOn: now
        )

        let snapshot = MistakeHistoryReducer.reduce(
            history: MemorizationHistory(sessions: [session], evidence: [e1, e2]),
            quran: quran,
            now: now
        )

        let summary = try XCTUnwrap(snapshot.verseSummaries[v1])
        XCTAssertEqual(summary.score, 1.0, accuracy: 0.0001)
        XCTAssertEqual(summary.wordSummaries.count, 1)
        XCTAssertEqual(summary.wordSummaries[0].sessionCount, 1)
        XCTAssertEqual(summary.wordSummaries[0].score, 1.0, accuracy: 0.0001)
        XCTAssertEqual(Set(summary.wordSummaries[0].events[0].evidenceIDs), Set([e1.id, e2.id]))
    }

    func testAssistedRecallDoesNotDecayMistakeWhileCleanRecallsClearIt() async throws {
        let v1 = try verse(112, 1)
        let v4 = try verse(112, 4)
        let passage = Passage(v1, v4)

        // Session 1: mistake on word 3
        try await service.recordSession(passage, startedOn: now, recalls: [
            VerseRecall(verse: v1, outcome: .mistake, mistakenWords: [3], provenance: .manual),
        ])

        // Session 2: hint (assisted) — must NOT reduce heat
        now = now.addingTimeInterval(3600)
        try await service.recordSession(passage, startedOn: now, recalls: [
            VerseRecall(verse: v1, outcome: .hint, assistance: 1, provenance: .manual),
        ])

        let loadedAfterHint = try await service.mistakeSummary(for: v1)
        var summary = try XCTUnwrap(loadedAfterHint)
        XCTAssertEqual(summary.cleanRecallsSinceLastMistake, 0)
        XCTAssertEqual(summary.wordSummaries.first?.level, .medium)

        // Three clean unassisted sessions clear it below threshold
        for step in 1 ... 3 {
            now = now.addingTimeInterval(Double(step) * 3600)
            try await service.recordSession(passage, startedOn: now, recalls: [
                VerseRecall(verse: v1, outcome: .correct, assistance: 0, provenance: .manual),
            ])
        }

        let loadedAfterClean = try await service.mistakeSummary(for: v1)
        summary = try XCTUnwrap(loadedAfterClean)
        XCTAssertEqual(summary.cleanRecallsSinceLastMistake, 3)
        XCTAssertNil(summary.level)
        let heatmapAfterClean = try await service.mistakeHeatmap(for: quran)
        XCTAssertTrue(heatmapAfterClean.isEmpty)
        let repairAfterClean = try await service.repairQueue()
        XCTAssertTrue(repairAfterClean.isEmpty)
    }

    func testConfirmModelMistakeUpgradesProvenanceWithoutDoublingCount() async throws {
        let v1 = try verse(112, 1)
        let passage = Passage(v1, try verse(112, 4))

        try await service.recordSession(passage, startedOn: now, recalls: [
            VerseRecall(verse: v1, outcome: .mistake, mistakenWords: [2], provenance: .model),
        ])

        let loadedBefore = try await service.mistakeSummary(for: v1)
        let before = try XCTUnwrap(loadedBefore)
        let modelEvent = try XCTUnwrap(before.activeEvents.first)
        XCTAssertEqual(modelEvent.provenance, .model)
        XCTAssertEqual(before.score, 1.0, accuracy: 0.0001)

        try await service.confirmMistake(modelEvent)

        let loadedAfter = try await service.mistakeSummary(for: v1)
        let after = try XCTUnwrap(loadedAfter)
        XCTAssertEqual(after.activeEvents.count, 1)
        XCTAssertEqual(after.activeEvents[0].provenance, .manual)
        XCTAssertEqual(after.score, 1.0, accuracy: 0.0001)
    }

    func testRetractLastWordMistakeAlsoRetractsCompanionAyahMistakeAndClearsHeatmap() async throws {
        let v1 = try verse(112, 1)
        let passage = Passage(v1, try verse(112, 4))

        try await service.recordSession(passage, startedOn: now, recalls: [
            VerseRecall(verse: v1, outcome: .mistake, mistakenWords: [2], provenance: .model),
        ])

        var heatmap = try await service.mistakeHeatmap(for: quran)
        XCTAssertEqual(heatmap.wordLevels[Word(verse: v1, wordNumber: 2)], .medium)
        XCTAssertEqual(heatmap.verseLevels[v1], .medium)

        let loadedSummary = try await service.mistakeSummary(for: v1)
        let summary = try XCTUnwrap(loadedSummary)
        let event = try XCTUnwrap(summary.activeEvents.first)
        try await service.retractMistake(event)

        heatmap = try await service.mistakeHeatmap(for: quran)
        XCTAssertTrue(heatmap.isEmpty)
        let loadedAfter = try await service.mistakeSummary(for: v1)
        let after = try XCTUnwrap(loadedAfter)
        XCTAssertTrue(after.activeEvents.isEmpty)
        XCTAssertEqual(after.retractedEvents.count, 1)
        let repairAfter = try await service.repairQueue()
        XCTAssertTrue(repairAfter.isEmpty)
    }

    func testRetractOneOfTwoWordMistakesKeepsOtherActive() async throws {
        let v1 = try verse(112, 1)
        let passage = Passage(v1, try verse(112, 4))

        try await service.recordSession(passage, startedOn: now, recalls: [
            VerseRecall(verse: v1, outcome: .mistake, mistakenWords: [2, 3], provenance: .model),
        ])

        let loadedSummary = try await service.mistakeSummary(for: v1)
        let summary = try XCTUnwrap(loadedSummary)
        XCTAssertEqual(summary.activeEvents.count, 2)
        let word2Event = try XCTUnwrap(summary.activeEvents.first { $0.word == 2 })
        try await service.retractMistake(word2Event)

        let heatmap = try await service.mistakeHeatmap(for: quran)
        XCTAssertNil(heatmap.wordLevels[Word(verse: v1, wordNumber: 2)])
        XCTAssertEqual(heatmap.wordLevels[Word(verse: v1, wordNumber: 3)], .medium)
        XCTAssertEqual(heatmap.verseLevels[v1], .medium)
    }

    func testRepairQueueDrillsWeakPassagesNotIsolatedWords() async throws {
        let ikhlas1 = try verse(112, 1)
        let ikhlas4 = try verse(112, 4)
        let falaq1 = try verse(113, 1)
        let falaq5 = try verse(113, 5)

        // Declare Al-Ikhlas as a passage; leave Al-Falaq undeclared to verify default passage fallback.
        try await service.declareMemorized(ikhlas1 ... ikhlas4)

        // Record a single-ayah H5-style drill mistake on 112:2 and two mistakes on 113:3.
        try await service.recordSession(Passage(try verse(112, 2), try verse(112, 2)), startedOn: now, recalls: [
            VerseRecall(verse: try verse(112, 2), outcome: .mistake, provenance: .manual),
        ])
        try await service.recordSession(Passage(try verse(113, 3), try verse(113, 3)), startedOn: now, recalls: [
            VerseRecall(verse: try verse(113, 3), outcome: .mistake, mistakenWords: [1], provenance: .manual),
        ])
        now = now.addingTimeInterval(600)
        try await service.recordSession(Passage(try verse(113, 3), try verse(113, 3)), startedOn: now, recalls: [
            VerseRecall(verse: try verse(113, 3), outcome: .mistake, mistakenWords: [1], provenance: .model),
        ])

        let repair = try await service.repairQueue()
        XCTAssertEqual(repair.count, 2)
        // Highest heat (113:1-5 with 2 sessions) comes first, resolved to full sura passage (not isolated 113:3!).
        XCTAssertEqual(repair[0].passage, Passage(falaq1, falaq5))
        XCTAssertEqual(repair[0].maxHeatLevel, .high)
        XCTAssertEqual(repair[0].mistakenVerseCount, 1)
        XCTAssertEqual(repair[0].mistakenWordCount, 1)

        // Second item resolves 112:2 to its declared passage 112:1-4.
        XCTAssertEqual(repair[1].passage, Passage(ikhlas1, ikhlas4))
        XCTAssertEqual(repair[1].maxHeatLevel, .medium)
        XCTAssertEqual(repair[1].mistakenVerseCount, 1)
        XCTAssertEqual(repair[1].mistakenWordCount, 0)
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405
    private var now: Date!
    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var service: MemorizationService!

    private func verse(_ sura: Int, _ ayah: Int) throws -> AyahNumber {
        try XCTUnwrap(AyahNumber(quran: quran, sura: sura, ayah: ayah))
    }
}
