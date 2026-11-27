//
//  HifzReviewSheets.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Localization
import MemorizationService
import NoorUI
import QuranKit
import QuranLocalization
import SwiftUI

struct DeclareMemorizedSheet: View {
    // MARK: Internal

    @Bindable var viewModel: HifzReviewViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(l("hifz_review.declare.title"), selection: $mode) {
                    Text(l("hifz_review.declare.mode.surah")).tag(HifzReviewViewModel.DeclareMode.surah)
                    Text(l("hifz_review.declare.mode.juz")).tag(HifzReviewViewModel.DeclareMode.juz)
                    Text(l("hifz_review.declare.mode.pages")).tag(HifzReviewViewModel.DeclareMode.pages)
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .surah:
                    surahPickerList
                case .juz:
                    juzPickerList
                case .pages:
                    pageRangePicker
                }
            }
            .navigationTitle(l("hifz_review.declare.title"))
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
                    Button(l("hifz_review.declare.save")) {
                        Task {
                            await commit()
                            dismiss()
                        }
                    }
                    .disabled(!canCommit)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var mode: HifzReviewViewModel.DeclareMode = .surah
    @State private var searchText = ""
    @State private var selectedSuras: Set<Int> = []
    @State private var selectedJuzs: Set<Int> = []
    @State private var startPage = 1
    @State private var endPage = 1

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

    private var surahPickerList: some View {
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

    private var juzPickerList: some View {
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

    private var pageRangePicker: some View {
        Form {
            Section {
                Stepper(
                    value: $startPage,
                    in: 1 ... viewModel.quran.numberOfPages
                ) {
                    HStack {
                        Text(l("hifz_review.declare.from_page"))
                        Spacer()
                        Text(NumberFormatter.shared.format(startPage))
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: startPage) { _, newValue in
                    if endPage < newValue {
                        endPage = newValue
                    }
                }

                Stepper(
                    value: $endPage,
                    in: 1 ... viewModel.quran.numberOfPages
                ) {
                    HStack {
                        Text(l("hifz_review.declare.to_page"))
                        Spacer()
                        Text(NumberFormatter.shared.format(endPage))
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: endPage) { _, newValue in
                    if startPage > newValue {
                        startPage = newValue
                    }
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

    private func commit() async {
        switch mode {
        case .surah:
            let suras = viewModel.quran.suras.filter { selectedSuras.contains($0.suraNumber) }
            await viewModel.declareSuras(suras)
        case .juz:
            let juzs = viewModel.quran.juzs.filter { selectedJuzs.contains($0.juzNumber) }
            await viewModel.declareJuzs(juzs)
        case .pages:
            await viewModel.declarePages(from: startPage, to: endPage)
        }
    }
}

struct DailyBudgetsSheet: View {
    // MARK: Lifecycle

    init(initialBudgets: ReviewDailyBudgets, save: @escaping (ReviewDailyBudgets) async -> Void) {
        _budgets = State(initialValue: initialBudgets)
        self.save = save
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text(l("hifz_review.budgets.footer"))) {
                    budgetStepper(bucket: .sabaq, value: $budgets.sabaq)
                    budgetStepper(bucket: .sabqi, value: $budgets.sabqi)
                    budgetStepper(bucket: .manzil, value: $budgets.manzil)
                }
            }
            .navigationTitle(l("hifz_review.budgets.title"))
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
                            await save(budgets)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var budgets: ReviewDailyBudgets
    private let save: (ReviewDailyBudgets) async -> Void

    private func budgetStepper(bucket: ReviewBucket, value: Binding<Int>) -> some View {
        Stepper(value: value, in: ReviewDailyBudgets.range) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(HifzReviewFormatting.bucketName(bucket))
                        .fontWeight(.semibold)
                    Spacer()
                    Text(lFormat("hifz_review.budgets.per_day", NumberFormatter.shared.format(value.wrappedValue)))
                        .foregroundStyle(.secondary)
                }
                Text(HifzReviewFormatting.bucketDescription(bucket))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ReschedulePassageSheet: View {
    // MARK: Lifecycle

    init(
        item: ReviewQueueItem,
        dateForDays: @escaping (Int) -> Date,
        onReschedule: @escaping (Date) async -> Void
    ) {
        self.item = item
        self.dateForDays = dateForDays
        self.onReschedule = onReschedule
        _selectedDate = State(initialValue: dateForDays(1))
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let ref: MultipartText = "\(ayahRange: item.passage.first ... item.passage.last)"
                    ref.view(ofSize: .body, allowsWrapping: true)
                        .fontWeight(.semibold)
                }

                Section {
                    presetButton(title: l("hifz_review.reschedule.tomorrow"), days: 1)
                    presetButton(title: l("hifz_review.reschedule.three_days"), days: 3)
                    presetButton(title: l("hifz_review.reschedule.one_week"), days: 7)
                }

                Section(header: Text(l("hifz_review.reschedule.custom"))) {
                    DatePicker(
                        l("hifz_review.reschedule.custom"),
                        selection: $selectedDate,
                        in: dateForDays(1)...,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                }
            }
            .navigationTitle(l("hifz_review.reschedule.title"))
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
                            await onReschedule(selectedDate)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    private let item: ReviewQueueItem
    private let dateForDays: (Int) -> Date
    private let onReschedule: (Date) async -> Void
    @State private var selectedDate: Date

    private func presetButton(title: String, days: Int) -> some View {
        let target = dateForDays(days)
        return Button {
            Task {
                await onReschedule(target)
                dismiss()
            }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(HifzReviewFormatting.shortDateFormatter.string(from: target))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SplitPassageSheet: View {
    // MARK: Lifecycle

    init(item: ReviewQueueItem, onSplit: @escaping (AyahNumber) async -> Void) {
        self.item = item
        self.onSplit = onSplit
        let verses = item.passage.verses
        let midpoint = verses[max(0, (verses.count / 2) - 1)]
        _splitAfter = State(initialValue: midpoint)
    }

    // MARK: Internal

    var body: some View {
        let verses = item.passage.verses
        let choices = Array(verses.dropLast())

        NavigationStack {
            Form {
                Section(header: Text(l("hifz_review.split.prompt"))) {
                    Picker(l("hifz_review.split.prompt"), selection: $splitAfter) {
                        ForEach(choices, id: \.self) { verse in
                            Text(verse.localizedName).tag(verse)
                        }
                    }
                }

                if let secondStart = splitAfter.next {
                    Section {
                        LabeledContent(l("hifz_review.split.part_one")) {
                            let part1: MultipartText = "\(ayahRange: item.passage.first ... splitAfter)"
                            part1.view(ofSize: .subheadline, allowsWrapping: true)
                        }
                        LabeledContent(l("hifz_review.split.part_two")) {
                            let part2: MultipartText = "\(ayahRange: secondStart ... item.passage.last)"
                            part2.view(ofSize: .subheadline, allowsWrapping: true)
                        }
                    }
                }
            }
            .navigationTitle(l("hifz_review.split.title"))
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
                            await onSplit(splitAfter)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    private let item: ReviewQueueItem
    private let onSplit: (AyahNumber) async -> Void
    @State private var splitAfter: AyahNumber
}
