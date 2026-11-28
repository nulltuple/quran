//
//  StudyGoals.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import QuranKit

/// Built-in H6 planning presets (roadmap §6 H6).
public enum StudyGoalPreset: String, CaseIterable, Identifiable, Sendable {
    case fridayAlKahf = "friday_alkahf"
    case ramadanKhatmah = "ramadan_khatmah"
    case sevenPartWeek = "seven_part_week"

    // MARK: Public

    public var id: String { rawValue }

    /// Creates a new `StudyGoalRecord` for this preset anchored at `startDate`.
    public func makeRecord(
        id: UUID,
        title: String,
        startDate: Date,
        calendar: Calendar = .current,
        quran: Quran = .hafsMadani1405
    ) -> StudyGoalRecord {
        let dayStart = calendar.startOfDay(for: startDate)
        let totalPages = quran.pages.count
        switch self {
        case .fridayAlKahf:
            return StudyGoalRecord(
                id: id,
                title: title,
                kind: .weeklySurah,
                activity: .read,
                unit: .completions,
                workloadMode: .fixed,
                targetAmount: 1,
                weekdayMask: WeekdaySchedule.friday.rawValue,
                startDate: dayStart,
                deadline: nil,
                startPage: 1,
                targetFirst: MemorizationVerse(sura: 18, ayah: 1),
                targetLast: MemorizationVerse(sura: 18, ayah: 110),
                presetID: rawValue,
                isPaused: false,
                createdOn: startDate,
                modifiedOn: startDate
            )
        case .ramadanKhatmah:
            let deadline = calendar.date(byAdding: .day, value: 29, to: dayStart) ?? dayStart
            return StudyGoalRecord(
                id: id,
                title: title,
                kind: .khatmah,
                activity: .read,
                unit: .pages,
                workloadMode: .flexible,
                targetAmount: totalPages,
                weekdayMask: WeekdaySchedule.all.rawValue,
                startDate: dayStart,
                deadline: deadline,
                startPage: 1,
                targetFirst: MemorizationVerse(sura: 1, ayah: 1),
                targetLast: MemorizationVerse(sura: 114, ayah: 6),
                presetID: rawValue,
                isPaused: false,
                createdOn: startDate,
                modifiedOn: startDate
            )
        case .sevenPartWeek:
            let deadline = calendar.date(byAdding: .day, value: 6, to: dayStart) ?? dayStart
            return StudyGoalRecord(
                id: id,
                title: title,
                kind: .khatmah,
                activity: .read,
                unit: .pages,
                workloadMode: .flexible,
                targetAmount: totalPages,
                weekdayMask: WeekdaySchedule.all.rawValue,
                startDate: dayStart,
                deadline: deadline,
                startPage: 1,
                targetFirst: MemorizationVerse(sura: 1, ayah: 1),
                targetLast: MemorizationVerse(sura: 114, ayah: 6),
                presetID: rawValue,
                isPaused: false,
                createdOn: startDate,
                modifiedOn: startDate
            )
        }
    }
}

/// Pace of a Khatmah or deadline-bounded flexible goal.
public enum GoalPaceStatus: Equatable, Sendable {
    case completed
    case onTrack
    case ahead(units: Int)
    case behind(units: Int)
    case paused
}

/// Derived progress for a single goal or Khatmah plan as of a point in time.
public struct GoalProgressSnapshot: Equatable, Identifiable, Sendable {
    public let goal: StudyGoalRecord
    public let isScheduledToday: Bool
    public let todayTarget: Int
    public let todayCompleted: Int
    public let todayRemaining: Int
    public let isTodayMet: Bool
    public let totalTarget: Int?
    public let totalCompleted: Int
    public let totalRemaining: Int?
    public let remainingScheduledDays: Int?
    /// Next unread Mushaf page (1...604) for a Khatmah plan, or `nil` when completed or not a Khatmah.
    public let nextKhatmahPage: Int?
    /// Planned Mushaf page range for today on a Khatmah plan (e.g. `81...101`).
    public let todayKhatmahPageRange: ClosedRange<Int>?
    public let paceStatus: GoalPaceStatus?

    public var id: UUID { goal.id }

    public var todayFraction: Double {
        guard todayTarget > 0 else { return isTodayMet ? 1 : 0 }
        return min(1, Double(todayCompleted) / Double(todayTarget))
    }

    public var totalFraction: Double? {
        guard let totalTarget, totalTarget > 0 else { return nil }
        return min(1, Double(totalCompleted) / Double(totalTarget))
    }

    /// Canonical ayah to open in the reader when jumping into this goal, if applicable.
    public func navigationTarget(in targetQuran: Quran, canonicalQuran: Quran = .hafsMadani1405) -> AyahNumber? {
        if goal.kind == .khatmah, let nextPage = nextKhatmahPage,
           let page = Page(quran: canonicalQuran, pageNumber: nextPage)
        {
            let verse = page.firstVerse
            return AyahNumber(quran: targetQuran, sura: verse.sura.suraNumber, ayah: verse.ayah) ?? verse
        }
        if let first = goal.targetFirst {
            return AyahNumber(quran: targetQuran, sura: first.sura, ayah: first.ayah)
        }
        return nil
    }
}

/// Gentle consistency summary: rest days never break a streak, and 1 missed scheduled day in a rolling
/// 7-day window is forgiven as a grace day so daily Quran habits stay encouraging rather than punitive.
public struct GentleStreakSummary: Equatable, Sendable {
    public let currentStreakDays: Int
    public let longestStreakDays: Int
    public let graceDayUsedInCurrentStreak: Bool
    public let activeDaysThisWeek: Int
    public let activeDaysLast30Days: Int
    public let isActiveToday: Bool

    public static let empty = Self(
        currentStreakDays: 0,
        longestStreakDays: 0,
        graceDayUsedInCurrentStreak: false,
        activeDaysThisWeek: 0,
        activeDaysLast30Days: 0,
        isActiveToday: false
    )
}

/// Activity totals for a single calendar day.
public struct DayActivityBucket: Equatable, Identifiable, Sendable {
    public let dayStart: Date
    public let readingSeconds: Int
    public let listeningSeconds: Int
    public let practiceSeconds: Int
    public let pagesCount: Int
    public let isActive: Bool

    public var id: Date { dayStart }
    public var totalSeconds: Int { readingSeconds + listeningSeconds + practiceSeconds }
}

/// Complete H6 Today summary for Home and the Goals & Khatmah screen.
public struct TodayPlanSummary: Equatable, Sendable {
    public let date: Date
    public let todayReadingSeconds: Int
    public let todayListeningSeconds: Int
    public let todayPracticeSeconds: Int
    public let todayPagesRead: Int
    public let goals: [GoalProgressSnapshot]
    public let streak: GentleStreakSummary
    public let last7Days: [DayActivityBucket]

    public var todayTotalSeconds: Int {
        todayReadingSeconds + todayListeningSeconds + todayPracticeSeconds
    }

    public var scheduledTodayGoals: [GoalProgressSnapshot] {
        goals.filter { !$0.goal.isPaused && $0.isScheduledToday }
    }

    public var completedTodayGoalCount: Int {
        scheduledTodayGoals.filter(\.isTodayMet).count
    }

    public var activeGoalCount: Int {
        goals.filter { !$0.goal.isPaused }.count
    }

    public static func empty(on date: Date) -> Self {
        Self(
            date: date,
            todayReadingSeconds: 0,
            todayListeningSeconds: 0,
            todayPracticeSeconds: 0,
            todayPagesRead: 0,
            goals: [],
            streak: .empty,
            last7Days: []
        )
    }
}

/// Pure, deterministic reducer computing H6 goals, Khatmah schedules, activity totals, and gentle streaks
/// directly from persisted `MemorizationHistory` (never duplicating derived state in Core Data).
public enum StudyGoalPlanner {
    // MARK: Public

    /// Minimum total active seconds on a day (when no pages/passages/completions were logged) to count as active for streaks.
    public static let minimumActiveDaySeconds = 60
    /// Minimum active reading pages inside Surah Al-Kahf to auto-complete the Friday Al-Kahf goal without a manual check-in.
    public static let minimumAlKahfAutoCompletePages = 6

    public static func todayPlan(
        history: MemorizationHistory,
        quran: Quran = .hafsMadani1405,
        now: Date,
        calendar: Calendar = .current
    ) -> TodayPlanSummary {
        let todayStart = calendar.startOfDay(for: now)
        let activeGoals = history.goals
            .filter { $0.removedOn == nil }
            .sorted { ($0.createdOn, $0.id.uuidString) < ($1.createdOn, $1.id.uuidString) }
        let activeLogs = history.activityLogs.filter { $0.retractedOn == nil }
        let practiceEntries = buildPracticeEntries(history: history, quran: quran, calendar: calendar)

        // Group activity by local calendar day.
        var logsByDay: [Date: [ActivityLogRecord]] = [:]
        for log in activeLogs {
            let day = calendar.startOfDay(for: log.startedOn)
            logsByDay[day, default: []].append(log)
        }
        var practiceByDay: [Date: [PracticeActivityEntry]] = [:]
        for entry in practiceEntries {
            practiceByDay[entry.dayStart, default: []].append(entry)
        }

        let todayLogs = logsByDay[todayStart] ?? []
        let todayPractice = practiceByDay[todayStart] ?? []

        let todayReadingSeconds = todayLogs
            .filter { $0.activity == .read }
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
        let todayListeningSeconds = todayLogs
            .filter { $0.activity == .listen }
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
        let todayPracticeSeconds = todayPractice.reduce(0) { $0 + $1.durationSeconds }
            + todayLogs
            .filter { $0.activity == .memorize || $0.activity == .review }
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
        let todayPagesRead = todayLogs
            .filter { $0.activity == .read }
            .reduce(0) { $0 + max(0, $1.pagesCount) }

        let goalSnapshots = activeGoals.map { goal in
            evaluateGoal(
                goal,
                logs: activeLogs,
                practiceEntries: practiceEntries,
                quran: quran,
                todayStart: todayStart,
                calendar: calendar
            )
        }
        .sorted { lhs, rhs in
            // Active scheduled-today unfinished first, then active scheduled-today done, then rest-day, then paused.
            func rank(_ item: GoalProgressSnapshot) -> Int {
                if item.goal.isPaused { return 4 }
                if item.isScheduledToday && !item.isTodayMet { return 0 }
                if item.isScheduledToday && item.isTodayMet { return 1 }
                return 2
            }
            let r1 = rank(lhs)
            let r2 = rank(rhs)
            if r1 != r2 { return r1 < r2 }
            return lhs.goal.createdOn < rhs.goal.createdOn
        }

        let allActivityDays = Set(logsByDay.keys).union(practiceByDay.keys)
        let activeDays: Set<Date> = Set(allActivityDays.filter { day in
            isDayActive(logs: logsByDay[day] ?? [], practice: practiceByDay[day] ?? [])
        })

        let combinedSchedule = combinedActiveSchedule(goals: activeGoals)
        let streak = computeGentleStreak(
            activeDays: activeDays,
            schedule: combinedSchedule,
            todayStart: todayStart,
            calendar: calendar
        )

        let last7Days: [DayActivityBucket] = (0 ..< 7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            let dayLogs = logsByDay[day] ?? []
            let dayPractice = practiceByDay[day] ?? []
            let readSec = dayLogs.filter { $0.activity == .read }.reduce(0) { $0 + max(0, $1.durationSeconds) }
            let listenSec = dayLogs.filter { $0.activity == .listen }.reduce(0) { $0 + max(0, $1.durationSeconds) }
            let pracSec = dayPractice.reduce(0) { $0 + $1.durationSeconds }
                + dayLogs.filter { $0.activity == .memorize || $0.activity == .review }.reduce(0) { $0 + max(0, $1.durationSeconds) }
            let pages = dayLogs.filter { $0.activity == .read }.reduce(0) { $0 + max(0, $1.pagesCount) }
            return DayActivityBucket(
                dayStart: day,
                readingSeconds: readSec,
                listeningSeconds: listenSec,
                practiceSeconds: pracSec,
                pagesCount: pages,
                isActive: activeDays.contains(day)
            )
        }

        return TodayPlanSummary(
            date: now,
            todayReadingSeconds: todayReadingSeconds,
            todayListeningSeconds: todayListeningSeconds,
            todayPracticeSeconds: todayPracticeSeconds,
            todayPagesRead: todayPagesRead,
            goals: goalSnapshots,
            streak: streak,
            last7Days: last7Days
        )
    }

    /// Counts scheduled calendar days in `fromDay ... toDay` inclusive.
    public static func scheduledDayCount(
        from fromDay: Date,
        through toDay: Date,
        schedule: WeekdaySchedule,
        calendar: Calendar
    ) -> Int {
        let start = calendar.startOfDay(for: fromDay)
        let end = calendar.startOfDay(for: toDay)
        guard start <= end, !schedule.isEmpty else { return 0 }
        let totalDays = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        guard totalDays > 0 else { return 0 }
        let fullWeeks = totalDays / 7
        let remainder = totalDays % 7
        var count = fullWeeks * schedule.count
        if remainder > 0 {
            let startWeekday = calendar.component(.weekday, from: start)
            for offset in 0 ..< remainder {
                let weekday = ((startWeekday - 1 + offset) % 7) + 1
                if schedule.contains(.weekday(weekday)) {
                    count += 1
                }
            }
        }
        return count
    }

    // MARK: Private

    private struct PracticeActivityEntry {
        let dayStart: Date
        let activity: GoalActivity
        let durationSeconds: Int
        let ayahsCount: Int
        let pagesCount: Int
        let passagesCount: Int
        let first: MemorizationVerse
        let last: MemorizationVerse
    }

    private static func buildPracticeEntries(
        history: MemorizationHistory,
        quran: Quran,
        calendar: Calendar
    ) -> [PracticeActivityEntry] {
        let evidenceBySession = Dictionary(grouping: EvidenceReducer.effective(history.evidence), by: \.sessionID)
        let sortedSessions = history.sessions.sorted { $0.startedOn < $1.startedOn }
        var firstSeenDayByRange: [String: Date] = [:]
        var entries: [PracticeActivityEntry] = []

        for session in sortedSessions {
            let day = calendar.startOfDay(for: session.endedOn ?? session.startedOn)
            let rangeKey = "\(session.first.sura):\(session.first.ayah)-\(session.last.sura):\(session.last.ayah)"
            let activity: GoalActivity
            if let firstDay = firstSeenDayByRange[rangeKey], firstDay < day {
                activity = .review
            } else {
                firstSeenDayByRange[rangeKey] = firstSeenDayByRange[rangeKey] ?? day
                activity = .memorize
            }

            let ended = session.endedOn ?? session.startedOn
            let duration = max(0, min(3600, Int(ended.timeIntervalSince(session.startedOn))))
            let sessionEvidence = evidenceBySession[session.id] ?? []
            let gradedVerses = Set(sessionEvidence.filter { $0.word == 0 }.map(\.verse))
            let ayahsCount = max(gradedVerses.count, 1)

            var pages: Set<Int> = []
            if let firstAyah = AyahNumber(quran: quran, sura: session.first.sura, ayah: session.first.ayah),
               let lastAyah = AyahNumber(quran: quran, sura: session.last.sura, ayah: session.last.ayah),
               firstAyah <= lastAyah
            {
                pages.insert(firstAyah.page.pageNumber)
                pages.insert(lastAyah.page.pageNumber)
                if firstAyah.page.pageNumber < lastAyah.page.pageNumber {
                    for p in firstAyah.page.pageNumber ... lastAyah.page.pageNumber {
                        pages.insert(p)
                    }
                }
            }

            entries.append(
                PracticeActivityEntry(
                    dayStart: day,
                    activity: activity,
                    durationSeconds: duration,
                    ayahsCount: ayahsCount,
                    pagesCount: pages.count,
                    passagesCount: 1,
                    first: session.first,
                    last: session.last
                )
            )
        }
        return entries
    }

    private static func isDayActive(logs: [ActivityLogRecord], practice: [PracticeActivityEntry]) -> Bool {
        if !practice.isEmpty {
            return true
        }
        let totalSeconds = logs.reduce(0) { $0 + max(0, $1.durationSeconds) }
        if totalSeconds >= minimumActiveDaySeconds {
            return true
        }
        let totalPages = logs.reduce(0) { $0 + max(0, $1.pagesCount) }
        let totalAyahs = logs.reduce(0) { $0 + max(0, $1.ayahsCount) }
        let hasCheckIn = logs.contains { $0.goalID != nil }
        return totalPages > 0 || totalAyahs > 0 || hasCheckIn
    }

    private static func combinedActiveSchedule(goals: [StudyGoalRecord]) -> WeekdaySchedule {
        let active = goals.filter { !$0.isPaused }
        guard !active.isEmpty else {
            return .all
        }
        let unionMask = active.reduce(0) { $0 | $1.weekdayMask }
        let schedule = WeekdaySchedule(rawValue: unionMask)
        return schedule.isEmpty ? .all : schedule
    }

    private static func evaluateGoal(
        _ goal: StudyGoalRecord,
        logs: [ActivityLogRecord],
        practiceEntries: [PracticeActivityEntry],
        quran: Quran,
        todayStart: Date,
        calendar: Calendar
    ) -> GoalProgressSnapshot {
        let schedule = goal.schedule.isEmpty ? WeekdaySchedule.all : goal.schedule
        let goalStartDay = calendar.startOfDay(for: goal.startDate)
        let isScheduledToday = !goal.isPaused && todayStart >= goalStartDay && schedule.contains(date: todayStart, calendar: calendar)

        let matchingLogs = logs.filter { log in
            let logDay = calendar.startOfDay(for: log.startedOn)
            guard logDay >= goalStartDay else { return false }
            if let linkedID = log.goalID {
                return linkedID == goal.id
            }
            guard log.activity == goal.activity else { return false }
            return logMatchesScope(log, goal: goal)
        }
        let matchingPractice = practiceEntries.filter { entry in
            guard entry.dayStart >= goalStartDay else { return false }
            guard goal.activity == .memorize || goal.activity == .review else { return false }
            // Review goals count review sessions; memorize goals count new/learning sessions.
            // If the goal is unscoped review, any practice session also contributes if activity matches.
            guard entry.activity == goal.activity else { return false }
            return practiceMatchesScope(entry, goal: goal)
        }

        let todayLogs = matchingLogs.filter { calendar.startOfDay(for: $0.startedOn) == todayStart }
        let beforeTodayLogs = matchingLogs.filter { calendar.startOfDay(for: $0.startedOn) < todayStart }
        let todayPractice = matchingPractice.filter { $0.dayStart == todayStart }
        let beforeTodayPractice = matchingPractice.filter { $0.dayStart < todayStart }

        let todayCompleted = completedUnits(for: goal, logs: todayLogs, practice: todayPractice)
        let beforeTodayCompleted = completedUnits(for: goal, logs: beforeTodayLogs, practice: beforeTodayPractice)
        let totalCompleted = beforeTodayCompleted + todayCompleted

        let isTotalTracked = goal.kind == .khatmah || goal.workloadMode == .flexible
        let totalTarget: Int? = isTotalTracked ? max(1, goal.targetAmount) : nil
        let totalRemaining: Int? = totalTarget.map { max(0, $0 - totalCompleted) }

        let remainingDays: Int? = if let deadline = goal.deadline {
            scheduledDayCount(from: todayStart, through: deadline, schedule: schedule, calendar: calendar)
        } else {
            nil
        }

        let todayTarget: Int
        if goal.isPaused || !isScheduledToday {
            todayTarget = 0
        } else if isTotalTracked, let total = totalTarget {
            let remainingBeforeToday = max(0, total - beforeTodayCompleted)
            if remainingBeforeToday == 0 {
                todayTarget = 0
            } else if goal.workloadMode == .flexible, let days = remainingDays {
                if days > 0 {
                    todayTarget = max(1, Int(ceil(Double(remainingBeforeToday) / Double(days))))
                } else {
                    todayTarget = remainingBeforeToday
                }
            } else {
                // Fixed-pace Khatmah (e.g. "20 pages/day until 604 pages done")
                if let deadline = goal.deadline {
                    let plannedTotalDays = max(1, scheduledDayCount(from: goalStartDay, through: deadline, schedule: schedule, calendar: calendar))
                    let fixedDaily = max(1, Int(ceil(Double(total) / Double(plannedTotalDays))))
                    todayTarget = min(remainingBeforeToday, fixedDaily)
                } else {
                    todayTarget = min(remainingBeforeToday, max(1, goal.targetAmount))
                }
            }
        } else {
            todayTarget = max(1, goal.targetAmount)
        }

        let todayRemaining = max(0, todayTarget - todayCompleted)
        let isTodayMet: Bool = if let totalRemaining, totalRemaining == 0 {
            true
        } else if todayTarget > 0 {
            todayCompleted >= todayTarget
        } else {
            false
        }

        // Khatmah page calculations (1...totalPages)
        let totalPages = quran.pages.count
        let clampedStartPage = min(max(1, goal.startPage), totalPages)
        let nextKhatmahPage: Int?
        let todayKhatmahPageRange: ClosedRange<Int>?
        if goal.kind == .khatmah {
            let remaining = totalRemaining ?? 0
            if remaining == 0 {
                nextKhatmahPage = nil
                todayKhatmahPageRange = nil
            } else {
                let rawNext = clampedStartPage + totalCompleted
                let wrappedNext = ((rawNext - 1) % totalPages) + 1
                nextKhatmahPage = wrappedNext
                if todayTarget > 0 {
                    let startOfTodayPage = ((clampedStartPage + beforeTodayCompleted - 1) % totalPages) + 1
                    let endOfTodayPage = min(totalPages, startOfTodayPage + todayTarget - 1)
                    todayKhatmahPageRange = startOfTodayPage ... max(startOfTodayPage, endOfTodayPage)
                } else {
                    todayKhatmahPageRange = nil
                }
            }
        } else {
            nextKhatmahPage = nil
            todayKhatmahPageRange = nil
        }

        // Pace status for Khatmah / deadline goals
        let paceStatus: GoalPaceStatus?
        if goal.isPaused {
            paceStatus = .paused
        } else if let total = totalTarget {
            if totalCompleted >= total {
                paceStatus = .completed
            } else if let deadline = goal.deadline {
                let totalScheduled = max(1, scheduledDayCount(from: goalStartDay, through: deadline, schedule: schedule, calendar: calendar))
                let elapsedEnd = min(todayStart, calendar.startOfDay(for: deadline))
                let elapsedScheduled = scheduledDayCount(from: goalStartDay, through: elapsedEnd, schedule: schedule, calendar: calendar)
                let expectedByNow = Int(floor(Double(total) * Double(elapsedScheduled) / Double(totalScheduled)))
                let delta = totalCompleted - expectedByNow
                if delta > 0 {
                    paceStatus = .ahead(units: delta)
                } else if delta < 0 {
                    paceStatus = .behind(units: -delta)
                } else {
                    paceStatus = .onTrack
                }
            } else {
                paceStatus = .onTrack
            }
        } else {
            paceStatus = nil
        }

        return GoalProgressSnapshot(
            goal: goal,
            isScheduledToday: isScheduledToday,
            todayTarget: todayTarget,
            todayCompleted: todayCompleted,
            todayRemaining: todayRemaining,
            isTodayMet: isTodayMet,
            totalTarget: totalTarget,
            totalCompleted: totalCompleted,
            totalRemaining: totalRemaining,
            remainingScheduledDays: remainingDays,
            nextKhatmahPage: nextKhatmahPage,
            todayKhatmahPageRange: todayKhatmahPageRange,
            paceStatus: paceStatus
        )
    }

    private static func logMatchesScope(_ log: ActivityLogRecord, goal: StudyGoalRecord) -> Bool {
        guard let goalFirst = goal.targetFirst, let goalLast = goal.targetLast else {
            return true
        }
        // Full-Quran Khatmah matches all reading logs.
        if goalFirst == MemorizationVerse(sura: 1, ayah: 1), goalLast == MemorizationVerse(sura: 114, ayah: 6) {
            return true
        }
        guard let logFirst = log.first, let logLast = log.last else {
            return false
        }
        return logFirst <= goalLast && logLast >= goalFirst
    }

    private static func practiceMatchesScope(_ entry: PracticeActivityEntry, goal: StudyGoalRecord) -> Bool {
        guard let goalFirst = goal.targetFirst, let goalLast = goal.targetLast else {
            return true
        }
        return entry.first <= goalLast && entry.last >= goalFirst
    }

    private static func completedUnits(
        for goal: StudyGoalRecord,
        logs: [ActivityLogRecord],
        practice: [PracticeActivityEntry]
    ) -> Int {
        switch goal.unit {
        case .minutes:
            let logSec = logs.reduce(0) { $0 + max(0, $1.durationSeconds) }
            let pracSec = practice.reduce(0) { $0 + $1.durationSeconds }
            return (logSec + pracSec) / 60
        case .pages:
            let logPages = logs.reduce(0) { $0 + max(0, $1.pagesCount) }
            let pracPages = practice.reduce(0) { $0 + $1.pagesCount }
            return logPages + pracPages
        case .ayahs:
            let logAyahs = logs.reduce(0) { $0 + max(0, $1.ayahsCount) }
            let pracAyahs = practice.reduce(0) { $0 + $1.ayahsCount }
            return logAyahs + pracAyahs
        case .passages:
            let manualPassages = logs.filter { $0.goalID == goal.id }.reduce(0) { $0 + max(1, $1.pagesCount) }
            let pracPassages = practice.reduce(0) { $0 + $1.passagesCount }
            return manualPassages + pracPassages
        case .juzs:
            let logPages = logs.reduce(0) { $0 + max(0, $1.pagesCount) }
            let pracPages = practice.reduce(0) { $0 + $1.pagesCount }
            // ~20 pages per Juz (604 / 30 ≈ 20.13)
            return (logPages + pracPages) / 20
        case .completions:
            // Explicit manual check-ins always count as 1 completion each.
            let manualCount = logs.filter { $0.goalID == goal.id }.count
            if manualCount > 0 {
                return manualCount
            }
            // Auto-complete weekly surah (e.g. Friday Al-Kahf) when active reading reaches the end of the surah
            // or covers enough pages (prevents a brief glance from falsely completing Al-Kahf).
            let autoLogs = logs.filter { $0.goalID == nil }
            let pagesCovered = autoLogs.reduce(0) { $0 + max(0, $1.pagesCount) }
            let reachedEnd = goal.targetLast.map { targetEnd in
                autoLogs.contains { ($0.last ?? MemorizationVerse(sura: 0, ayah: 0)) >= targetEnd }
            } ?? false
            if pagesCovered >= minimumAlKahfAutoCompletePages || (reachedEnd && pagesCovered >= 2) {
                return 1
            }
            return 0
        }
    }

    private static func computeGentleStreak(
        activeDays: Set<Date>,
        schedule: WeekdaySchedule,
        todayStart: Date,
        calendar: Calendar
    ) -> GentleStreakSummary {
        let isActiveToday = activeDays.contains(todayStart)

        let activeDaysThisWeek = (0 ..< 7).reduce(0) { count, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return count }
            return count + (activeDays.contains(day) ? 1 : 0)
        }
        let activeDaysLast30Days = (0 ..< 30).reduce(0) { count, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return count }
            return count + (activeDays.contains(day) ? 1 : 0)
        }

        guard let earliestDay = activeDays.min() else {
            return GentleStreakSummary(
                currentStreakDays: 0,
                longestStreakDays: 0,
                graceDayUsedInCurrentStreak: false,
                activeDaysThisWeek: 0,
                activeDaysLast30Days: 0,
                isActiveToday: false
            )
        }

        // Compute current gentle streak walking backward from today (if active) or yesterday.
        // Rest days (unscheduled) are skipped cleanly.
        // At most 1 missed scheduled day in any rolling 7-day window is forgiven as a grace day.
        let walkStart: Date = if isActiveToday {
            todayStart
        } else {
            calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        }

        var currentStreak = 0
        var graceDates: [Date] = []
        var cursor = walkStart
        let maxLookbackDays = 3650
        var lookedBack = 0

        while cursor >= earliestDay, lookedBack < maxLookbackDays {
            lookedBack += 1
            let active = activeDays.contains(cursor)
            let scheduled = schedule.contains(date: cursor, calendar: calendar)
            if active {
                currentStreak += 1
            } else if scheduled {
                // Allow 1 missed scheduled day if no other grace day was used within 7 days of this date.
                let hasRecentGrace = graceDates.contains { used in
                    abs(calendar.dateComponents([.day], from: cursor, to: used).day ?? 99) < 7
                }
                if !hasRecentGrace {
                    graceDates.append(cursor)
                } else {
                    break
                }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        // Trailing grace days with no active day before them do not count as a streak.
        let graceUsedInCurrent = currentStreak > 0 && graceDates.contains { $0 > cursor }

        // Compute longest gentle streak walking forward from earliestDay to todayStart.
        var longest = currentStreak
        var running = 0
        var forwardGraceDates: [Date] = []
        var forwardCursor = earliestDay
        var forwardSteps = 0
        while forwardCursor <= todayStart, forwardSteps < maxLookbackDays {
            forwardSteps += 1
            let active = activeDays.contains(forwardCursor)
            let scheduled = schedule.contains(date: forwardCursor, calendar: calendar)
            if active {
                running += 1
                if running > longest { longest = running }
            } else if scheduled {
                let hasRecentGrace = forwardGraceDates.contains { used in
                    abs(calendar.dateComponents([.day], from: used, to: forwardCursor).day ?? 99) < 7
                }
                if running > 0, !hasRecentGrace {
                    forwardGraceDates.append(forwardCursor)
                } else {
                    running = 0
                    forwardGraceDates.removeAll()
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: forwardCursor) else { break }
            forwardCursor = next
        }

        return GentleStreakSummary(
            currentStreakDays: currentStreak,
            longestStreakDays: longest,
            graceDayUsedInCurrentStreak: graceUsedInCurrent,
            activeDaysThisWeek: activeDaysThisWeek,
            activeDaysLast30Days: activeDaysLast30Days,
            isActiveToday: isActiveToday
        )
    }
}
