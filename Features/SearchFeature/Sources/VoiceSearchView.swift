//
//  VoiceSearchView.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Localization
import NoorUI
import QuranKit
import QuranText
import SwiftUI
import UIx

struct VoiceSearchView: View {
    @StateObject var viewModel: VoiceSearchViewModel
    let quranFont: QuranFont
    let dismiss: @MainActor @Sendable () -> Void

    var body: some View {
        NavigationStack {
            VoiceSearchContent(
                state: viewModel.state,
                quranFont: quranFont,
                download: { await viewModel.download() },
                listen: { await viewModel.startListening() },
                stop: { await viewModel.stopListening() },
                tryAgain: { await viewModel.tryAgain() },
                select: { viewModel.select($0) }
            )
            .navigationTitle(l("voice_search.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem(action: dismiss) }
        }
        .task { await viewModel.start() }
        .onDisappear { viewModel.cancel() }
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
    }

    private var failureTitle: String {
        switch viewModel.failure {
        case .downloadFailed: l("voice_search.download.failed.title")
        case .microphoneDenied, .microphoneUnavailable, nil: l("voice_search.microphone.title")
        }
    }

    private func failureMessage(_ failure: VoiceSearchViewModel.Failure) -> String {
        switch failure {
        case .downloadFailed: l("voice_search.download.failed.message")
        case .microphoneDenied: l("voice_search.microphone.denied")
        case .microphoneUnavailable: l("voice_search.microphone.unavailable")
        }
    }
}

private struct VoiceSearchContent: View {
    let state: VoiceSearchViewModel.State
    let quranFont: QuranFont
    let download: AsyncAction
    let listen: AsyncAction
    let stop: AsyncAction
    let tryAgain: AsyncAction
    let select: ItemAction<VoiceSearchViewModel.Candidate>

    var body: some View {
        switch state {
        case .preparing:
            ProgressView(l("voice_search.preparing"))
        case .needsModel(let byteCount):
            ContentUnavailableView {
                Label { Text(l("voice_search.download.title")) } icon: { NoorSystemImage.voiceSearch.image }
            } description: {
                Text(lFormat("voice_search.download.message", Self.size(byteCount)))
            } actions: {
                AsyncButton(action: download) {
                    Text(lFormat("voice_search.download.button", Self.size(byteCount)))
                }
                .buttonStyle(.borderedProminent)
            }
        case .downloading(let progress):
            ProgressView(value: progress) {
                Text(l("voice_search.downloading"))
            } currentValueLabel: {
                Text(Self.percent.format(progress))
            }
            .padding()
        case .ready:
            prompt(title: l("voice_search.prompt.title"), text: l("voice_search.prompt.text"), image: .voiceSearch)
        case .listening(let level):
            ListeningView(level: level, stop: stop)
        case .recognizing:
            ProgressView(l("voice_search.recognizing"))
        case .results(let results):
            resultsList(results)
        case .heardNothing:
            prompt(title: l("voice_search.heard_nothing.title"), text: l("voice_search.heard_nothing.text"), image: .heardNothing)
        case .noMatch:
            prompt(title: l("voice_search.no_match.title"), text: l("voice_search.no_match.text"), image: .search)
        case .failed:
            prompt(title: l("voice_search.failed.title"), text: l("voice_search.failed.text"), image: .voiceSearch)
        }
    }

    private static let percent: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = .fixedCurrentLocaleNumbers
        return formatter
    }()

    /// Whole megabytes (1,000,000 bytes, as the Files app counts them).
    private static func size(_ byteCount: Int64) -> String {
        let megabytes = Int((Double(byteCount) / 1_000_000).rounded())
        return lFormat("download_amount_in_megabytes", table: .android, NumberFormatter.shared.format(megabytes))
    }

    private func prompt(title: String, text: String, image: NoorSystemImage) -> some View {
        ContentUnavailableView {
            Label { Text(title) } icon: { image.image }
        } description: {
            Text(text)
        } actions: {
            AsyncButton(action: state == .ready ? listen : tryAgain) {
                Label { Text(l("voice_search.recite")) } icon: { NoorSystemImage.listening.image }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func resultsList(_ results: VoiceSearchViewModel.Results) -> some View {
        NoorList {
            if results.isConfident, let best = results.candidates.first {
                NoorSection(title: l("voice_search.results.best"), [best]) { row($0) }
                let others = Array(results.candidates.dropFirst())
                if !others.isEmpty {
                    NoorSection(title: l("voice_search.results.others"), others) { row($0) }
                }
            } else {
                NoorSection(
                    title: l("voice_search.results.unsure"),
                    footer: l("voice_search.results.unsure.footer"),
                    results.candidates
                ) { row($0) }
            }
            NoorBasicSection {
                AsyncButton(action: tryAgain) {
                    Label { Text(l("voice_search.recite")) } icon: { NoorSystemImage.listening.image }
                }
            }
        }
    }

    private func row(_ candidate: VoiceSearchViewModel.Candidate) -> some View {
        NoorListItem(
            subheading: "\(ayahRange: candidate.verses)",
            title: candidate.text.map { "\(quran: $0, font: quranFont, lineLimit: 2)" } ?? "\(ayahRange: candidate.verses)",
            action: .sync { select(candidate) }
        )
    }
}

/// The microphone while it listens: a ring that grows with the level (still under Reduce Motion),
/// the instruction, and a button to search without waiting for the pause.
private struct ListeningView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var iconSize = 64.0

    let level: Double
    let stop: AsyncAction

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: iconSize * 2, height: iconSize * 2)
                    .scaleEffect(reduceMotion ? 1 : 0.7 + min(level * 3, 1) * 0.5)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: level)
                NoorSystemImage.listening.image
                    .font(.system(size: iconSize * 0.6))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)
            Text(l("voice_search.listening.title"))
                .font(.title3.bold())
                .padding(.top)
            Text(l("voice_search.listening.text"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            AsyncButton(action: stop) {
                Text(l("voice_search.search_now"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text(l("voice_search.privacy"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
