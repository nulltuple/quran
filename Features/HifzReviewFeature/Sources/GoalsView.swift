//
//  GoalsView.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Localization
import MemorizationPersistence
import MemorizationService
import NoorUI
import QuranKit
import SwiftUI
import UIx

struct GoalsView: View {
    // MARK: Internal

    @Bindable var viewModel: GoalsViewModel

    var body: some View {
        List {
            todaySummarySection
            activeGoalsSection
            presetsSection
            if !viewModel.plan.last7Days.isEmpty {
                weeklyActivitySection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(l("goals.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.presentNewGoal()
                } label: {
                    NoorSystemImage.plusCircle.image
                }
                .tint(.primary)
                .accessibilityLabel(l("goals.action.add"))
            }
        }
        .task {
            await viewModel.reload()
        }
        .onAppear {
            Task { await viewModel.reload() }
        }
        .sheet(isPresented: $viewModel.isEditorPresented) {
            GoalEditorSheet(
                existing: viewModel.editingGoal,
                onSave: { title, kind, activity, unit, workloadMode, targetAmount, weekdayMask, deadline, startPage in
                    await viewModel.saveGoal(
                        existing: viewModel.editingGoal,
                        title: title,
                        kind: kind,
                        activity: activity,
                        unit: unit,
                        workloadMode: workloadMode,
                        targetAmount: targetAmount,
                        weekdayMask: weekdayMask,
                        deadline: deadline,
                        startPage: startPage
                    )
                }
            )
        }
        .sheet(item: $viewModel.replanTarget) { snapshot in
            KhatmahReplanSheet(
                snapshot: snapshot,
                previewDailyTarget: { deadline, mask, mode, target in
                    viewModel.previewReplanDailyTarget(
                        snapshot: snapshot,
                        deadline: deadline,
                        weekdayMask: mask,
                        workloadMode: mode,
                        targetAmount: target
                    )
                },
                onReplan: { deadline, mask, mode, target in
                    await viewModel.replan(
                        snapshot,
                        deadline: deadline,
                        weekdayMask: mask,
                        workloadMode: mode,
                        targetAmount: target
                    )
                }
            )
        }
        .sheet(item: $viewModel.logProgressTarget) { snapshot in
            LogGoalProgressSheet(snapshot: snapshot) { amount in
                await viewModel.logProgress(for: snapshot, amount: amount)
            }
        }
        .alert(
            l("goals.delete.confirm.title"),
            isPresented: Binding(
                get: { viewModel.removeTarget != nil },
                set: { if !$0 { viewModel.removeTarget = nil } }
            ),
            presenting: viewModel.removeTarget
        ) { goal in
            Button(lAndroid("cancel"), role: .cancel) {}
            Button(l("button.delete"), role: .destructive) {
                Task { await viewModel.confirmRemove(goal) }
            }
        } message: { goal in
            Text(lFormat("goals.delete.confirm.message", GoalsViewModel.displayTitle(for: goal)))
        }
        .alert(
            l("goals.error.title"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(lAndroid("dialog_ok")) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var todaySummarySection: some View {
        Section {
            streakSummaryRow
            activityBreakdownRow
            if viewModel.dueReviewCount > 0 {
                Button {
                    viewModel.startNextReview()
                } label: {
                    HStack(spacing: 12) {
                        NoorSystemImage.reviewQueue.image
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l("hifz_review.home.start_next"))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(lFormat("hifz_review.home.due_count", NumberFormatter.shared.format(viewModel.dueReviewCount)))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NoorSystemImage.disclosure.image
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            Text(l("goals.section.today"))
        }
    }

    private var streakSummaryRow: some View {
        let streak = viewModel.plan.streak
        let streakHeadline: String = if streak.currentStreakDays > 0 {
            lFormat("goals.streak.days", NumberFormatter.shared.format(streak.currentStreakDays))
        } else if streak.activeDaysThisWeek > 0 {
            l("goals.streak.ready_to_resume")
        } else {
            l("goals.streak.start_today")
        }

        let weekLabel = lFormat(
            "goals.streak.week_active",
            NumberFormatter.shared.format(streak.activeDaysThisWeek),
            NumberFormatter.shared.format(7)
        )

        return HStack(alignment: .center, spacing: 12) {
            NoorSystemImage.gentleStreak.image
                .font(.title2)
                .foregroundStyle(streak.currentStreakDays > 0 ? Color.orange : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(streakHeadline)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(weekLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if streak.graceDayUsedInCurrentStreak {
                    Text(l("goals.streak.grace_used"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var activityBreakdownRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                NoorSystemImage.lastPage.image
                    .foregroundStyle(.secondary)
                Text(l("goals.activity.today_time"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(GoalsViewModel.formatMinutes(fromSeconds: viewModel.plan.todayTotalSeconds))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            layout {
                activityMetricBadge(
                    icon: .book,
                    label: l("goals.activity.read"),
                    value: GoalsViewModel.formatMinutes(fromSeconds: viewModel.plan.todayReadingSeconds)
                )
                activityMetricBadge(
                    icon: .audio,
                    label: l("goals.activity.listen"),
                    value: GoalsViewModel.formatMinutes(fromSeconds: viewModel.plan.todayListeningSeconds)
                )
                activityMetricBadge(
                    icon: .hifzPractice,
                    label: l("goals.activity.practice"),
                    value: GoalsViewModel.formatMinutes(fromSeconds: viewModel.plan.todayPracticeSeconds)
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func activityMetricBadge(icon: NoorSystemImage, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                icon.image
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var activeGoalsSection: some View {
        Section {
            if viewModel.plan.goals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l("goals.empty.title"))
                        .font(.headline)
                    Text(l("goals.empty.message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.presentNewGoal()
                    } label: {
                        Label {
                            Text(l("goals.action.create"))
                        } icon: {
                            NoorSystemImage.plusCircle.image
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(viewModel.plan.goals) { snapshot in
                    goalCard(snapshot)
                }
            }
        } header: {
            Text(l("goals.section.active"))
        }
    }

    private func goalCard(_ snapshot: GoalProgressSnapshot) -> some View {
        let goal = snapshot.goal
        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        let actionLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        return VStack(alignment: .leading, spacing: 10) {
            headerLayout {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    GoalsViewModel.activityImage(goal.activity).image
                        .foregroundStyle(goal.isPaused ? Color.secondary : Color.accentColor)
                    Text(GoalsViewModel.displayTitle(for: goal))
                        .font(.headline)
                        .foregroundStyle(goal.isPaused ? .secondary : .primary)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 4)
                }
                statusPill(for: snapshot)
            }

            if snapshot.isScheduledToday, snapshot.todayTarget > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: snapshot.todayFraction)
                        .tint(snapshot.isTodayMet ? .green : .accentColor)
                    HStack {
                        Text(GoalsViewModel.formatProgressRatio(
                            completed: snapshot.todayCompleted,
                            target: snapshot.todayTarget,
                            unit: goal.unit
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        Spacer()
                        if let range = snapshot.todayKhatmahPageRange {
                            Text(lFormat(
                                "goals.khatmah.page_range",
                                NumberFormatter.shared.format(range.lowerBound),
                                NumberFormatter.shared.format(range.upperBound)
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let totalTarget = snapshot.totalTarget {
                let pct = Int((Double(min(snapshot.totalCompleted, totalTarget)) / Double(max(1, totalTarget)) * 100).rounded())
                VStack(alignment: .leading, spacing: 2) {
                    Text(lFormat(
                        "goals.khatmah.overall",
                        NumberFormatter.shared.format(snapshot.totalCompleted),
                        NumberFormatter.shared.format(totalTarget),
                        GoalsViewModel.unitLabel(goal.unit),
                        NumberFormatter.shared.format(pct)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let deadline = goal.deadline {
                        let daysText = snapshot.remainingScheduledDays.map {
                            lFormat("goals.deadline.remaining", GoalsViewModel.formatDate(deadline), NumberFormatter.shared.format($0))
                        } ?? GoalsViewModel.formatDate(deadline)
                        Text(daysText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !snapshot.isScheduledToday, !goal.isPaused {
                Text(l("goals.status.rest_day_detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            actionLayout {
                if !goal.isPaused {
                    Button {
                        viewModel.openGoalAction(snapshot)
                    } label: {
                        Text(openButtonTitle(for: snapshot))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        if goal.unit == .completions {
                            Task { await viewModel.logProgress(for: snapshot, amount: 1) }
                        } else {
                            viewModel.logProgressTarget = snapshot
                        }
                    } label: {
                        Text(goal.unit == .completions ? l("goals.action.mark_done") : l("goals.action.log_progress"))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer(minLength: 0)

                Menu {
                    if goal.kind == .khatmah || goal.workloadMode == .flexible {
                        Button {
                            viewModel.replanTarget = snapshot
                        } label: {
                            Label {
                                Text(l("goals.action.replan"))
                            } icon: {
                                NoorSystemImage.replanGoal.image
                            }
                        }
                    }
                    Button {
                        viewModel.presentEdit(goal)
                    } label: {
                        Label {
                            Text(l("goals.action.edit"))
                        } icon: {
                            NoorSystemImage.edit.image
                        }
                    }
                    Button {
                        Task { await viewModel.togglePaused(goal) }
                    } label: {
                        Label {
                            Text(goal.isPaused ? l("goals.action.resume") : l("goals.action.pause"))
                        } icon: {
                            (goal.isPaused ? NoorSystemImage.play : .pause).image
                        }
                    }
                    Button(role: .destructive) {
                        viewModel.removeTarget = goal
                    } label: {
                        Label {
                            Text(l("button.delete"))
                        } icon: {
                            NoorSystemImage.delete.image
                        }
                    }
                } label: {
                    NoorSystemImage.moreCircle.image
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(l("button.more"))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func openButtonTitle(for snapshot: GoalProgressSnapshot) -> String {
        if snapshot.goal.kind == .khatmah, let page = snapshot.nextKhatmahPage {
            return lFormat("goals.action.open_page", NumberFormatter.shared.format(page))
        }
        switch snapshot.goal.activity {
        case .read: return l("goals.action.open_reader")
        case .listen: return l("goals.action.open_reader")
        case .memorize, .review: return l("goals.action.practice")
        }
    }

    @ViewBuilder
    private func statusPill(for snapshot: GoalProgressSnapshot) -> some View {
        let info: (text: String, color: Color) = if snapshot.goal.isPaused {
            (l("goals.status.paused"), .secondary)
        } else if snapshot.paceStatus == .completed {
            (l("goals.status.completed"), .green)
        } else if snapshot.isScheduledToday, snapshot.isTodayMet {
            (l("goals.status.done_today"), .green)
        } else if !snapshot.isScheduledToday {
            (l("goals.status.rest_day"), .secondary)
        } else if case .ahead(let units) = snapshot.paceStatus {
            (lFormat("goals.pace.ahead", NumberFormatter.shared.format(units)), .green)
        } else if case .behind(let units) = snapshot.paceStatus {
            (lFormat("goals.pace.behind", NumberFormatter.shared.format(units)), .orange)
        } else {
            (l("goals.pace.on_track"), .accentColor)
        }

        Text(info.text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(info.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(info.color.opacity(0.14), in: Capsule())
    }

    private var presetsSection: some View {
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        return Section {
            ForEach(StudyGoalPreset.allCases) { preset in
                let alreadyActive = viewModel.hasActivePreset(preset)
                rowLayout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GoalsViewModel.presetTitle(preset))
                            .font(.body.weight(.medium))
                        Text(GoalsViewModel.presetSubtitle(preset))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer()
                    }
                    if alreadyActive {
                        Label {
                            Text(l("goals.preset.added"))
                        } icon: {
                            NoorSystemImage.goalComplete.image
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                    } else {
                        Button(l("goals.preset.add")) {
                            Task { await viewModel.addPreset(preset) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(l("goals.section.presets"))
        }
    }

    private var weeklyActivitySection: some View {
        let maxSeconds = max(60, viewModel.plan.last7Days.map(\.totalSeconds).max() ?? 60)
        return Section {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(viewModel.plan.last7Days) { bucket in
                    let heightFraction = max(0.08, Double(bucket.totalSeconds) / Double(maxSeconds))
                    let dayName = GoalsViewModel.weekdayVeryShortName(for: bucket.dayStart)
                    let minsText = GoalsViewModel.formatMinutes(fromSeconds: bucket.totalSeconds)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(bucket.isActive ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(height: max(8, 72 * heightFraction))
                        Text(dayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(GoalsViewModel.formatDate(bucket.dayStart)): \(minsText)")
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text(l("goals.section.week_activity"))
        } footer: {
            Text(l("goals.activity.footer"))
        }
    }
}

// MARK: - Goal Editor Sheet

private struct GoalEditorSheet: View {
    // MARK: Lifecycle

    init(
        existing: StudyGoalRecord?,
        onSave: @escaping (String, GoalKind, GoalActivity, GoalUnit, GoalWorkloadMode, Int, Int, Date?, Int) async -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        _title = State(initialValue: existing?.title ?? "")
        _kind = State(initialValue: existing?.kind ?? .habit)
        _activity = State(initialValue: existing?.activity ?? .read)
        _unit = State(initialValue: existing?.unit ?? .minutes)
        _workloadMode = State(initialValue: existing?.workloadMode ?? .fixed)
        _targetAmount = State(initialValue: existing?.targetAmount ?? 15)
        _schedule = State(initialValue: existing?.schedule ?? .all)
        _hasDeadline = State(initialValue: existing?.deadline != nil)
        _deadline = State(initialValue: existing?.deadline ?? Calendar.current.date(byAdding: .day, value: 29, to: Date()) ?? Date())
        _startPage = State(initialValue: existing?.startPage ?? 1)
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(l("goals.editor.title_placeholder"), text: $title)
                    Picker(l("goals.editor.kind"), selection: $kind) {
                        Text(l("goals.kind.habit")).tag(GoalKind.habit)
                        Text(l("goals.kind.khatmah")).tag(GoalKind.khatmah)
                    }
                    .onChange(of: kind) { _, newKind in
                        if newKind == .khatmah {
                            activity = .read
                            unit = .pages
                            workloadMode = .flexible
                            targetAmount = Quran.hafsMadani1405.pages.count
                            hasDeadline = true
                        }
                    }

                    if kind != .khatmah {
                        Picker(l("goals.editor.activity"), selection: $activity) {
                            ForEach(GoalActivity.allCases, id: \.self) { item in
                                Text(GoalsViewModel.activityLabel(item)).tag(item)
                            }
                        }
                    }
                }

                Section {
                    Picker(l("goals.editor.unit"), selection: $unit) {
                        ForEach(availableUnits, id: \.self) { item in
                            Text(GoalsViewModel.unitLabel(item)).tag(item)
                        }
                    }

                    Picker(l("goals.editor.workload"), selection: $workloadMode) {
                        Text(l("goals.workload.fixed")).tag(GoalWorkloadMode.fixed)
                        Text(l("goals.workload.flexible")).tag(GoalWorkloadMode.flexible)
                    }

                    Stepper(
                        value: $targetAmount,
                        in: 1 ... maxTarget,
                        step: targetStep
                    ) {
                        let labelKey = (kind == .khatmah || workloadMode == .flexible)
                            ? "goals.editor.total_target"
                            : "goals.editor.daily_target"
                        Text(lFormat(
                            labelKey,
                            NumberFormatter.shared.format(targetAmount),
                            GoalsViewModel.unitLabel(unit)
                        ))
                    }

                    if kind == .khatmah {
                        Stepper(value: $startPage, in: 1 ... Quran.hafsMadani1405.pages.count) {
                            Text(lFormat("goals.editor.start_page", NumberFormatter.shared.format(startPage)))
                        }
                    }
                } footer: {
                    Text(workloadMode == .flexible
                        ? l("goals.workload.flexible.help")
                        : l("goals.workload.fixed.help"))
                }

                Section(l("goals.editor.schedule")) {
                    WeekdayPickerRow(schedule: $schedule)
                    Toggle(l("goals.editor.has_deadline"), isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker(
                            l("goals.editor.deadline"),
                            selection: $deadline,
                            in: Calendar.current.startOfDay(for: Date())...,
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle(existing == nil ? l("goals.editor.new_title") : l("goals.editor.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        NoorSystemImage.cancel.image
                    }
                    .tint(.primary)
                    .accessibilityLabel(l("button.close"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l("hifz_practice.save_mistakes")) {
                        Task {
                            await onSave(
                                title,
                                kind,
                                activity,
                                unit,
                                workloadMode,
                                targetAmount,
                                schedule.rawValue,
                                hasDeadline ? deadline : nil,
                                startPage
                            )
                            dismiss()
                        }
                    }
                    .disabled(schedule.isEmpty)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private let existing: StudyGoalRecord?
    private let onSave: (String, GoalKind, GoalActivity, GoalUnit, GoalWorkloadMode, Int, Int, Date?, Int) async -> Void

    @State private var title: String
    @State private var kind: GoalKind
    @State private var activity: GoalActivity
    @State private var unit: GoalUnit
    @State private var workloadMode: GoalWorkloadMode
    @State private var targetAmount: Int
    @State private var schedule: WeekdaySchedule
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var startPage: Int

    private var availableUnits: [GoalUnit] {
        if kind == .khatmah {
            return [.pages, .juzs]
        }
        switch activity {
        case .read: return [.minutes, .pages, .ayahs, .juzs]
        case .listen: return [.minutes, .ayahs, .pages]
        case .memorize, .review: return [.passages, .ayahs, .minutes, .pages]
        }
    }

    private var maxTarget: Int {
        switch unit {
        case .pages: 604
        case .ayahs: 6236
        case .juzs: 30
        case .minutes: 600
        case .passages: 100
        case .completions: 7
        }
    }

    private var targetStep: Int {
        switch unit {
        case .minutes: 5
        case .ayahs: 5
        default: 1
        }
    }
}

// MARK: - Khatmah Replan Sheet

private struct KhatmahReplanSheet: View {
    // MARK: Lifecycle

    init(
        snapshot: GoalProgressSnapshot,
        previewDailyTarget: @escaping (Date?, Int, GoalWorkloadMode, Int) -> Int,
        onReplan: @escaping (Date?, Int, GoalWorkloadMode, Int) async -> Void
    ) {
        self.snapshot = snapshot
        self.previewDailyTarget = previewDailyTarget
        self.onReplan = onReplan
        _workloadMode = State(initialValue: snapshot.goal.workloadMode)
        _schedule = State(initialValue: snapshot.goal.schedule.isEmpty ? .all : snapshot.goal.schedule)
        _hasDeadline = State(initialValue: snapshot.goal.deadline != nil)
        let defaultDeadline = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        _deadline = State(initialValue: max(Calendar.current.startOfDay(for: Date()), snapshot.goal.deadline ?? defaultDeadline))
        _targetAmount = State(initialValue: snapshot.goal.targetAmount)
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(lFormat(
                        "goals.replan.history_preserved",
                        NumberFormatter.shared.format(snapshot.totalCompleted),
                        GoalsViewModel.unitLabel(snapshot.goal.unit)
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section(l("goals.editor.schedule")) {
                    Picker(l("goals.editor.workload"), selection: $workloadMode) {
                        Text(l("goals.workload.flexible")).tag(GoalWorkloadMode.flexible)
                        Text(l("goals.workload.fixed")).tag(GoalWorkloadMode.fixed)
                    }

                    WeekdayPickerRow(schedule: $schedule)

                    Toggle(l("goals.editor.has_deadline"), isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker(
                            l("goals.editor.deadline"),
                            selection: $deadline,
                            in: Calendar.current.startOfDay(for: Date())...,
                            displayedComponents: .date
                        )
                    }
                }

                Section {
                    let daily = previewDailyTarget(hasDeadline ? deadline : nil, schedule.rawValue, workloadMode, targetAmount)
                    HStack {
                        Text(l("goals.replan.new_daily_pace"))
                        Spacer()
                        Text(lFormat(
                            "goals.replan.daily_amount",
                            NumberFormatter.shared.format(daily),
                            GoalsViewModel.unitLabel(snapshot.goal.unit)
                        ))
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                    }
                }
            }
            .navigationTitle(l("goals.replan.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        NoorSystemImage.cancel.image
                    }
                    .tint(.primary)
                    .accessibilityLabel(l("button.close"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l("hifz_practice.save_mistakes")) {
                        Task {
                            await onReplan(hasDeadline ? deadline : nil, schedule.rawValue, workloadMode, targetAmount)
                            dismiss()
                        }
                    }
                    .disabled(schedule.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private let snapshot: GoalProgressSnapshot
    private let previewDailyTarget: (Date?, Int, GoalWorkloadMode, Int) -> Int
    private let onReplan: (Date?, Int, GoalWorkloadMode, Int) async -> Void

    @State private var workloadMode: GoalWorkloadMode
    @State private var schedule: WeekdaySchedule
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var targetAmount: Int
}

// MARK: - Log Progress Sheet

private struct LogGoalProgressSheet: View {
    // MARK: Lifecycle

    init(snapshot: GoalProgressSnapshot, onLog: @escaping (Int) async -> Void) {
        self.snapshot = snapshot
        self.onLog = onLog
        let initial = max(1, snapshot.todayRemaining > 0 ? snapshot.todayRemaining : snapshot.todayTarget)
        _amount = State(initialValue: initial)
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $amount, in: 1 ... 604) {
                        Text(lFormat(
                            "goals.log.amount_row",
                            NumberFormatter.shared.format(amount),
                            GoalsViewModel.unitLabel(snapshot.goal.unit)
                        ))
                    }
                } header: {
                    Text(GoalsViewModel.displayTitle(for: snapshot.goal))
                } footer: {
                    Text(l("goals.log.footer"))
                }
            }
            .navigationTitle(l("goals.action.log_progress"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        NoorSystemImage.cancel.image
                    }
                    .tint(.primary)
                    .accessibilityLabel(l("button.close"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l("hifz_practice.save_mistakes")) {
                        Task {
                            await onLog(amount)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private let snapshot: GoalProgressSnapshot
    private let onLog: (Int) async -> Void
    @State private var amount: Int
}

// MARK: - Weekday Picker Row

private struct WeekdayPickerRow: View {
    @Binding var schedule: WeekdaySchedule

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WeekdaySchedule.orderedDays, id: \.rawValue) { day in
                let isSelected = schedule.contains(day)
                let label = GoalsViewModel.weekdayShortName(day)
                Button {
                    if isSelected {
                        if schedule.count > 1 {
                            schedule.remove(day)
                        }
                    } else {
                        schedule.insert(day)
                    }
                } label: {
                    Text(String(label.prefix(2)))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
