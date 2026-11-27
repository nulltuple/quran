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
                UIAccessibility.post(notification: .announcement, argument: summary(check))
            }
        }
    }

    // MARK: Private

    @ScaledMetric private var spacing = 16.0

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
            Text(l("recitation_check.ready"))
        case .listening:
            Label(l("recitation_check.listening"), systemImage: NoorSystemImage.reciteAlong.rawValue)
                .symbolEffect(.pulse)
        case .checking:
            ProgressView(l("recitation_check.checking"))
        case .checked(let check):
            result(check)
        case .failed:
            Text(l("voice_search.failed.text"))
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
        Text(summary(check))
            .font(.headline)
        QuranMarkedText(segments)
        let notes = notes(check)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: spacing / 2) {
                ForEach(notes, id: \.self) { note in
                    Text(note)
                }
            }
            .font(.callout)
        }
    }

    private var segments: [QuranMarkedText.Segment] {
        viewModel.checkedTexts.flatMap { text -> [QuranMarkedText.Segment] in
            let style: QuranMarkedText.Segment.Style = switch text.mark {
            case .correct: .plain
            case .omitted: .struck(.red)
            case .substituted: .marked(.red)
            case .uncertain: .marked(.orange)
            case .notReached: .faded
            }
            var segments = [QuranMarkedText.Segment(text: text.text, style: style)]
            if let verse = text.endsVerse {
                segments.append(.init(text: NumberFormatter.arabicNumberFormatter.format(verse.ayah), style: .plain))
            }
            return segments
        }
    }

    private func summary(_ check: RecitationCheck) -> String {
        let mistakes = check.mistakes.count
        return mistakes == 0
            ? l("recitation_check.no_mistakes")
            : lFormat("recitation_check.mistakes", NumberFormatter.shared.format(mistakes))
    }

    /// One line per mistake, then one for the words to check.
    private func notes(_ check: RecitationCheck) -> [String] {
        let texts = Dictionary(viewModel.checkedTexts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lines = check.skippedVerses.map { lFormat("recitation_check.skipped_verse", NumberFormatter.shared.format($0.ayah)) }
        for text in texts.values.sorted(by: { $0.id < $1.id }) {
            switch text.mark {
            case .omitted where !check.skippedVerses.contains(text.verse):
                lines.append(lFormat("recitation_check.omitted", text.text))
            case .substituted(let recited):
                lines.append(lFormat("recitation_check.substituted", recited, text.text))
            default:
                break
            }
        }
        let uncertain = viewModel.checkedTexts.count { $0.mark == .uncertain }
        if uncertain > 0 {
            lines.append(lFormat("recitation_check.uncertain", NumberFormatter.shared.format(uncertain)))
        }
        return lines
    }

    private func failureMessage(_ failure: RecitationCheckViewModel.Failure) -> String {
        switch failure {
        case .downloadFailed: l("voice_search.download.failed.message")
        case .microphoneDenied: l("recitation_check.microphone.denied")
        case .microphoneUnavailable: l("voice_search.microphone.unavailable")
        }
    }
}
