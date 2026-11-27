//
//  ReviewQueueAndMapTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import MemorizationPersistence
import QuranKit
import XCTest
@testable import MemorizationService

final class ReviewQueueAndMapTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        persistence = CoreDataMemorizationPersistence(stack: store.stack())
        clock = Clock()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = utc
        service = MemorizationService(persistence: persistence, now: { [clock] in clock!.now })
    }

    override func tearDown() {
        service = nil
        persistence = nil
        store = nil
        super.tearDown()
    }

    func testDeclaringRangeCreatesDefaultPassagesAndShowsDeclaredUnassessedInQueueAndMap() async throws {
        // Declare page 604 (Suras 112-114).
        let record = try await service.declareMemorized(v(112, 1) ... v(114, 6))

        let queue = try await service.reviewQueue(calendar: calendar)
        XCTAssertEqual(queue.declaredRanges.map(\.id), [record.id])
        XCTAssertEqual(queue.dueItems.count, 3)
        XCTAssertEqual(queue.dueItems.map(\.passage), [
            Passage(v(112, 1), v(112, 4)),
            Passage(v(113, 1), v(113, 5)),
            Passage(v(114, 1), v(114, 6)),
        ])
        XCTAssertTrue(queue.dueItems.allSatisfy { $0.bucket == .manzil && $0.reason == .declaredUnassessed && $0.isDeclared })

        let map = try await service.mapSummary()
        XCTAssertEqual(map.totalVerses, 6236)
        XCTAssertEqual(map.declaredVerseCount, 15)
        XCTAssertEqual(map.demonstratedVerseCount, 0)
        XCTAssertEqual(map.counts[.declaredUnassessed], 15)

        let juz30 = try XCTUnwrap(map.juzs.last)
        XCTAssertEqual(juz30.juz.juzNumber, 30)
        XCTAssertEqual(juz30.declaredCount, 15)
        XCTAssertEqual(juz30.demonstratedCount, 0)
        let ikhlasSlice = try XCTUnwrap(juz30.suras.first { $0.sura.suraNumber == 112 })
        XCTAssertEqual(ikhlasSlice.ayahStates, Array(repeating: .declaredUnassessed, count: 4))
    }

    func testBucketsAndReasonsReflectWeakSessionsOverdueDaysAndDailyBudgets() async throws {
        let ikhlas = Passage(v(112, 1), v(112, 4))
        let falaq = Passage(v(113, 1), v(113, 5))
        let nas = Passage(v(114, 1), v(114, 6))
        _ = try await service.declareMemorized(v(112, 1) ... v(114, 6))

        // 1) Graduate Al-Ikhlas into review, then make it weak across 3 sessions (Sabqi, weak 3 sessions).
        for _ in 0 ..< 3 {
            try await record(ikhlas, outcomes: [.correct, .correct, .correct, .correct])
            clock.advance(days: 3)
        }
        for _ in 0 ..< 3 {
            try await record(ikhlas, outcomes: [.correct, .hint, .correct, .correct])
            clock.advance(days: 4)
        }
        // 2) Make Al-Falaq strong and then overdue by 2 days.
        for _ in 0 ..< 3 {
            try await record(falaq, outcomes: [.correct, .correct, .correct, .correct, .correct])
            clock.advance(days: 4)
        }
        let falaqProgress = try await service.progress(of: falaq)
        let falaqDue = try XCTUnwrap(falaqProgress.due)
        clock.now = falaqDue.addingTimeInterval(2 * 86400 + 3600)

        // Ensure ikhlas is also due now.
        let ikhlasProgress = try await service.progress(of: ikhlas)
        if let ikhlasDue = ikhlasProgress.due, ikhlasDue > clock.now {
            clock.now = ikhlasDue.addingTimeInterval(3600)
        }

        let budgets = ReviewDailyBudgets(sabaq: 1, sabqi: 1, manzil: 1)
        let queue = try await service.reviewQueue(budgets: budgets, calendar: calendar)

        let ikhlasItem = try XCTUnwrap(queue.dueItems.first { $0.passage == ikhlas })
        XCTAssertEqual(ikhlasItem.bucket, .sabqi)
        XCTAssertEqual(ikhlasItem.reason, .weakSessions(3))
        XCTAssertTrue(ikhlasItem.isWithinDailyBudget)

        let falaqItem = try XCTUnwrap(queue.dueItems.first { $0.passage == falaq })
        if case .overdueDays(let days) = falaqItem.reason {
            XCTAssertGreaterThanOrEqual(days, 2)
        } else {
            XCTFail("Expected overdueDays reason for Al-Falaq, got \(falaqItem.reason)")
        }

        let nasItem = try XCTUnwrap(queue.dueItems.first { $0.passage == nas })
        XCTAssertEqual(nasItem.bucket, .manzil)
        XCTAssertEqual(nasItem.reason, .declaredUnassessed)

        // 3) A passage with a revealed verse goes to Sabaq (learning).
        let fatiha = Passage(v(1, 1), v(1, 7))
        try await record(fatiha, outcomes: [.correct, .revealed, .correct, .correct, .correct, .correct, .correct])
        clock.advance(days: 1)
        let queueWithSabaq = try await service.reviewQueue(budgets: budgets, calendar: calendar)
        let fatihaItem = try XCTUnwrap(queueWithSabaq.dueItems.first { $0.passage == fatiha })
        XCTAssertEqual(fatihaItem.bucket, .sabaq)
        XCTAssertEqual(fatihaItem.reason, .learning)

        // Verify map separates declared (15) from demonstrated (4 + 5 + 7 = 16).
        let map = try await service.mapSummary()
        XCTAssertEqual(map.declaredVerseCount, 15)
        XCTAssertEqual(map.demonstratedVerseCount, 16)
        let ikhlasSura = map.suras[111]
        XCTAssertEqual(ikhlasSura.ayahStates[1], .weak)
    }

    func testSkipRescheduleSplitResetAndRemoveDeclaration() async throws {
        let range = try await service.declareMemorized(v(112, 1) ... v(112, 4))
        var queue = try await service.reviewQueue(calendar: calendar)
        let item = try XCTUnwrap(queue.dueItems.first)

        // Skip moves passage out of dueItems into upcoming with snoozedUntil = start of tomorrow.
        try await service.skipPassage(item.passage, passageRecordID: item.passageRecordID, calendar: calendar)
        queue = try await service.reviewQueue(calendar: calendar)
        XCTAssertTrue(queue.dueItems.isEmpty)
        XCTAssertEqual(queue.upcomingItems.count, 1)
        if case .snoozedUntil = queue.upcomingItems[0].reason {
            // Expected
        } else {
            XCTFail("Expected snoozedUntil after skip")
        }

        // Advance to tomorrow: passage becomes due again.
        clock.advance(days: 1)
        queue = try await service.reviewQueue(calendar: calendar)
        XCTAssertEqual(queue.dueItems.count, 1)

        // Practice with a mistake, then reset: retracts evidence and returns to unassessed.
        try await record(item.passage, outcomes: [.correct, .revealed, .correct, .correct])
        let beforeReset = try await service.progress(of: item.passage)
        XCTAssertEqual(beforeReset.gradedSessions, 1)

        try await service.resetPassage(item.passage, passageRecordID: item.passageRecordID)
        let afterReset = try await service.progress(of: item.passage)
        XCTAssertEqual(afterReset.strength, .unassessed)
        XCTAssertEqual(afterReset.gradedSessions, 0)

        // Split 112:1-4 after 112:2 -> [112:1-2, 112:3-4].
        try await service.splitPassage(id: item.passageRecordID, passage: item.passage, after: v(112, 2))
        queue = try await service.reviewQueue(calendar: calendar)
        XCTAssertEqual(queue.dueItems.map(\.passage), [
            Passage(v(112, 1), v(112, 2)),
            Passage(v(112, 3), v(112, 4)),
        ])

        // Removing the declared range tombstones the range and its passages.
        try await service.removeDeclaredRange(id: range.id)
        queue = try await service.reviewQueue(calendar: calendar)
        XCTAssertTrue(queue.declaredRanges.isEmpty)
        XCTAssertTrue(queue.dueItems.isEmpty)
    }

    func testDailyBudgetStorePersistsAndClamps() {
        let suite = "ReviewBudgetStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReviewBudgetStore(defaults: defaults)
        XCTAssertEqual(store.budgets, ReviewDailyBudgets(sabaq: 2, sabqi: 4, manzil: 5))

        store.budgets = ReviewDailyBudgets(sabaq: -3, sabqi: 7, manzil: 99)
        XCTAssertEqual(store.budgets, ReviewDailyBudgets(sabaq: 0, sabqi: 7, manzil: 20))
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
    private var calendar: Calendar!

    private func v(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }

    private func record(_ passage: Passage, outcomes: [RecallOutcome]) async throws {
        let recalls = zip(passage.verses, outcomes).map { verse, outcome in
            VerseRecall(verse: verse, outcome: outcome, assistance: outcome == .hint ? 1 : 0)
        }
        try await service.recordSession(passage, startedOn: clock.now, recalls: recalls)
    }
}
