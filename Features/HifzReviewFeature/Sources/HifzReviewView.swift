//
//  HifzReviewView.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Localization
import MemorizationService
import NoorUI
import QuranAnnotations
import QuranKit
import QuranLocalization
import SwiftUI
import UIx

struct HifzReviewView: View {
    // MARK: Internal

    @Bindable var viewModel: HifzReviewViewModel

    var body: some View {
        Group {
            switch viewModel.selectedTab {
            case .queue:
                queueContent
            case .repair:
                repairContent
            case .map:
                if let map = viewModel.map {
                    HifzMapView(
                        summary: map,
                        practiceRange: { viewModel.startPractice(range: $0) },
                        openAyah: { viewModel.openInReader($0) }
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker(l("hifz_review.title"), selection: $viewModel.selectedTab) {
                Text(l("hifz_review.tab.queue")).tag(HifzReviewViewModel.SectionTab.queue)
                Text(l("hifz_review.tab.repair")).tag(HifzReviewViewModel.SectionTab.repair)
                Text(l("hifz_review.tab.map")).tag(HifzReviewViewModel.SectionTab.map)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(l("hifz_review.title"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    viewModel.openSpotTest()
                } label: {
                    NoorSystemImage.spotTest.image
                }
                .tint(.primary)
                .accessibilityLabel(l("hifz_test.title"))

                Button {
                    viewModel.isBudgetsPresented = true
                } label: {
                    NoorSystemImage.reviewBudgets.image
                }
                .tint(.primary)
                .accessibilityLabel(l("hifz_review.action.budgets"))

                Button {
                    viewModel.isDeclarePresented = true
                } label: {
                    NoorSystemImage.declareMemorized.image
                }
                .tint(.primary)
                .accessibilityLabel(l("hifz_review.action.declare"))
            }
        }
        .task {
            await viewModel.reload()
        }
        .onAppear {
            Task { await viewModel.reload() }
        }
        .sheet(isPresented: $viewModel.isDeclarePresented) {
            DeclareMemorizedSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isBudgetsPresented) {
            DailyBudgetsSheet(
                initialBudgets: viewModel.budgets,
                save: { newBudgets in
                    await viewModel.saveBudgets(newBudgets)
                }
            )
        }
        .sheet(item: $viewModel.rescheduleTarget) { item in
            ReschedulePassageSheet(
                item: item,
                dateForDays: { viewModel.rescheduleDate(daysFromNow: $0) },
                onReschedule: { date in
                    await viewModel.reschedule(item, until: date)
                }
            )
        }
        .sheet(item: $viewModel.splitTarget) { item in
            SplitPassageSheet(
                item: item,
                onSplit: { splitVerse in
                    await viewModel.split(item, after: splitVerse)
                }
            )
        }
        .sheet(item: $viewModel.mistakeDetailTarget) { target in
            if let detailVM = viewModel.makeMistakeDetailViewModel(for: target.verse) {
                NavigationStack {
                    MistakeDetailView(viewModel: detailVM)
                        .navigationTitle(l("mistake_history.title"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    viewModel.mistakeDetailTarget = nil
                                } label: {
                                    NoorSystemImage.cancel.image
                                }
                                .tint(.primary)
                                .accessibilityLabel(l("button.close"))
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .alert(
            l("hifz_review.reset.confirm.title"),
            isPresented: Binding(
                get: { viewModel.resetTarget != nil },
                set: { if !$0 { viewModel.resetTarget = nil } }
            ),
            presenting: viewModel.resetTarget
        ) { item in
            Button(lAndroid("cancel"), role: .cancel) {}
            Button(l("hifz_review.action.reset"), role: .destructive) {
                Task { await viewModel.confirmReset(item) }
            }
        } message: { item in
            let range = (item.passage.first ... item.passage.last).localizedName()
            Text(lFormat("hifz_review.reset.confirm.message", range))
        }
        .alert(
            l("hifz_review.remove_range.confirm.title"),
            isPresented: Binding(
                get: { viewModel.removeRangeTarget != nil },
                set: { if !$0 { viewModel.removeRangeTarget = nil } }
            ),
            presenting: viewModel.removeRangeTarget
        ) { range in
            Button(lAndroid("cancel"), role: .cancel) {}
            Button(l("hifz_review.action.remove"), role: .destructive) {
                Task { await viewModel.confirmRemoveRange(range) }
            }
        } message: { range in
            Text(lFormat("hifz_review.remove_range.confirm.message", range.range.localizedName()))
        }
    }

    // MARK: Private

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    private var repairContent: some View {
        if viewModel.loadFailed {
            ContentUnavailableView {
                Label {
                    Text(l("hifz_review.error.load_failed"))
                } icon: {
                    NoorSystemImage.syncStatusFailed.image
                }
            } actions: {
                Button(l("sync.action.try-again")) {
                    Task { await viewModel.reload() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if viewModel.repairItems.isEmpty, !viewModel.isLoading {
            ContentUnavailableView {
                Label {
                    Text(l("repair_queue.empty.title"))
                } icon: {
                    NoorSystemImage.repairQueue.image
                }
            } description: {
                Text(l("repair_queue.empty.message"))
            }
        } else {
            NoorList {
                if let top = viewModel.repairItems.first {
                    NoorBasicSection {
                        VStack(alignment: .leading, spacing: 10) {
                            let passagesCount = NumberFormatter.shared.format(viewModel.repairItems.count)
                            let versesCount = NumberFormatter.shared.format(
                                viewModel.repairItems.reduce(0) { $0 + $1.mistakenVerseCount }
                            )
                            Text(lFormat("repair_queue.summary", passagesCount, versesCount))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button {
                                viewModel.startRepairPractice(top)
                            } label: {
                                Label {
                                    Text(l("repair_queue.action.practice_top"))
                                } icon: {
                                    NoorSystemImage.hifzPractice.image
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }

                NoorBasicSection(title: l("repair_queue.section.passages")) {
                    ForEach(viewModel.repairItems) { item in
                        repairRow(item)
                    }
                }
            }
            .refreshable {
                await viewModel.reload()
            }
        }
    }

    private func repairRow(_ item: RepairQueueItem) -> some View {
        let range = item.passage.first ... item.passage.last
        let reference: MultipartText = "\(ayahRange: range)"
        let heatColor = item.maxHeatLevel.accentColor
        let heatLabel: String = switch item.maxHeatLevel {
        case .high: l("mistake_history.heat.high")
        case .medium: l("mistake_history.heat.medium")
        case .low: l("mistake_history.heat.low")
        }
        let verseCountText = NumberFormatter.shared.format(item.mistakenVerseCount)
        let subtitle: String = if item.mistakenWordCount > 0 {
            lFormat("repair_queue.row.verses_and_words", verseCountText, NumberFormatter.shared.format(item.mistakenWordCount))
        } else {
            lFormat("repair_queue.row.verses_only", verseCountText)
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    viewModel.startRepairPractice(item)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        reference.view(ofSize: .body, allowsWrapping: true)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            badge(heatLabel, color: heatColor)
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        viewModel.startRepairPractice(item)
                    } label: {
                        Label {
                            Text(l("mistake_history.action.practice_passage"))
                        } icon: {
                            NoorSystemImage.hifzPractice.image
                        }
                    }
                    Button {
                        viewModel.openInReader(item.hotVerses.first?.verse ?? item.passage.first)
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
                        .contentShape(Circle())
                }
                .accessibilityLabel(l("hifz_practice.options"))
            }

            if !item.hotVerses.isEmpty {
                WrappingHStack(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(item.hotVerses.prefix(6)) { verseSummary in
                        let chipColor = verseSummary.level?.accentColor ?? .orange
                        let label = "\(NumberFormatter.shared.format(verseSummary.verse.sura.suraNumber)):\(NumberFormatter.shared.format(verseSummary.verse.ayah))"
                        Button {
                            viewModel.mistakeDetailTarget = .init(verse: verseSummary.verse)
                        } label: {
                            Text(label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(chipColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(chipColor.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(lFormat("repair_queue.chip.accessibility", verseSummary.verse.localizedName))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var queueContent: some View {
        let hasItems = !viewModel.queue.dueItems.isEmpty
            || !viewModel.queue.upcomingItems.isEmpty
            || !viewModel.queue.declaredRanges.isEmpty

        if viewModel.loadFailed {
            ContentUnavailableView {
                Label {
                    Text(l("hifz_review.error.load_failed"))
                } icon: {
                    NoorSystemImage.syncStatusFailed.image
                }
            } actions: {
                Button(l("sync.action.try-again")) {
                    Task { await viewModel.reload() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if !hasItems, !viewModel.isLoading {
            ContentUnavailableView {
                Label {
                    Text(l("hifz_review.empty.title"))
                } icon: {
                    NoorSystemImage.reviewQueue.image
                }
            } description: {
                Text(l("hifz_review.empty.message"))
            } actions: {
                Button(l("hifz_review.action.declare")) {
                    viewModel.isDeclarePresented = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            NoorList {
                if !viewModel.queue.bucketSummaries.isEmpty {
                    NoorBasicSection {
                        bucketSummaryStrip
                    }
                }

                let dueToday = viewModel.filteredDueToday
                if !dueToday.isEmpty {
                    NoorBasicSection(title: l("hifz_review.section.due_today")) {
                        ForEach(dueToday) { item in
                            queueRow(item)
                        }
                    }
                }

                let moreDue = viewModel.filteredMoreDue
                if !moreDue.isEmpty {
                    NoorBasicSection(title: l("hifz_review.section.more_due")) {
                        ForEach(moreDue) { item in
                            queueRow(item)
                        }
                    }
                }

                let upcoming = viewModel.filteredUpcoming
                if !upcoming.isEmpty {
                    NoorBasicSection(title: l("hifz_review.section.upcoming")) {
                        ForEach(upcoming) { item in
                            queueRow(item)
                        }
                    }
                }

                if !viewModel.queue.declaredRanges.isEmpty {
                    NoorBasicSection(title: l("hifz_review.section.declared_ranges")) {
                        ForEach(viewModel.queue.declaredRanges) { declared in
                            declaredRangeRow(declared)
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.reload()
            }
        }
    }

    @ViewBuilder
    private var bucketSummaryStrip: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        layout {
            ForEach(viewModel.queue.bucketSummaries) { summary in
                bucketCard(summary)
            }
        }
        .padding(.vertical, 4)
    }

    private func bucketCard(_ summary: ReviewBucketSummary) -> some View {
        let isSelected = viewModel.bucketFilter == .bucket(summary.bucket)
        let color = HifzReviewFormatting.bucketColor(summary.bucket)
        let progress = lFormat(
            "hifz_review.bucket.progress",
            NumberFormatter.shared.format(summary.completedToday),
            NumberFormatter.shared.format(summary.dailyBudget),
            NumberFormatter.shared.format(summary.dueCount)
        )

        return Button {
            viewModel.toggleBucketFilter(summary.bucket)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(HifzReviewFormatting.bucketName(summary.bucket))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? color.opacity(0.16) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func queueRow(_ item: ReviewQueueItem) -> some View {
        let range = item.passage.first ... item.passage.last
        let reference: MultipartText = "\(ayahRange: range)"
        let bucketColor = HifzReviewFormatting.bucketColor(item.bucket)
        let stateColor = HifzReviewFormatting.strengthColor(item.progress.strength, isDeclared: item.isDeclared)
        let stateText = HifzReviewFormatting.strengthLabel(item.progress.strength, isDeclared: item.isDeclared)
        let reasonText = HifzReviewFormatting.reasonText(item.reason)

        return HStack(alignment: .center, spacing: 12) {
            Button {
                viewModel.startPractice(item)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    reference.view(ofSize: .body, allowsWrapping: true)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            badge(HifzReviewFormatting.bucketName(item.bucket), color: bucketColor)
                            badge(stateText, color: stateColor)
                        }
                    } else {
                        HStack(spacing: 6) {
                            badge(HifzReviewFormatting.bucketName(item.bucket), color: bucketColor)
                            badge(stateText, color: stateColor)
                        }
                    }

                    Text(reasonText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                rowMenuItems(for: item)
            } label: {
                NoorSystemImage.moreCircle.image
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Circle())
            }
            .accessibilityLabel(l("hifz_practice.options"))
        }
        .padding(.vertical, 4)
        .contextMenu {
            rowMenuItems(for: item)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                Task { await viewModel.skip(item) }
            } label: {
                Label {
                    Text(l("hifz_review.action.skip"))
                } icon: {
                    NoorSystemImage.skipPassage.image
                }
            }
            .tint(.orange)

            Button {
                viewModel.rescheduleTarget = item
            } label: {
                Label {
                    Text(l("hifz_review.action.reschedule"))
                } icon: {
                    NoorSystemImage.reschedule.image
                }
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func rowMenuItems(for item: ReviewQueueItem) -> some View {
        Button {
            viewModel.startPractice(item)
        } label: {
            Label {
                Text(l("hifz_review.action.practice"))
            } icon: {
                NoorSystemImage.hifzPractice.image
            }
        }

        Button {
            viewModel.openInReader(item.passage.first)
        } label: {
            Label {
                Text(l("hifz_review.action.open_reader"))
            } icon: {
                NoorSystemImage.book.image
            }
        }

        Divider()

        Button {
            Task { await viewModel.skip(item) }
        } label: {
            Label {
                Text(l("hifz_review.action.skip"))
            } icon: {
                NoorSystemImage.skipPassage.image
            }
        }

        Button {
            viewModel.rescheduleTarget = item
        } label: {
            Label {
                Text(l("hifz_review.action.reschedule"))
            } icon: {
                NoorSystemImage.reschedule.image
            }
        }

        if item.passage.verses.count > 1 {
            Button {
                viewModel.splitTarget = item
            } label: {
                Label {
                    Text(l("hifz_review.action.split"))
                } icon: {
                    NoorSystemImage.splitPassage.image
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            viewModel.resetTarget = item
        } label: {
            Label {
                Text(l("hifz_review.action.reset"))
            } icon: {
                NoorSystemImage.resetProgress.image
            }
        }
    }

    private func declaredRangeRow(_ declared: DeclaredRangeItem) -> some View {
        let reference: MultipartText = "\(ayahRange: declared.range)"
        let verseCount = lFormat("hifz_review.declare.verse_count", NumberFormatter.shared.format(declared.range.verseCount))

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                reference.view(ofSize: .body, allowsWrapping: true)
                    .foregroundStyle(.primary)
                Text(verseCount)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                viewModel.removeRangeTarget = declared
            } label: {
                Text(l("hifz_review.action.remove"))
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}
