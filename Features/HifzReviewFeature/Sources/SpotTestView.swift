//
//  SpotTestView.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Localization
import MemorizationPersistence
import MemorizationService
import NoorFont
import NoorUI
import QuranKit
import QuranLocalization
import SwiftUI
import UIx

struct SpotTestView: View {
    // MARK: Internal

    @Bindable var viewModel: SpotTestViewModel
    let showCloseButton: Bool

    var body: some View {
        Group {
            switch viewModel.screenPhase {
            case .setup:
                SpotTestSetupView(viewModel: viewModel)
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .testing:
                SpotTestSessionView(viewModel: viewModel)
            case .results(let report):
                SpotTestResultsView(viewModel: viewModel, report: report)
            }
        }
        .navigationTitle(l("hifz_test.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        NoorSystemImage.cancel.image
                    }
                    .tint(.primary)
                    .accessibilityLabel(l("button.close"))
                }
            }
            if viewModel.screenPhase == .testing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(l("hifz_test.action.end")) {
                        Task { await viewModel.endTestEarly() }
                    }
                    .tint(.primary)
                }
            }
        }
        .task {
            if viewModel.screenPhase == .setup {
                await viewModel.refreshPools()
            }
        }
        .sheet(isPresented: $viewModel.isCustomRangePickerPresented) {
            SpotTestCustomRangeSheet(viewModel: viewModel)
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}

// MARK: - Setup View

private struct SpotTestSetupView: View {
    @Bindable var viewModel: SpotTestViewModel

    var body: some View {
        Form {
            Section(header: Text(l("hifz_test.section.presets"))) {
                ForEach(SpotTestPreset.allCases, id: \.self) { preset in
                    presetRow(preset)
                }
            }

            Section(header: Text(l("hifz_test.section.source"))) {
                sourceRow(
                    title: l("hifz_test.source.memorized"),
                    count: viewModel.memorizedVerseCount,
                    isSelected: viewModel.sourceKind == .memorized
                ) {
                    viewModel.selectSource(.memorized)
                }

                Button {
                    viewModel.selectSource(.custom)
                    viewModel.isCustomRangePickerPresented = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l("hifz_test.source.custom"))
                                .foregroundStyle(.primary)
                            if viewModel.customRanges.isEmpty {
                                Text(l("hifz_test.source.custom.empty"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(lFormat("hifz_review.declare.verse_count", NumberFormatter.shared.format(viewModel.customRanges.verseCount)))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if viewModel.sourceKind == .custom {
                            NoorSystemImage.checkmark.image
                                .foregroundStyle(Color.accentColor)
                        }
                        NoorSystemImage.disclosure.image
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section(header: Text(l("hifz_test.section.format"))) {
                Picker(l("hifz_test.length.unit"), selection: $viewModel.lengthUnit) {
                    Text(l("hifz_test.length.ayahs")).tag(SpotTestViewModel.LengthUnit.ayahs)
                    Text(l("hifz_test.length.lines")).tag(SpotTestViewModel.LengthUnit.lines)
                }
                .pickerStyle(.segmented)

                if viewModel.lengthUnit == .ayahs {
                    Stepper(value: $viewModel.ayahCount, in: SpotTestQuestionLength.ayahBounds) {
                        HStack {
                            Text(l("hifz_test.length.label"))
                            Spacer()
                            Text(lFormat("hifz_test.length.ayahs_value", NumberFormatter.shared.format(viewModel.ayahCount)))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Stepper(value: $viewModel.lineCount, in: SpotTestQuestionLength.lineBounds) {
                        HStack {
                            Text(l("hifz_test.length.label"))
                            Spacer()
                            Text(lFormat("hifz_test.length.lines_value", NumberFormatter.shared.format(viewModel.lineCount)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Picker(l("hifz_test.limit.mode"), selection: $viewModel.limitMode) {
                    Text(l("hifz_test.limit.questions")).tag(SpotTestViewModel.LimitMode.count)
                    Text(l("hifz_test.limit.timer")).tag(SpotTestViewModel.LimitMode.timer)
                }
                .pickerStyle(.segmented)

                if viewModel.limitMode == .count {
                    Stepper(value: $viewModel.questionCount, in: SpotTestLimit.countBounds) {
                        HStack {
                            Text(l("hifz_test.limit.questions"))
                            Spacer()
                            Text(NumberFormatter.shared.format(viewModel.questionCount))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Stepper(value: $viewModel.timerMinutes, in: 1 ... 60) {
                        HStack {
                            Text(l("hifz_test.limit.timer"))
                            Spacer()
                            Text(lFormat("hifz_test.limit.minutes_value", NumberFormatter.shared.format(viewModel.timerMinutes)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Picker(l("hifz_test.cue.title"), selection: $viewModel.startCue) {
                    Text(l("hifz_test.cue.first_word")).tag(SpotTestStartCue.firstWord)
                    Text(l("hifz_test.cue.first_two_words")).tag(SpotTestStartCue.firstTwoWords)
                    Text(l("hifz_test.cue.first_ayah")).tag(SpotTestStartCue.firstAyah)
                    if !viewModel.hideLocation {
                        Text(l("hifz_test.cue.reference_only")).tag(SpotTestStartCue.referenceOnly)
                    }
                }
            }

            Section(header: Text(l("hifz_test.section.options"))) {
                Toggle(isOn: $viewModel.hideLocation) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l("hifz_test.option.hide_location"))
                        Text(l("hifz_test.option.hide_location.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.hideLocation) { _, isHidden in
                    if isHidden, viewModel.startCue == .referenceOnly {
                        viewModel.startCue = .firstWord
                    }
                }

                Toggle(isOn: $viewModel.isTemporary) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l("hifz_test.option.temporary"))
                        Text(l("hifz_test.option.temporary.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if viewModel.availableVerseCount == 0, !viewModel.isRefreshingPools {
                    Text(l("hifz_test.empty_pool"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.startTest() }
                } label: {
                    HStack {
                        Spacer()
                        Text(l("hifz_test.action.start"))
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStart)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } footer: {
                if viewModel.availableVerseCount > 0 {
                    Text(lFormat("hifz_test.available_verses", NumberFormatter.shared.format(viewModel.availableVerseCount)))
                }
            }
        }
    }

    private func presetRow(_ preset: SpotTestPreset) -> some View {
        let count = viewModel.presetVerseCounts[preset] ?? 0
        let isSelected = viewModel.sourceKind == .preset(preset)
        return Button {
            viewModel.selectSource(.preset(preset))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.presetTitle(preset))
                        .foregroundStyle(.primary)
                        .fontWeight(isSelected ? .semibold : .regular)
                    Text(Self.presetSubtitle(preset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(lFormat("hifz_review.declare.verse_count", NumberFormatter.shared.format(count)))
                    .font(.footnote)
                    .foregroundStyle(count > 0 ? Color.secondary : Color.secondary.opacity(0.6))
                if isSelected {
                    NoorSystemImage.checkmark.image
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sourceRow(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .fontWeight(isSelected ? .semibold : .regular)
                    Text(lFormat("hifz_review.declare.verse_count", NumberFormatter.shared.format(count)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    NoorSystemImage.checkmark.image
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static func presetTitle(_ preset: SpotTestPreset) -> String {
        switch preset {
        case .warmUp: l("hifz_test.preset.warm_up")
        case .weakest: l("hifz_test.preset.weakest")
        case .due: l("hifz_test.preset.due")
        case .recent: l("hifz_test.preset.recent")
        case .old: l("hifz_test.preset.old")
        }
    }

    private static func presetSubtitle(_ preset: SpotTestPreset) -> String {
        switch preset {
        case .warmUp: l("hifz_test.preset.warm_up.subtitle")
        case .weakest: l("hifz_test.preset.weakest.subtitle")
        case .due: l("hifz_test.preset.due.subtitle")
        case .recent: l("hifz_test.preset.recent.subtitle")
        case .old: l("hifz_test.preset.old.subtitle")
        }
    }
}

// MARK: - Active Session View

private struct SpotTestSessionView: View {
    @Bindable var viewModel: SpotTestViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let quranFontSize: CGFloat = 24
    private static let wordChipFontSize: CGFloat = 22

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerStrip

                if let question = viewModel.currentQuestion {
                    questionCard(question)
                    actionPanel(question)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var headerStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if viewModel.isTimedTest {
                    Text(lFormat("hifz_test.progress.question_only", NumberFormatter.shared.format(viewModel.currentIndex + 1)))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Label {
                        Text(Self.formattedTimer(viewModel.remainingSeconds))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    } icon: {
                        NoorSystemImage.spotTestTimer.image
                    }
                    .font(.subheadline)
                    .foregroundStyle(viewModel.remainingSeconds <= 30 ? .red : .primary)
                } else {
                    Text(
                        lFormat(
                            "hifz_test.progress.count",
                            NumberFormatter.shared.format(viewModel.currentIndex + 1),
                            NumberFormatter.shared.format(viewModel.questions.count)
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                }
            }

            if viewModel.activeConfiguration.isTemporary {
                Text(l("hifz_test.banner.temporary"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
            }
        }
    }

    private func questionCard(_ question: SpotTestQuestion) -> some View {
        let shouldHideLocation = viewModel.activeConfiguration.hideLocation && viewModel.questionPhase == .reciting
        let range = question.passage.first ... question.passage.last

        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))

        return VStack(alignment: .leading, spacing: 14) {
            headerLayout {
                if shouldHideLocation {
                    Label {
                        Text(l("hifz_test.location_hidden"))
                    } icon: {
                        NoorSystemImage.hideLocation.image
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                } else {
                    let ref: MultipartText = "\(ayahRange: range)"
                    ref.view(ofSize: .body, allowsWrapping: true)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }
                if let lines = question.targetLineCount {
                    Text(lFormat("hifz_test.length.lines_value", NumberFormatter.shared.format(lines)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(lFormat("hifz_test.length.ayahs_value", NumberFormatter.shared.format(question.verses.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            switch viewModel.questionPhase {
            case .reciting:
                recitingPromptContent
            case .grading:
                revealedVersesContent(question)
            case .markingMistakes:
                mistakePickerContent(question)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var recitingPromptContent: some View {
        let lines = viewModel.visiblePromptLines
        if lines.isEmpty {
            Text(l("hifz_test.prompt.recite_from_memory"))
                .font(.body)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .trailing, spacing: 10) {
                ForEach(lines, id: \.verse) { entry in
                    let joined = entry.words.map(\.text).joined(separator: " ") + (entry.hasMoreHidden ? " …" : "")
                    Text(joined)
                        .font(.custom(FontName.uthmanicHafs, size: Self.quranFontSize, relativeTo: .title2))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }

        if let hint = viewModel.hintLetter {
            HStack(spacing: 8) {
                Text(l("hifz_test.hint.next_letter"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(hint)
                    .font(.custom(FontName.uthmanicHafs, size: Self.quranFontSize, relativeTo: .title2))
                    .foregroundStyle(Color.accentColor)
            }
        }

        if viewModel.currentQuestionHints > 0 {
            Text(lFormat("hifz_test.hints_used", NumberFormatter.shared.format(viewModel.currentQuestionHints)))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func revealedVersesContent(_ question: SpotTestQuestion) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            ForEach(question.verses, id: \.self) { verse in
                let units = viewModel.loadedWords[verse] ?? []
                let text = units.map(\.text).joined(separator: " ")
                VStack(alignment: .trailing, spacing: 4) {
                    Text(text)
                        .font(.custom(FontName.uthmanicHafs, size: Self.quranFontSize, relativeTo: .title2))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(verse.localizedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func mistakePickerContent(_ question: SpotTestQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l("hifz_test.mistakes.instructions"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(question.verses, id: \.self) { verse in
                let isForgot = viewModel.forgotVerses.contains(verse)
                let marked = viewModel.markedMistakeWords[verse] ?? []
                let units = viewModel.loadedWords[verse] ?? []

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(verse.localizedName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            viewModel.toggleForgotVerse(verse)
                        } label: {
                            Text(l("hifz_practice.forgot"))
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(isForgot ? .red : .secondary)
                    }

                    FlowWordChips(units: units, marked: marked, isVerseForgot: isForgot) { unit in
                        viewModel.toggleMistakenWord(verse: verse, wordNumbers: unit.wordNumbers)
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
            }
        }
    }

    @ViewBuilder
    private func actionPanel(_ question: SpotTestQuestion) -> some View {
        switch viewModel.questionPhase {
        case .reciting:
            VStack(spacing: 10) {
                let assistLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))

                assistLayout {
                    Button {
                        viewModel.showFirstLetterHint()
                    } label: {
                        Label {
                            Text(l("hifz_practice.hint"))
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .minimumScaleFactor(0.85)
                        } icon: {
                            NoorSystemImage.firstLetterHint.image
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasHiddenWord)

                    Button {
                        viewModel.revealNextWord()
                    } label: {
                        Label {
                            Text(l("hifz_practice.next_word"))
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .minimumScaleFactor(0.85)
                        } icon: {
                            NoorSystemImage.revealWord.image
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasHiddenWord)

                    Button {
                        Task { await viewModel.skipQuestion() }
                    } label: {
                        Label {
                            Text(l("hifz_test.action.skip"))
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .minimumScaleFactor(0.85)
                        } icon: {
                            NoorSystemImage.skipPassage.image
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                Button {
                    viewModel.revealAndGrade()
                } label: {
                    Text(l("hifz_test.action.reveal"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .grading:
            let gradeLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))

            gradeLayout {
                Button {
                    Task { await viewModel.gradeForgot() }
                } label: {
                    Text(l("hifz_practice.forgot"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)

                Button {
                    viewModel.beginMarkingMistakes()
                } label: {
                    Text(l("hifz_practice.mistakes"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.large)

                Button {
                    Task { await viewModel.gradeCorrect() }
                } label: {
                    Text(l("hifz_practice.correct"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            }

        case .markingMistakes:
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))

            layout {
                Button {
                    viewModel.cancelMarkingMistakes()
                } label: {
                    Text(lAndroid("cancel"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    Task { await viewModel.saveMistakesAndAdvance() }
                } label: {
                    Text(l("hifz_test.action.save_grade"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private static func formattedTimer(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let mins = clamped / 60
        let secs = clamped % 60
        let minText = NumberFormatter.shared.format(mins)
        let secText = secs < 10
            ? NumberFormatter.shared.format(0) + NumberFormatter.shared.format(secs)
            : NumberFormatter.shared.format(secs)
        return "\(minText):\(secText)"
    }
}

/// Wrapping horizontal RTL word chips for tapping exact mistaken words.
private struct FlowWordChips: View {
    let units: [SpotTestWordUnit]
    let marked: Set<Int>
    let isVerseForgot: Bool
    let onTap: (SpotTestWordUnit) -> Void

    private static let wordFontSize: CGFloat = 20

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 72), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(units) { unit in
                let isMarked = isVerseForgot || marked.isSuperset(of: unit.wordNumbers)
                Button {
                    onTap(unit)
                } label: {
                    Text(unit.text)
                        .font(.custom(FontName.uthmanicHafs, size: Self.wordFontSize, relativeTo: .title3))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isMarked ? Color.red.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isMarked ? Color.red : Color.clear, lineWidth: 1.5)
                        )
                        .foregroundStyle(isMarked ? .red : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isMarked ? .isSelected : [])
            }
        }
    }
}

// MARK: - Results View

private struct SpotTestResultsView: View {
    @Bindable var viewModel: SpotTestViewModel
    let report: SpotTestScoreReport
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.locale = .fixedCurrentLocaleNumbers
        return formatter
    }()

    var body: some View {
        NoorList {
            NoorBasicSection {
                VStack(alignment: .leading, spacing: 12) {
                    statusBanner

                    let columns = dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

                    LazyVGrid(columns: columns, spacing: 10) {
                        scoreCard(
                            title: l("hifz_test.score.strict"),
                            ratio: report.strictScore,
                            detail: lFormat(
                                "hifz_test.score.strict.detail",
                                NumberFormatter.shared.format(report.strictPassedQuestions),
                                NumberFormatter.shared.format(report.assessedQuestions)
                            ),
                            color: .green
                        )
                        scoreCard(
                            title: l("hifz_test.score.word_recall"),
                            ratio: report.wordRecallScore,
                            detail: lFormat(
                                "hifz_test.score.word_recall.detail",
                                NumberFormatter.shared.format(report.recalledWords),
                                NumberFormatter.shared.format(report.assessedWords)
                            ),
                            color: .blue
                        )
                        scoreCard(
                            title: l("hifz_test.score.coverage"),
                            ratio: report.coverageScore,
                            detail: lFormat(
                                "hifz_test.score.coverage.detail",
                                NumberFormatter.shared.format(report.assessedQuestions),
                                NumberFormatter.shared.format(report.coverageScore?.denominator ?? report.plannedQuestions)
                            ),
                            color: .teal
                        )
                        scoreCard(
                            title: l("hifz_test.score.assistance"),
                            ratio: report.assistanceRate,
                            detail: lFormat(
                                "hifz_test.score.assistance.detail",
                                NumberFormatter.shared.format(report.totalHints),
                                NumberFormatter.shared.format(report.revealedVerses)
                            ),
                            color: .orange
                        )
                    }

                    HStack(spacing: 16) {
                        Label {
                            Text(lFormat("hifz_test.summary.streak", NumberFormatter.shared.format(report.bestStreak)))
                        } icon: {
                            NoorSystemImage.checkmark_checked.image
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        Label {
                            Text(lFormat("hifz_test.summary.skipped", NumberFormatter.shared.format(report.skippedQuestions)))
                        } icon: {
                            NoorSystemImage.skipPassage.image
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            if !viewModel.results.isEmpty {
                NoorBasicSection(title: l("hifz_test.section.breakdown")) {
                    ForEach(viewModel.results) { item in
                        resultRow(item)
                    }
                }
            }

            NoorBasicSection {
                Button {
                    Task { await viewModel.replaySameQuestions() }
                } label: {
                    Label {
                        Text(l("hifz_test.action.replay"))
                    } icon: {
                        NoorSystemImage.replayTest.image
                    }
                }

                Button {
                    Task { await viewModel.resetToSetup() }
                } label: {
                    Label {
                        Text(l("hifz_test.action.new_test"))
                    } icon: {
                        NoorSystemImage.spotTest.image
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if viewModel.activeConfiguration.isTemporary {
            Text(l("hifz_test.results.temporary_notice"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
        } else if viewModel.saveFailed {
            Text(l("hifz_test.results.save_failed"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)
        } else if viewModel.savedToHistory {
            Text(l("hifz_test.results.saved_notice"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.green)
        } else {
            Text(l("hifz_test.results.empty_notice"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func scoreCard(title: String, ratio: SpotTestRatio?, detail: String, color: Color) -> some View {
        let valueText: String = if let ratio {
            Self.percentFormatter.string(from: NSNumber(value: ratio.fraction)) ?? "—"
        } else {
            "—"
        }

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(valueText)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .accessibilityElement(children: .combine)
    }

    private func resultRow(_ result: SpotTestQuestionResult) -> some View {
        let range = result.question.passage.first ... result.question.passage.last
        let reference: MultipartText = "\(ayahRange: range)"
        let (statusText, statusColor) = Self.statusBadge(for: result)

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                reference.view(ofSize: .body, allowsWrapping: true)
                    .fontWeight(.semibold)
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(statusColor.opacity(0.14)))

                    if result.isAssessed {
                        Text(
                            lFormat(
                                "hifz_test.score.word_recall.detail",
                                NumberFormatter.shared.format(result.recalledWords),
                                NumberFormatter.shared.format(result.assessedWords)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button {
                    viewModel.practice(result.question.passage)
                } label: {
                    Label {
                        Text(l("hifz_review.action.practice"))
                    } icon: {
                        NoorSystemImage.hifzPractice.image
                    }
                }

                Button {
                    viewModel.openInReader(result.question.passage.first)
                } label: {
                    Label {
                        Text(l("hifz_review.action.open_reader"))
                    } icon: {
                        NoorSystemImage.book.image
                    }
                }
            } label: {
                NoorSystemImage.moreCircle.image
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .accessibilityLabel(l("hifz_practice.options"))
        }
        .padding(.vertical, 4)
    }

    private static func statusBadge(for result: SpotTestQuestionResult) -> (String, Color) {
        if !result.isAssessed {
            return (l("hifz_test.status.skipped"), .secondary)
        }
        if result.isStrictPerfect {
            return (l("hifz_test.status.perfect"), .green)
        }
        if result.revealedVerseCount > 0 {
            return (l("hifz_practice.forgot"), .red)
        }
        if result.verseOutcomes.contains(where: { $0.outcome == .mistake }) {
            return (l("hifz_practice.mistakes"), .orange)
        }
        return (l("hifz_test.status.assisted"), .blue)
    }
}

// MARK: - Custom Range Picker Sheet

private struct SpotTestCustomRangeSheet: View {
    @Bindable var viewModel: SpotTestViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: HifzReviewViewModel.DeclareMode = .surah
    @State private var searchText = ""
    @State private var selectedSuras: Set<Int> = []
    @State private var selectedJuzs: Set<Int> = []
    @State private var startPage = 1
    @State private var endPage = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(l("hifz_test.source.custom"), selection: $mode) {
                    Text(l("hifz_review.declare.mode.surah")).tag(HifzReviewViewModel.DeclareMode.surah)
                    Text(l("hifz_review.declare.mode.juz")).tag(HifzReviewViewModel.DeclareMode.juz)
                    Text(l("hifz_review.declare.mode.pages")).tag(HifzReviewViewModel.DeclareMode.pages)
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .surah:
                    surahList
                case .juz:
                    juzList
                case .pages:
                    pagePicker
                }
            }
            .navigationTitle(l("hifz_test.source.custom"))
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
                        commit()
                        dismiss()
                    }
                    .disabled(!canCommit)
                }
            }
        }
    }

    private var filteredSuras: [Sura] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.quran.suras }
        return viewModel.quran.suras.filter { sura in
            sura.localizedName().localizedCaseInsensitiveContains(query)
                || sura.localizedTranslatedName().localizedCaseInsensitiveContains(query)
                || String(sura.suraNumber).contains(query)
        }
    }

    private var canCommit: Bool {
        switch mode {
        case .surah: !selectedSuras.isEmpty
        case .juz: !selectedJuzs.isEmpty
        case .pages: viewModel.pageRangePreview(from: startPage, to: endPage) != nil
        }
    }

    private var surahList: some View {
        List(filteredSuras) { sura in
            let isSelected = selectedSuras.contains(sura.suraNumber)
            Button {
                if isSelected {
                    selectedSuras.remove(sura.suraNumber)
                } else {
                    selectedSuras.insert(sura.suraNumber)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        let title: MultipartText = "\(sura.localizedSuraNumber). \(sura: sura)"
                        title.view(ofSize: .body, allowsWrapping: true)
                            .foregroundStyle(.primary)
                        Text(lFormat("hifz_review.declare.verse_count", NumberFormatter.shared.format(sura.verses.count)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    (isSelected ? NoorSystemImage.checkmark_checked : NoorSystemImage.checkmark_unchecked).image
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .searchable(text: $searchText)
    }

    private var juzList: some View {
        List(viewModel.quran.juzs) { juz in
            let isSelected = selectedJuzs.contains(juz.juzNumber)
            Button {
                if isSelected {
                    selectedJuzs.remove(juz.juzNumber)
                } else {
                    selectedJuzs.insert(juz.juzNumber)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(juz.localizedName)
                            .foregroundStyle(.primary)
                        let range: MultipartText = "\(ayahRange: juz.firstVerse ... juz.lastVerse)"
                        range.view(ofSize: .footnote, allowsWrapping: true)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    (isSelected ? NoorSystemImage.checkmark_checked : NoorSystemImage.checkmark_unchecked).image
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private var pagePicker: some View {
        Form {
            Section {
                Stepper(value: $startPage, in: 1 ... viewModel.quran.numberOfPages) {
                    HStack {
                        Text(l("hifz_review.declare.from_page"))
                        Spacer()
                        Text(NumberFormatter.shared.format(startPage))
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: startPage) { _, newValue in
                    if endPage < newValue { endPage = newValue }
                }

                Stepper(value: $endPage, in: 1 ... viewModel.quran.numberOfPages) {
                    HStack {
                        Text(l("hifz_review.declare.to_page"))
                        Spacer()
                        Text(NumberFormatter.shared.format(endPage))
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: endPage) { _, newValue in
                    if startPage > newValue { startPage = newValue }
                }
            }

            if let preview = viewModel.pageRangePreview(from: startPage, to: endPage) {
                Section {
                    let ref: MultipartText = "\(ayahRange: preview)"
                    ref.view(ofSize: .body, allowsWrapping: true)
                    Text(lFormat("hifz_review.declare.verse_count", NumberFormatter.shared.format(preview.verseCount)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func commit() {
        switch mode {
        case .surah:
            let suras = viewModel.quran.suras.filter { selectedSuras.contains($0.suraNumber) }
            viewModel.setCustomRanges(AyahRangeSet(suras.map { $0.firstVerse ... $0.lastVerse }))
        case .juz:
            let juzs = viewModel.quran.juzs.filter { selectedJuzs.contains($0.juzNumber) }
            viewModel.setCustomRanges(AyahRangeSet(juzs.map { $0.firstVerse ... $0.lastVerse }))
        case .pages:
            if let range = viewModel.pageRangePreview(from: startPage, to: endPage) {
                viewModel.setCustomRanges(AyahRangeSet(range))
            }
        }
    }
}
