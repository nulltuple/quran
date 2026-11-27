//
//  HifzReviewViewModel.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import MemorizationService
import Observation
import QuranKit
import VLogging

/// Drives the H3 Memorization screen: Sabaq/Sabqi/Manzil review queue, daily budgets,
/// quick declaration (Surah / Juz / Pages), skip/reschedule/split/reset, and Juz → Surah → Ayah map.
@MainActor
@Observable
public final class HifzReviewViewModel {
    // MARK: Lifecycle

    public init(
        service: MemorizationService,
        budgetStore: ReviewBudgetStore = ReviewBudgetStore(),
        quran: Quran = .hafsMadani1405,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        practicePassage: @escaping (Passage) -> Void,
        openAyah: @escaping (AyahNumber) -> Void,
        openSpotTest: @escaping () -> Void = {}
    ) {
        self.service = service
        self.budgetStore = budgetStore
        self.quran = quran
        self.calendar = calendar
        self.now = now
        self.practicePassage = practicePassage
        self.openAyah = openAyah
        openSpotTestHandler = openSpotTest
        budgets = budgetStore.budgets
    }

    // MARK: Public

    public enum SectionTab: Int, CaseIterable, Hashable {
        case queue
        case map
    }

    public enum BucketFilter: Hashable {
        case all
        case bucket(ReviewBucket)
    }

    public enum DeclareMode: Int, CaseIterable, Hashable {
        case surah
        case juz
        case pages
    }

    public let quran: Quran
    public var selectedTab: SectionTab = .queue
    public var bucketFilter: BucketFilter = .all
    public var queue = ReviewQueueSnapshot(dueItems: [], upcomingItems: [], bucketSummaries: [], declaredRanges: [])
    public var map: MemorizationMapSummary?
    public var budgets: ReviewDailyBudgets
    public var isLoading = false
    public var loadFailed = false

    public var isDeclarePresented = false
    public var isBudgetsPresented = false
    public var rescheduleTarget: ReviewQueueItem?
    public var splitTarget: ReviewQueueItem?
    public var resetTarget: ReviewQueueItem?
    public var removeRangeTarget: DeclaredRangeItem?

    public var filteredDueToday: [ReviewQueueItem] {
        filtered(queue.dueItems.filter(\.isWithinDailyBudget))
    }

    public var filteredMoreDue: [ReviewQueueItem] {
        filtered(queue.dueItems.filter { !$0.isWithinDailyBudget })
    }

    public var filteredUpcoming: [ReviewQueueItem] {
        filtered(queue.upcomingItems)
    }

    public func reload() async {
        isLoading = true
        loadFailed = false
        let service = service
        let budgets = budgets
        let calendar = calendar
        do {
            async let loadedQueue = service.reviewQueue(budgets: budgets, calendar: calendar)
            async let loadedMap = service.mapSummary()
            queue = try await loadedQueue
            map = try await loadedMap
        } catch {
            logger.error("HifzReview: failed to load queue/map: \(error)")
            loadFailed = true
        }
        isLoading = false
    }

    public func toggleBucketFilter(_ bucket: ReviewBucket) {
        if bucketFilter == .bucket(bucket) {
            bucketFilter = .all
        } else {
            bucketFilter = .bucket(bucket)
        }
    }

    public func startPractice(_ item: ReviewQueueItem) {
        practicePassage(item.passage)
    }

    public func startPractice(range: ClosedRange<AyahNumber>) {
        practicePassage(Passage(range.lowerBound, range.upperBound))
    }

    public func openInReader(_ ayah: AyahNumber) {
        openAyah(ayah)
    }

    public func openSpotTest() {
        openSpotTestHandler()
    }

    public func declareSuras(_ suras: [Sura]) async {
        guard !suras.isEmpty else { return }
        let sorted = suras.sorted()
        let ranges = AyahRangeSet(sorted.map { $0.firstVerse ... $0.lastVerse }).ranges
        await declareRanges(ranges)
    }

    public func declareJuzs(_ juzs: [Juz]) async {
        guard !juzs.isEmpty else { return }
        let sorted = juzs.sorted()
        let ranges = AyahRangeSet(sorted.map { $0.firstVerse ... $0.lastVerse }).ranges
        await declareRanges(ranges)
    }

    public func declarePages(from startPage: Int, to endPage: Int) async {
        let low = max(1, min(quran.numberOfPages, min(startPage, endPage)))
        let high = max(1, min(quran.numberOfPages, max(startPage, endPage)))
        guard let first = Page(quran: quran, pageNumber: low)?.firstVerse,
              let last = Page(quran: quran, pageNumber: high)?.lastVerse
        else {
            return
        }
        await declareRanges([first ... last])
    }

    public func pageRangePreview(from startPage: Int, to endPage: Int) -> ClosedRange<AyahNumber>? {
        let low = max(1, min(quran.numberOfPages, min(startPage, endPage)))
        let high = max(1, min(quran.numberOfPages, max(startPage, endPage)))
        guard let first = Page(quran: quran, pageNumber: low)?.firstVerse,
              let last = Page(quran: quran, pageNumber: high)?.lastVerse
        else {
            return nil
        }
        return first ... last
    }

    public func saveBudgets(_ newBudgets: ReviewDailyBudgets) async {
        budgets = newBudgets
        budgetStore.budgets = newBudgets
        await reload()
    }

    public func skip(_ item: ReviewQueueItem) async {
        do {
            try await service.skipPassage(item.passage, passageRecordID: item.passageRecordID, calendar: calendar)
            await reload()
        } catch {
            logger.error("HifzReview: skip failed: \(error)")
            loadFailed = true
        }
    }

    public func reschedule(_ item: ReviewQueueItem, until date: Date) async {
        do {
            try await service.reschedulePassage(item.passage, passageRecordID: item.passageRecordID, until: date)
            rescheduleTarget = nil
            await reload()
        } catch {
            logger.error("HifzReview: reschedule failed: \(error)")
            loadFailed = true
        }
    }

    public func rescheduleDate(daysFromNow days: Int) -> Date {
        let base = now()
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: base) ?? base.addingTimeInterval(Double(days) * 86400))
    }

    public func split(_ item: ReviewQueueItem, after verse: AyahNumber) async {
        do {
            try await service.splitPassage(id: item.passageRecordID, passage: item.passage, after: verse)
            splitTarget = nil
            await reload()
        } catch {
            logger.error("HifzReview: split failed: \(error)")
            loadFailed = true
        }
    }

    public func confirmReset(_ item: ReviewQueueItem) async {
        do {
            try await service.resetPassage(item.passage, passageRecordID: item.passageRecordID)
            resetTarget = nil
            await reload()
        } catch {
            logger.error("HifzReview: reset failed: \(error)")
            loadFailed = true
        }
    }

    public func confirmRemoveRange(_ item: DeclaredRangeItem) async {
        do {
            try await service.removeDeclaredRange(id: item.id)
            removeRangeTarget = nil
            await reload()
        } catch {
            logger.error("HifzReview: remove range failed: \(error)")
            loadFailed = true
        }
    }

    // MARK: Private

    private let service: MemorizationService
    private let budgetStore: ReviewBudgetStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let practicePassage: (Passage) -> Void
    private let openAyah: (AyahNumber) -> Void
    private let openSpotTestHandler: () -> Void

    private func filtered(_ items: [ReviewQueueItem]) -> [ReviewQueueItem] {
        switch bucketFilter {
        case .all: items
        case .bucket(let bucket): items.filter { $0.bucket == bucket }
        }
    }

    private func declareRanges(_ ranges: [ClosedRange<AyahNumber>]) async {
        do {
            for range in ranges {
                _ = try await service.declareMemorized(range)
            }
            await reload()
        } catch {
            logger.error("HifzReview: declare failed: \(error)")
            loadFailed = true
        }
    }
}
