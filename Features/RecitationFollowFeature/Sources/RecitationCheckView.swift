//
//  RecitationCheckView.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Localization
import NoorUI
import QuranKit
import RecitationRecognition
import SwiftUI

struct RecitationCheckView: View {
    // MARK: Internal

    @ObservedObject var viewModel: RecitationCheckViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A bar, not an inset: the text scrolling under the button fades out (scroll edge effect).
        .safeAreaBar(edge: .bottom) {
            actionButton
                .padding()
        }
        .task { await viewModel.start() }
        .alert(
            failureTitle,
            isPresented: Binding(get: { viewModel.failure != nil }, set: { if !$0 { viewModel.failure = nil } }),
            presenting: viewModel.failure
        ) { failure in
            if failure == .microphoneDenied {
                Button(l("voice_search.open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Button(l("button.close"), role: .cancel) {}
        } message: { failure in
            Text(failureMessage(failure))
        }
        .onChange(of: viewModel.state) { _, state in
            if case .checked(let check) = state {
                let announcement = viewModel.policy == .silent
                    ? silentSummary
                    : summary(check)
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
        }
    }

    // MARK: Private

    @ScaledMetric private var spacing = 16.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var passageTitle: MultipartText {
        guard let first = viewModel.verses.first, let last = viewModel.verses.last else {
            return ""
        }
        return first == last ? "\(ayah: first)" : "\(ayahRange: first ... last)"
    }

    @ViewBuilder
    private var content: some View {
        passageTitle.view(ofSize: .body)
            .foregroundStyle(.secondary)
        switch viewModel.state {
        case .preparing:
            ProgressView(l("voice_search.preparing"))
        case .needsModel(let byteCount):
            Text(lFormat("recitation_check.needs_model", Self.size(byteCount)))
        case .downloading(let progress):
            ProgressView(l("voice_search.downloading"), value: progress)
        case .ready:
            policyPicker
            Text(viewModel.policy == .silent ? l("recitation_check.ready.silent") : l("recitation_check.ready"))
        case .listening:
            Label(l("recitation_check.listening"), systemImage: NoorSystemImage.reciteAlong.rawValue)
                .symbolEffect(.pulse)
        case .checking:
            ProgressView(l("recitation_check.checking"))
        case .checked(let check):
            if viewModel.policy == .silent {
                silentResult
            } else {
                result(check)
            }
        case .failed:
            Text(l("voice_search.failed.text"))
        }
    }

    private var policyPicker: some View {
        Picker(l("recitation_check.policy.title"), selection: $viewModel.policy) {
            Text(l("recitation_check.policy.show_mistakes")).tag(RecitationCheckPolicy.showMistakes)
            Text(l("recitation_check.policy.silent")).tag(RecitationCheckPolicy.silent)
        }
        .pickerStyle(.segmented)
    }

    private var silentSummary: String {
        if viewModel.recordedReachedVerseCount == 0 {
            return l("recitation_check.silent.nothing_recorded")
        }
        return l("recitation_check.silent.saved.title")
    }

    @ViewBuilder
    private var silentResult: some View {
        policyPicker
        Text(silentSummary)
            .font(.headline)
        if viewModel.recordedReachedVerseCount > 0 {
            Text(l("recitation_check.silent.saved.message"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if viewModel.recordSaveFailed {
            Text(l("recitation_check.save_failed"))
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.state {
        case .needsModel(let byteCount):
            Button { Task { await viewModel.download() } } label: {
                Text(lFormat("voice_search.download.button", Self.size(byteCount))).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .ready:
            Button { Task { await viewModel.startListening() } } label: {
                Text(l("recitation_check.start")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .listening:
            Button { Task { await viewModel.stopAndCheck() } } label: {
                Text(l("recitation_check.stop")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .checked:
            Button { Task { await viewModel.startListening() } } label: {
                Text(l("recitation_check.again")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .preparing, .downloading, .checking, .failed:
            EmptyView()
        }
    }

    private var failureTitle: String {
        switch viewModel.failure {
        case .downloadFailed: l("voice_search.download.failed.title")
        case .microphoneDenied, .microphoneUnavailable, nil: l("voice_search.microphone.title")
        }
    }

    private static func size(_ byteCount: Int64) -> String {
        let megabytes = Int((Double(byteCount) / 1_000_000).rounded())
        return lFormat("download_amount_in_megabytes", table: .android, NumberFormatter.shared.format(megabytes))
    }

    @ViewBuilder
    private func result(_ check: RecitationCheck) -> some View {
        policyPicker
        Text(summary(check))
            .font(.headline)
        QuranMarkedText(segments)
        if viewModel.recordSaveFailed {
            Text(l("recitation_check.save_failed"))
                .font(.footnote)
                .foregroundStyle(.red)
        }
        if !viewModel.recordedMistakes.isEmpty {
            VStack(alignment: .leading, spacing: spacing / 2) {
                ForEach(viewModel.recordedMistakes) { item in
                    mistakeRow(item)
                }
            }
            .font(.callout)
        }
        let uncertain = viewModel.checkedTexts.count { $0.mark == .uncertain }
        if uncertain > 0 {
            Text(lFormat("recitation_check.uncertain", NumberFormatter.shared.format(uncertain)))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func mistakeRow(_ item: RecitationCheckViewModel.RecordedMistakeItem) -> some View {
        let label = mistakeLabel(item)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))

        layout {
            Text(label)
                .strikethrough(item.isDisputed)
                .foregroundStyle(item.isDisputed ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.isDisputed {
                Text(l("mistake_history.status.disputed"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if !item.evidenceIDs.isEmpty {
                Button(role: .destructive) {
                    Task { await viewModel.dispute(item) }
                } label: {
                    Text(l("mistake_history.action.dispute"))
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func mistakeLabel(_ item: RecitationCheckViewModel.RecordedMistakeItem) -> String {
        switch item.kind {
        case .skippedVerse:
            lFormat("recitation_check.skipped_verse", NumberFormatter.shared.format(item.verse.ayah))
        case .omitted(let wordText):
            lFormat("recitation_check.omitted", wordText)
        case .substituted(let recited, let expected):
            lFormat("recitation_check.substituted", recited, expected)
        }
    }

    private var segments: [QuranMarkedText.Segment] {
        let disputedWords = Set(
            viewModel.recordedMistakes
                .filter(\.isDisputed)
                .flatMap { item in item.wordNumbers.map { Word(verse: item.verse, wordNumber: $0) } }
        )
        let disputedSkippedVerses = Set(
            viewModel.recordedMistakes
                .filter { $0.isDisputed && $0.kind == .skippedVerse }
                .map(\.verse)
        )
        return viewModel.checkedTexts.flatMap { text -> [QuranMarkedText.Segment] in
            let isDisputed = disputedSkippedVerses.contains(text.verse)
                || text.wordNumbers.contains { disputedWords.contains(Word(verse: text.verse, wordNumber: $0)) }
            let style: QuranMarkedText.Segment.Style = if isDisputed {
                .plain
            } else {
                switch text.mark {
                case .correct: .plain
                case .omitted: .struck(.red)
                case .substituted: .marked(.red)
                case .uncertain: .marked(.orange)
                case .notReached: .faded
                }
            }
            var segments = [QuranMarkedText.Segment(text: text.text, style: style)]
            if let verse = text.endsVerse {
                segments.append(.init(text: NumberFormatter.arabicNumberFormatter.format(verse.ayah), style: .plain))
            }
            return segments
        }
    }

    private func summary(_ check: RecitationCheck) -> String {
        let mistakes = viewModel.recordedMistakes.isEmpty
            ? check.mistakes.count
            : viewModel.recordedMistakes.count { !$0.isDisputed }
        return mistakes == 0
            ? l("recitation_check.no_mistakes")
            : lFormat("recitation_check.mistakes", NumberFormatter.shared.format(mistakes))
    }

    private func failureMessage(_ failure: RecitationCheckViewModel.Failure) -> String {
        switch failure {
        case .downloadFailed: l("voice_search.download.failed.message")
        case .microphoneDenied: l("recitation_check.microphone.denied")
        case .microphoneUnavailable: l("recitation_check.microphone.unavailable")
        }
    }
}
