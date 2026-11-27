//
//  MemorizationServiceTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import MemorizationPersistence
import QuranKit
import XCTest
@testable import MemorizationService

final class MemorizationServiceTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        persistence = CoreDataMemorizationPersistence(stack: store.stack())
        clock = Clock()
        service = MemorizationService(persistence: persistence, now: { [clock] in clock!.now })
    }

    override func tearDown() {
        service = nil
        persistence = nil
        store = nil
        super.tearDown()
    }

    func testAPassageNeverPracticedIsUnassessed() async throws {
        let progress = try await service.progress(of: ikhlas)
        XCTAssertEqual(progress.strength, .unassessed)
        XCTAssertNil(progress.due)
        let actual = try await service.progress()
        XCTAssertEqual(actual, [])
    }

    func testRecordingStoresOneManualRecordPerVerseAndMistakenWord() async throws {
        let id = try await service.recordSession(ikhlas, startedOn: clock.now, recalls: [
            VerseRecall(verse: verse(1), outcome: .correct),
            VerseRecall(verse: verse(2), outcome: .mistake, assistance: 2, mistakenWords: [2, 2, 1]),
        ])

        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.map(\.id), [id])
        XCTAssertEqual(history.sessions.first?.first, MemorizationVerse(sura: 112, ayah: 1))
        XCTAssertEqual(history.sessions.first?.last, MemorizationVerse(sura: 112, ayah: 4))
        XCTAssertEqual(history.evidence.count, 4)
        XCTAssertTrue(history.evidence.allSatisfy { $0.provenance == .manual && $0.sessionID == id })
        XCTAssertEqual(
            Set(history.evidence.map { [$0.verse.ayah, $0.word, $0.outcome.rawValue, $0.assistance] }),
            [[1, 0, 0, 0], [2, 0, 1, 2], [2, 1, 1, 0], [2, 2, 1, 0]]
        )
    }

    func testCleanSessionsGrowTheIntervalAndBecomeStrong() async throws {
        try await practice(.correct)
        let first = try await service.progress(of: ikhlas)
        XCTAssertEqual(first.lastGrade, .good)
        XCTAssertEqual(first.gradedSessions, 1)

        clock.advance(days: 1)
        try await practice(.correct)
        clock.advance(days: 3)
        try await practice(.correct)
        let third = try await service.progress(of: ikhlas)
        XCTAssertEqual(third.strength, .strong)
        let firstInterval = try XCTUnwrap(first.due).timeIntervalSince(try XCTUnwrap(first.lastPracticed))
        let thirdInterval = try XCTUnwrap(third.due).timeIntervalSince(try XCTUnwrap(third.lastPracticed))
        XCTAssertGreaterThan(thirdInterval, firstInterval)
    }

    func testARevealedVerseAfterReviewsMakesThePassageLearnAgainSooner() async throws {
        for _ in 0 ..< 3 {
            try await practice(.correct)
            clock.advance(days: 3)
        }
        let strong = try await service.progress(of: ikhlas)
        try await practice(.revealed)
        let forgotten = try await service.progress(of: ikhlas)

        XCTAssertEqual(forgotten.lastGrade, .again)
        XCTAssertEqual(forgotten.strength, .learning)
        XCTAssertLessThan(
            try XCTUnwrap(forgotten.due).timeIntervalSince(clock.now),
            try XCTUnwrap(strong.due).timeIntervalSince(try XCTUnwrap(strong.lastPracticed))
        )
    }

    func testAHardReviewIsWeak() async throws {
        for _ in 0 ..< 3 {
            try await practice(.correct)
            clock.advance(days: 3)
        }
        try await practice(.hint)
        let actual = try await service.progress(of: ikhlas).strength
        XCTAssertEqual(actual, .weak)
    }

    func testRetractedEvidenceNoLongerCounts() async throws {
        let id = try await service.recordSession(ikhlas, startedOn: clock.now, recalls: [
            VerseRecall(verse: verse(1), outcome: .revealed),
        ])
        let actual = try await service.progress(of: ikhlas).lastGrade
        XCTAssertEqual(actual, .again)

        let ids = try await persistence.history().evidence.filter { $0.sessionID == id }.map(\.id)
        try await service.retractEvidence(withIDs: Set(ids))
        let progress = try await service.progress(of: ikhlas)
        XCTAssertEqual(progress.strength, .unassessed)
        XCTAssertEqual(progress.gradedSessions, 0)
        XCTAssertNotNil(progress.lastPracticed)
    }

    func testPassagesAreListedSoonestDueFirst() async throws {
        let fatiha = Passage(AyahNumber(quran: quran, sura: 1, ayah: 1)!, AyahNumber(quran: quran, sura: 1, ayah: 7)!)
        try await practice(.correct)
        try await service.recordSession(fatiha, startedOn: clock.now, recalls: [
            VerseRecall(verse: fatiha.first, outcome: .revealed),
        ])
        let actual = try await service.progress().map(\.passage)
        XCTAssertEqual(actual, [fatiha, ikhlas])
    }

    func testRecordingPreservesModelProvenanceOnRecallEvidence() async throws {
        _ = try await service.recordSession(ikhlas, startedOn: clock.now, recalls: [
            VerseRecall(verse: verse(1), outcome: .correct, provenance: .model),
            VerseRecall(verse: verse(2), outcome: .hint, assistance: 1, provenance: .manual),
        ])

        let evidence = try await persistence.history().evidence.sorted { $0.verse < $1.verse }
        XCTAssertEqual(evidence.map(\.provenance), [.model, .manual])
    }

    func testPassageOrdersItsEnds() {
        XCTAssertEqual(Passage(verse(4), verse(1)), ikhlas)
        XCTAssertEqual(ikhlas.verses.count, 4)
    }

    // MARK: Private

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)

        func advance(days: Double) {
            now += days * 86400
        }
    }

    private let quran = Quran.hafsMadani1405

    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var service: MemorizationService!
    private var clock: Clock!

    private var ikhlas: Passage {
        Passage(verse(1), verse(4))
    }

    private func verse(_ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: 112, ayah: ayah)!
    }

    private func practice(_ secondVerse: RecallOutcome) async throws {
        try await service.recordSession(ikhlas, startedOn: clock.now, recalls: [
            VerseRecall(verse: verse(1), outcome: .correct),
            VerseRecall(verse: verse(2), outcome: secondVerse),
            VerseRecall(verse: verse(3), outcome: .correct),
            VerseRecall(verse: verse(4), outcome: .correct),
        ])
    }
}
