//
//  ReviewQueue.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import QuranKit

/// Classic Hifz review buckets (roadmap H3).
public enum ReviewBucket: String, Codable, Hashable, Sendable, CaseIterable {
    /// New or recently forgotten passages in active learning/relearning.
    case sabaq
    /// Recent consolidation and weak passages needing closer attention.
    case sabqi
    /// Long-term revision and declared passages awaiting verification.
    case manzil
}

/// Daily passage review targets per bucket.
public struct ReviewDailyBudgets: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(sabaq: Int = 2, sabqi: Int = 4, manzil: Int = 5) {
        self.sabaq = Self.clamp(sabaq)
        self.sabqi = Self.clamp(sabqi)
        self.manzil = Self.clamp(manzil)
    }

    // MARK: Public

    public static let range = 0 ... 20

    public var sabaq: Int {
        didSet { sabaq = Self.clamp(sabaq) }
    }

    public var sabqi: Int {
        didSet { sabqi = Self.clamp(sabqi) }
    }

    public var manzil: Int {
        didSet { manzil = Self.clamp(manzil) }
    }

    public func limit(for bucket: ReviewBucket) -> Int {
        switch bucket {
        case .sabaq: sabaq
        case .sabqi: sabqi
        case .manzil: manzil
        }
    }

    // MARK: Private

    private static func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Persists daily Sabaq/Sabqi/Manzil budgets in UserDefaults (preferences, not backed up).
public final class ReviewBudgetStore {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Public

    public var budgets: ReviewDailyBudgets {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode(ReviewDailyBudgets.self, from: data)
            else {
                return ReviewDailyBudgets()
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }

    // MARK: Private

    private static let key = "hifzReview.dailyBudgets"
    private let defaults: UserDefaults
}

/// Why a passage is in the queue or scheduled later (formatted in the UI layer).
public enum ReviewReason: Equatable, Hashable, Sendable {
    /// Consecutive recent sessions had mistakes, hints, or forgot.
    case weakSessions(Int)
    /// Overdue by at least one calendar day.
    case overdueDays(Int)
    /// Due today (within the current calendar day or due now).
    case dueToday
    /// In FSRS learning or relearning.
    case learning
    /// Declared memorized, never graded in practice yet.
    case declaredUnassessed
    /// Skipped or rescheduled until a future date.
    case snoozedUntil(Date)
    /// Upcoming review in `days` calendar days.
    case scheduledInDays(Int)
}

/// One passage entry in the H3 review queue.
public struct ReviewQueueItem: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        passageRecordID: UUID?,
        passage: Passage,
        progress: PassageProgress,
        bucket: ReviewBucket,
        isDeclared: Bool,
        isDue: Bool,
        isWithinDailyBudget: Bool,
        snoozedUntil: Date?,
        reason: ReviewReason
    ) {
        self.id = id
        self.passageRecordID = passageRecordID
        self.passage = passage
        self.progress = progress
        self.bucket = bucket
        self.isDeclared = isDeclared
        self.isDue = isDue
        self.isWithinDailyBudget = isWithinDailyBudget
        self.snoozedUntil = snoozedUntil
        self.reason = reason
    }

    // MARK: Public

    public let id: UUID
    public let passageRecordID: UUID?
    public let passage: Passage
    public let progress: PassageProgress
    public let bucket: ReviewBucket
    public let isDeclared: Bool
    public let isDue: Bool
    public let isWithinDailyBudget: Bool
    public let snoozedUntil: Date?
    public let reason: ReviewReason
}

/// Per-bucket progress against today's budget.
public struct ReviewBucketSummary: Identifiable, Equatable, Hashable, Sendable {
    public let bucket: ReviewBucket
    public let dueCount: Int
    public let completedToday: Int
    public let dailyBudget: Int

    public var remainingBudget: Int {
        max(0, dailyBudget - completedToday)
    }

    public var id: ReviewBucket { bucket }
}

/// An active declared memorized range for display and management.
public struct DeclaredRangeItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let range: ClosedRange<AyahNumber>
    public let declaredOn: Date
}

/// Complete snapshot of the H3 review queue.
public struct ReviewQueueSnapshot: Equatable, Sendable {
    public init(
        dueItems: [ReviewQueueItem] = [],
        upcomingItems: [ReviewQueueItem] = [],
        bucketSummaries: [ReviewBucketSummary] = [],
        declaredRanges: [DeclaredRangeItem] = []
    ) {
        self.dueItems = dueItems
        self.upcomingItems = upcomingItems
        self.bucketSummaries = bucketSummaries
        self.declaredRanges = declaredRanges
    }

    public let dueItems: [ReviewQueueItem]
    public let upcomingItems: [ReviewQueueItem]
    public let bucketSummaries: [ReviewBucketSummary]
    public let declaredRanges: [DeclaredRangeItem]

    public var totalDueCount: Int {
        dueItems.count
    }

    public var budgetedDueItems: [ReviewQueueItem] {
        dueItems.filter(\.isWithinDailyBudget)
    }
}

/// Per-ayah memorization state keeping declared and demonstrated progress distinct (roadmap H1/H3).
public enum AyahMemorizationState: Int, Hashable, Sendable, CaseIterable {
    /// Neither declared nor practiced.
    case notMemorized = 0
    /// Declared memorized, but not yet verified in practice.
    case declaredUnassessed = 1
    /// Practiced and currently learning or relearning.
    case learning = 2
    /// Practiced with recent mistakes or hints.
    case weak = 3
    /// Practiced cleanly on a review interval.
    case strong = 4

    public var isDemonstrated: Bool {
        switch self {
        case .learning, .weak, .strong: true
        case .notMemorized, .declaredUnassessed: false
        }
    }
}

/// Memorization breakdown of one sura's portion inside a Juz.
public struct JuzSuraSlice: Identifiable, Hashable, Sendable {
    public let juzNumber: Int
    public let sura: Sura
    public let firstAyah: Int
    public let lastAyah: Int
    public let declaredCount: Int
    public let demonstratedCount: Int
    public let counts: [AyahMemorizationState: Int]
    public let ayahStates: [AyahMemorizationState]

    public var totalVerses: Int {
        lastAyah - firstAyah + 1
    }

    public var id: String {
        "\(juzNumber)-\(sura.suraNumber)"
    }
}

/// Memorization breakdown of one Juz (1...30).
public struct JuzMemorizationSummary: Identifiable, Hashable, Sendable {
    public let juz: Juz
    public let totalVerses: Int
    public let declaredCount: Int
    public let demonstratedCount: Int
    public let counts: [AyahMemorizationState: Int]
    public let suras: [JuzSuraSlice]

    public var id: Int {
        juz.juzNumber
    }
}

/// Memorization breakdown of one Sura (1...114).
public struct SuraMemorizationSummary: Identifiable, Hashable, Sendable {
    public let sura: Sura
    public let totalVerses: Int
    public let declaredCount: Int
    public let demonstratedCount: Int
    public let counts: [AyahMemorizationState: Int]
    public let ayahStates: [AyahMemorizationState]

    public var id: Int {
        sura.suraNumber
    }
}

/// Whole-Quran memorization map summary (Juz → Surah → Ayah).
public struct MemorizationMapSummary: Equatable, Sendable {
    public let totalVerses: Int
    public let declaredVerseCount: Int
    public let demonstratedVerseCount: Int
    public let counts: [AyahMemorizationState: Int]
    public let juzs: [JuzMemorizationSummary]
    public let suras: [SuraMemorizationSummary]
}
