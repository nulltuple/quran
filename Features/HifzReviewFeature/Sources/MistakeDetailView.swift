//
//  MistakeDetailView.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Localization
import MemorizationPersistence
import MemorizationService
import NoorFont
import NoorUI
import QuranAnnotations
import QuranKit
import QuranLocalization
import QuranText
import SwiftUI
import UIx

/// Detail sheet for one ayah's mistake history across sessions (roadmap H7):
/// shows marked Arabic text, decayed heat level, active/retracted events, confirm/dispute/remove,
/// ayah note access, and passage practice launch.
struct MistakeDetailView: View {
    // MARK: Internal

    @Bindable var viewModel: MistakeDetailViewModel

    var body: some View {
        Group {
            if viewModel.loadFailed {
                ContentUnavailableView {
                    Label {
                        Text(l("mistake_history.error.load_failed"))
                    } icon: {
                        NoorSystemImage.syncStatusFailed.image
                    }
                } actions: {
                    Button(l("sync.action.try-again")) {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewModel.isLoading, viewModel.summary == nil, viewModel.wordUnits.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailList
            }
        }
        .task {
            await viewModel.load()
        }
        .alert(
            l("mistake_history.error.update_failed"),
            isPresented: $viewModel.mutationFailed
        ) {
            Button(l("button.close"), role: .cancel) {}
        }
    }

    // MARK: Private

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var detailList: some View {
        NoorList {
            NoorBasicSection {
                VStack(alignment: .leading, spacing: 12) {
                    headerRow
                    if !viewModel.wordUnits.isEmpty {
                        QuranMarkedText(markedSegments)
                    }
                    summaryFooter
                }
                .padding(.vertical, 4)
            }

            if viewModel.canPractice || viewModel.canEditNote || viewModel.canOpenInReader {
                NoorBasicSection {
                    if viewModel.canPractice {
                        NoorListItem(
                            image: .init(.hifzPractice),
                            title: .text(l("mistake_history.action.practice_passage")),
                            accessory: .disclosureIndicator,
                            action: .sync { viewModel.practiceRepairPassage() }
                        )
                    }
                    if viewModel.canEditNote {
                        NoorListItem(
                            image: .init(.notes),
                            title: .text(l("mistake_history.action.ayah_note")),
                            accessory: .disclosureIndicator,
                            action: .sync { viewModel.editNote() }
                        )
                    }
                    if viewModel.canOpenInReader {
                        NoorListItem(
                            image: .init(.book),
                            title: .text(l("hifz_review.action.open_reader")),
                            accessory: .disclosureIndicator,
                            action: .sync { viewModel.openReader() }
                        )
                    }
                }
            }

            if let summary = viewModel.summary, !summary.activeEvents.isEmpty {
                NoorBasicSection(title: l("mistake_history.section.active")) {
                    ForEach(summary.activeEvents) { event in
                        activeEventRow(event)
                    }
                }
            } else {
                NoorBasicSection(title: l("mistake_history.section.active")) {
                    Text(l("mistake_history.empty.active"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }

            if let summary = viewModel.summary, !summary.retractedEvents.isEmpty {
                NoorBasicSection(title: l("mistake_history.section.retracted")) {
                    ForEach(summary.retractedEvents) { event in
                        retractedEventRow(event)
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        let reference: MultipartText = "\(ayah: viewModel.canonicalVerse)"
        let level = viewModel.summary?.level
        return ViewThatFits(in: .horizontal) {
            HStack {
                reference.view(ofSize: .body, allowsWrapping: true)
                    .fontWeight(.semibold)
                Spacer()
                heatBadge(level)
            }
            VStack(alignment: .leading, spacing: 6) {
                reference.view(ofSize: .body, allowsWrapping: true)
                    .fontWeight(.semibold)
                heatBadge(level)
            }
        }
    }

    private var markedSegments: [QuranMarkedText.Segment] {
        var segments = viewModel.wordUnits.map { unit -> QuranMarkedText.Segment in
            let style: QuranMarkedText.Segment.Style = switch viewModel.heatLevel(for: unit) {
            case .high: .marked(.red)
            case .medium, .low: .marked(.orange)
            case nil: .plain
            }
            return QuranMarkedText.Segment(text: unit.text, style: style)
        }
        segments.append(.init(text: NumberFormatter.arabicNumberFormatter.format(viewModel.canonicalVerse.ayah), style: .plain))
        return segments
    }

    private var summaryFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let summary = viewModel.summary, summary.sessionCount > 0 {
                let sessions = NumberFormatter.shared.format(summary.sessionCount)
                let clean = NumberFormatter.shared.format(summary.cleanRecallsSinceLastMistake)
                Text(lFormat("mistake_history.summary.counts", sessions, clean))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(l("mistake_history.decay.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func heatBadge(_ level: MistakeHeatLevel?) -> some View {
        let color: Color = level?.accentColor ?? .green
        let title: String = switch level {
        case .high: l("mistake_history.heat.high")
        case .medium: l("mistake_history.heat.medium")
        case .low: l("mistake_history.heat.low")
        case nil: l("mistake_history.heat.cleared")
        }
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private func activeEventRow(_ event: MistakeEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            eventHeader(event, dimmed: false)
            eventActionButtons(event)
        }
        .padding(.vertical, 4)
    }

    private func retractedEventRow(_ event: MistakeEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            eventHeader(event, dimmed: true)
            let statusText = event.provenance == .model
                ? l("mistake_history.status.disputed")
                : l("mistake_history.status.removed")
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(0.7)
        .padding(.vertical, 4)
    }

    private func eventHeader(_ event: MistakeEvent, dimmed: Bool) -> some View {
        let outcomeText = event.outcome == .revealed
            ? l("hifz_practice.grade.forgot")
            : l("hifz_practice.grade.mistakes")
        let provenanceText = event.provenance == .model
            ? l("mistake_history.provenance.model")
            : l("mistake_history.provenance.manual")
        let dateText = HifzReviewFormatting.shortDateFormatter.string(from: event.recordedOn)

        return VStack(alignment: .leading, spacing: 4) {
            if let wordText = viewModel.arabicText(forWord: event.word) {
                QuranTextView(QuranText(wordText), quranFont: .uthmanicHafs)
                    .font(.title3)
                    .foregroundStyle(dimmed ? .secondary : .primary)
            } else {
                Text(l("mistake_history.whole_ayah"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(dimmed ? .secondary : .primary)
            }

            Text("\(outcomeText) · \(provenanceText) · \(dateText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func eventActionButtons(_ event: MistakeEvent) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        layout {
            if event.provenance == .model {
                Button {
                    Task { await viewModel.confirm(event) }
                } label: {
                    Label {
                        Text(l("mistake_history.action.confirm"))
                    } icon: {
                        NoorSystemImage.confirmMistake.image
                    }
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    Task { await viewModel.retract(event) }
                } label: {
                    Label {
                        Text(l("mistake_history.action.dispute"))
                    } icon: {
                        NoorSystemImage.disputeMistake.image
                    }
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)
            } else {
                Button(role: .destructive) {
                    Task { await viewModel.retract(event) }
                } label: {
                    Label {
                        Text(l("mistake_history.action.remove"))
                    } icon: {
                        NoorSystemImage.delete.image
                    }
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
