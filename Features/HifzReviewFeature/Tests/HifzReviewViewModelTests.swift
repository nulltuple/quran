//
//  HifzReviewViewModelTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import MemorizationPersistence
import MemorizationService
import QuranKit
import XCTest
@testable import HifzReviewFeature

@MainActor
final class HifzReviewViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        persistence = CoreDataMemorizationPersistence(stack: store.stack())
        suiteName = "HifzReviewViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        budgetStore = ReviewBudgetStore(defaults: defaults)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = utc
        clock = Clock()
        practicedPassages = []
        openedAyahs = []
        service = MemorizationService(persistence: persistence, now: { [clock] in clock!.now })
        sut = HifzReviewViewModel(
            service: service,
            budgetStore: budgetStore,
            calendar: calendar,
            now: { [clock] in clock!.now },
            practicePassage: { [weak self] in self?.practicedPassages.append($0) },
            openAyah: { [weak self] in self?.openedAyahs.append($0) }
        )
    }

    override func tearDown() {
        sut = nil
        service = nil
        budgetStore = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        persistence = nil
        store = nil
        super.tearDown()
    }

    func testDeclareSurasPopulatesQueueAndMapAndLaunchesPractice() async {
        let ikhlas = Sura(quran: quran, suraNumber: 112)!
        let falaq = Sura(quran: quran, suraNumber: 113)!

        await sut.declareSuras([falaq, ikhlas])

        XCTAssertEqual(sut.queue.declaredRanges.count, 1, "Adjacent suras normalize into one declared range")
        XCTAssertEqual(sut.queue.dueItems.count, 2)
        XCTAssertEqual(sut.map?.declaredVerseCount, 9)
        XCTAssertEqual(sut.map?.demonstratedVerseCount, 0)

        let first = sut.queue.dueItems[0]
        sut.startPractice(first)
        XCTAssertEqual(practicedPassages, [first.passage])
    }

    func testDeclarePagesClampsAndOrdersEndpoints() async {
        await sut.declarePages(from: 604, to: 604)

        XCTAssertEqual(sut.queue.dueItems.count, 3)
        XCTAssertEqual(sut.map?.declaredVerseCount, 15)
    }

    func testBucketFilterBudgetsSkipRescheduleSplitResetAndRemove() async throws {
        let ikhlas = Sura(quran: quran, suraNumber: 112)!
        await sut.declareSuras([ikhlas])
        let item = try XCTUnwrap(sut.queue.dueItems.first)

        // Filter to Sabaq hides Manzil items; toggling again shows all.
        sut.toggleBucketFilter(.sabaq)
        XCTAssertTrue(sut.filteredDueToday.isEmpty)
        sut.toggleBucketFilter(.sabaq)
        XCTAssertEqual(sut.filteredDueToday.count, 1)

        // Setting Manzil budget to 0 moves item from Due Today into More Due.
        await sut.saveBudgets(ReviewDailyBudgets(sabaq: 2, sabqi: 4, manzil: 0))
        XCTAssertTrue(sut.filteredDueToday.isEmpty)
        XCTAssertEqual(sut.filteredMoreDue.count, 1)

        // Skip moves item into upcoming.
        await sut.skip(item)
        XCTAssertTrue(sut.queue.dueItems.isEmpty)
        XCTAssertEqual(sut.filteredUpcoming.count, 1)

        // Reset clears snooze and returns item to due queue.
        let snoozed = try XCTUnwrap(sut.queue.upcomingItems.first)
        await sut.confirmReset(snoozed)
        XCTAssertEqual(sut.queue.dueItems.count, 1)

        // Split after 112:2 creates two due passages.
        let dueItem = try XCTUnwrap(sut.queue.dueItems.first)
        await sut.split(dueItem, after: AyahNumber(quran: quran, sura: 112, ayah: 2)!)
        XCTAssertEqual(sut.queue.dueItems.count, 2)

        // Remove declared range clears queue and map.
        let declared = try XCTUnwrap(sut.queue.declaredRanges.first)
        await sut.confirmRemoveRange(declared)
        XCTAssertTrue(sut.queue.declaredRanges.isEmpty)
        XCTAssertEqual(sut.map?.declaredVerseCount, 0)
    }

    func testRescheduleDateStartsAtTargetDayAndOpenInReaderForwardsAyah() async throws {
        let ikhlas = Sura(quran: quran, suraNumber: 112)!
        await sut.declareSuras([ikhlas])
        let item = try XCTUnwrap(sut.queue.dueItems.first)

        let target = sut.rescheduleDate(daysFromNow: 3)
        await sut.reschedule(item, until: target)
        XCTAssertTrue(sut.queue.dueItems.isEmpty)
        XCTAssertEqual(sut.queue.upcomingItems.first?.snoozedUntil, target)

        sut.openInReader(ikhlas.firstVerse)
        XCTAssertEqual(openedAyahs, [ikhlas.firstVerse])
    }

    // MARK: Private

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private let quran = Quran.hafsMadani1405
    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var budgetStore: ReviewBudgetStore!
    private var calendar: Calendar!
    private var clock: Clock!
    private var service: MemorizationService!
    private var sut: HifzReviewViewModel!
    private var practicedPassages: [Passage] = []
    private var openedAyahs: [AyahNumber] = []
}
