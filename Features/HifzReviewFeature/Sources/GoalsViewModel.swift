//
//  GoalsViewModel.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import Localization
import MemorizationPersistence
import MemorizationService
import NoorUI
import Observation
import QuranKit
import ReadingService
import VLogging

@MainActor
@Observable
public final class GoalsViewModel {
    // MARK: Lifecycle

    public init(
        service: MemorizationService,
        openAyah: @escaping (AyahNumber) -> Void,
        openMemorization: @escaping () -> Void,
        practicePassage: @escaping (Passage) -> Void,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.openAyah = openAyah
        self.openMemorization = openMemorization
        self.practicePassage = practicePassage
        self.calendar = calendar
        self.now = now
        plan = .empty(on: now())
    }

    // MARK: Public

    public private(set) var plan: TodayPlanSummary
    public private(set) var dueReviewCount = 0
    public private(set) var topDuePassage: Passage?
    public private(set) var isLoading = false
    public var errorMessage: String?

    public var isEditorPresented = false
    public var editingGoal: StudyGoalRecord?
    public var replanTarget: GoalProgressSnapshot?
    public var logProgressTarget: GoalProgressSnapshot?
    public var removeTarget: StudyGoalRecord?

    public func reload() async {
        isLoading = true
        defer { isLoading = false }
        let service = service
        let calendar = calendar
        let budgets = ReviewBudgetStore().budgets
        do {
            async let loadedPlan = service.todayPlan(calendar: calendar)
            async let loadedQueue = service.reviewQueue(budgets: budgets)
            let (todayPlan, queue) = try await (loadedPlan, loadedQueue)
            plan = todayPlan
            dueReviewCount = queue.totalDueCount
            topDuePassage = queue.budgetedDueItems.first?.passage ?? queue.dueItems.first?.passage
            errorMessage = nil
        } catch {
            logger.error("Goals: failed to load today plan: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    public func addPreset(_ preset: StudyGoalPreset) async {
        do {
            _ = try await service.createPresetGoal(preset, title: Self.presetTitle(preset), calendar: calendar)
            await reload()
        } catch {
            logger.error("Goals: failed to create preset \(preset.rawValue): \(error)")
            errorMessage = error.localizedDescription
        }
    }

    public func presentNewGoal() {
        editingGoal = nil
        isEditorPresented = true
    }

    public func presentEdit(_ goal: StudyGoalRecord) {
        editingGoal = goal
        isEditorPresented = true
    }

    public func saveGoal(
        existing: StudyGoalRecord?,
        title: String,
        kind: GoalKind,
        activity: GoalActivity,
        unit: GoalUnit,
        workloadMode: GoalWorkloadMode,
        targetAmount: Int,
        weekdayMask: Int,
        deadline: Date?,
        startPage: Int
    ) async {
        let timestamp = now()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? Self.defaultTitle(kind: kind, activity: activity) : trimmedTitle
        let safeMask = weekdayMask == 0 ? WeekdaySchedule.all.rawValue : weekdayMask
        let safeTarget = max(1, targetAmount)
        let safeStartPage = min(max(1, startPage), Quran.hafsMadani1405.pages.count)

        let record: StudyGoalRecord
        if var existing {
            existing.title = resolvedTitle
            existing.kind = kind
            existing.activity = activity
            existing.unit = unit
            existing.workloadMode = workloadMode
            existing.targetAmount = safeTarget
            existing.weekdayMask = safeMask
            existing.deadline = deadline
            existing.startPage = safeStartPage
            existing.modifiedOn = timestamp
            record = existing
        } else {
            let first: MemorizationVerse? = kind == .khatmah ? MemorizationVerse(sura: 1, ayah: 1) : nil
            let last: MemorizationVerse? = kind == .khatmah ? MemorizationVerse(sura: 114, ayah: 6) : nil
            record = StudyGoalRecord(
                id: UUID(),
                title: resolvedTitle,
                kind: kind,
                activity: activity,
                unit: unit,
                workloadMode: workloadMode,
                targetAmount: safeTarget,
                weekdayMask: safeMask,
                startDate: calendar.startOfDay(for: timestamp),
                deadline: deadline,
                startPage: safeStartPage,
                targetFirst: first,
                targetLast: last,
                presetID: nil,
                isPaused: false,
                createdOn: timestamp,
                modifiedOn: timestamp
            )
        }

        do {
            try await service.saveGoal(record)
            isEditorPresented = false
            editingGoal = nil
            await reload()
        } catch {
            logger.error("Goals: failed to save goal: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    public func replan(
        _ snapshot: GoalProgressSnapshot,
        deadline: Date?,
        weekdayMask: Int,
        workloadMode: GoalWorkloadMode,
        targetAmount: Int
    ) async {
        let safeMask = weekdayMask == 0 ? WeekdaySchedule.all.rawValue : weekdayMask
        do {
            _ = try await service.replanGoal(
                id: snapshot.goal.id,
                deadline: deadline,
                weekdayMask: safeMask,
                workloadMode: workloadMode,
                targetAmount: max(1, targetAmount)
            )
            replanTarget = nil
            await reload()
        } catch {
            logger.error("Goals: failed to replan goal: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    public func logProgress(for snapshot: GoalProgressSnapshot, amount: Int) async {
        do {
            _ = try await service.logManualProgress(for: snapshot.goal, amount: max(1, amount))
            logProgressTarget = nil
            await reload()
        } catch {
            logger.error("Goals: failed to log progress: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    public func togglePaused(_ goal: StudyGoalRecord) async {
        do {
            try await service.setGoalPaused(id: goal.id, isPaused: !goal.isPaused)
            await reload()
        } catch {
            logger.error("Goals: failed to toggle pause: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    public func confirmRemove(_ goal: StudyGoalRecord) async {
        do {
            try await service.removeGoal(id: goal.id)
            removeTarget = nil
            await reload()
        } catch {
            logger.error("Goals: failed to remove goal: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    public func openGoalAction(_ snapshot: GoalProgressSnapshot) {
        let activeQuran = ReadingPreferences.shared.reading.quran
        if let ayah = snapshot.navigationTarget(in: activeQuran) {
            openAyah(ayah)
            return
        }
        switch snapshot.goal.activity {
        case .memorize, .review:
            if let topDuePassage {
                practicePassage(topDuePassage)
            } else {
                openMemorization()
            }
        case .read, .listen:
            openAyah(activeQuran.firstVerse)
        }
    }

    public func openReview() {
        openMemorization()
    }

    public func startNextReview() {
        guard let topDuePassage else {
            openMemorization()
            return
        }
        practicePassage(topDuePassage)
    }

    public func hasActivePreset(_ preset: StudyGoalPreset) -> Bool {
        plan.goals.contains { $0.goal.presetID == preset.rawValue && $0.goal.removedOn == nil }
    }

    // MARK: - Preview / Formatting Helpers

    public func previewReplanDailyTarget(
        snapshot: GoalProgressSnapshot,
        deadline: Date?,
        weekdayMask: Int,
        workloadMode: GoalWorkloadMode,
        targetAmount: Int
    ) -> Int {
        let total = max(1, targetAmount)
        let remaining = max(0, total - snapshot.totalCompleted)
        guard remaining > 0 else { return 0 }
        let schedule = WeekdaySchedule(rawValue: weekdayMask == 0 ? WeekdaySchedule.all.rawValue : weekdayMask)
        let todayStart = calendar.startOfDay(for: now())
        if workloadMode == .flexible, let deadline {
            let days = StudyGoalPlanner.scheduledDayCount(from: todayStart, through: deadline, schedule: schedule, calendar: calendar)
            if days > 0 {
                return max(1, Int(ceil(Double(remaining) / Double(days))))
            }
            return remaining
        }
        if let deadline {
            let days = max(1, StudyGoalPlanner.scheduledDayCount(from: todayStart, through: deadline, schedule: schedule, calendar: calendar))
            return max(1, Int(ceil(Double(remaining) / Double(days))))
        }
        return remaining
    }

    public static func presetTitle(_ preset: StudyGoalPreset) -> String {
        switch preset {
        case .fridayAlKahf: l("goals.preset.friday_alkahf.title")
        case .ramadanKhatmah: l("goals.preset.ramadan_khatmah.title")
        case .sevenPartWeek: l("goals.preset.seven_part_week.title")
        }
    }

    public static func presetSubtitle(_ preset: StudyGoalPreset) -> String {
        switch preset {
        case .fridayAlKahf: l("goals.preset.friday_alkahf.subtitle")
        case .ramadanKhatmah: l("goals.preset.ramadan_khatmah.subtitle")
        case .sevenPartWeek: l("goals.preset.seven_part_week.subtitle")
        }
    }

    public static func defaultTitle(kind: GoalKind, activity: GoalActivity) -> String {
        if kind == .khatmah {
            return l("goals.kind.khatmah")
        }
        return activityLabel(activity)
    }

    public static func activityLabel(_ activity: GoalActivity) -> String {
        switch activity {
        case .read: l("goals.activity.read")
        case .listen: l("goals.activity.listen")
        case .memorize: l("goals.activity.memorize")
        case .review: l("goals.activity.review")
        }
    }

    public static func activityImage(_ activity: GoalActivity) -> NoorSystemImage {
        switch activity {
        case .read: .book
        case .listen: .audio
        case .memorize: .hifzPractice
        case .review: .reviewQueue
        }
    }

    public static func unitLabel(_ unit: GoalUnit) -> String {
        switch unit {
        case .minutes: l("goals.unit.minutes")
        case .pages: l("goals.unit.pages")
        case .ayahs: l("goals.unit.ayahs")
        case .passages: l("goals.unit.passages")
        case .juzs: l("goals.unit.juzs")
        case .completions: l("goals.unit.completions")
        }
    }

    public static func formatMinutes(fromSeconds seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        if seconds > 0, mins == 0 {
            return l("goals.time.under_minute")
        }
        return lFormat("goals.time.minutes", NumberFormatter.shared.format(mins))
    }

    public static func formatProgressRatio(completed: Int, target: Int, unit: GoalUnit) -> String {
        let doneStr = NumberFormatter.shared.format(completed)
        let targetStr = NumberFormatter.shared.format(target)
        return lFormat("goals.progress.ratio", doneStr, targetStr, unitLabel(unit))
    }

    public static func displayTitle(for goal: StudyGoalRecord) -> String {
        if let presetID = goal.presetID, let preset = StudyGoalPreset(rawValue: presetID), goal.title.isEmpty {
            return presetTitle(preset)
        }
        return goal.title.isEmpty ? defaultTitle(kind: goal.kind, activity: goal.activity) : goal.title
    }

    public static func formatDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    public static func weekdayShortName(_ day: WeekdaySchedule, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols
        guard let index = WeekdaySchedule.orderedDays.firstIndex(of: day), symbols.indices.contains(index) else {
            return ""
        }
        return symbols[index]
    }

    public static func weekdayVeryShortName(for date: Date, calendar: Calendar = .current) -> String {
        let weekday = calendar.component(.weekday, from: date)
        let symbols = calendar.veryShortWeekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    // MARK: Private

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .fixedCurrentLocaleNumbers
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private let service: MemorizationService
    private let openAyah: (AyahNumber) -> Void
    private let openMemorization: () -> Void
    private let practicePassage: (Passage) -> Void
    private let calendar: Calendar
    private let now: () -> Date
}
