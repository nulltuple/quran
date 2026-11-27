//
//  RecitationFollowView.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Localization
import NoorUI
import QuranKit
import SwiftUI
import UIx

/// The reader's live-follow controls: a capsule where the audio banner sits, always visible while
/// the microphone is on, with the state, the action it needs, and Stop.
struct RecitationFollowView: View {
    @ObservedObject var viewModel: RecitationFollowViewModel

    var body: some View {
        RecitationFollowCapsule(
            state: viewModel.state,
            download: { await viewModel.download() },
            listen: { await viewModel.startListening() },
            stop: { viewModel.stop() }
        )
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
            // Each recited word changes the highlight, not the announcement: only losing the place
            // or stopping is announced.
            switch state {
            case .lost: UIAccessibility.post(notification: .announcement, argument: l("recitation_follow.lost"))
            case .stoppedAfterSilence: UIAccessibility.post(notification: .announcement, argument: l("recitation_follow.stopped"))
            default: break
            }
        }
    }

    private var failureTitle: String {
        switch viewModel.failure {
        case .downloadFailed: l("voice_search.download.failed.title")
        case .microphoneDenied, .microphoneUnavailable, nil: l("voice_search.microphone.title")
        }
    }

    private func failureMessage(_ failure: RecitationFollowViewModel.Failure) -> String {
        switch failure {
        case .downloadFailed: l("voice_search.download.failed.message")
        case .microphoneDenied: l("recitation_follow.microphone.denied")
        case .microphoneUnavailable: l("voice_search.microphone.unavailable")
        }
    }
}

struct RecitationFollowCapsule: View {
    let state: RecitationFollowViewModel.State
    let download: AsyncAction
    let listen: AsyncAction
    let stop: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                message
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            action
            Button(action: stop) {
                NoorSystemImage.cancel.image
                    .padding(8)
                    .contentShape(Circle())
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel(l("recitation_follow.stop"))
        }
        .padding(.leading)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var leading: some View {
        switch state {
        case .preparing:
            ProgressView()
        case .listening, .following, .lost:
            NoorSystemImage.listening.image
                .foregroundStyle(state == .lost ? Color.orange : Color.red)
                .accessibilityHidden(true)
        case .needsModel, .downloading, .ready, .failed:
            NoorSystemImage.voiceSearch.image
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .stoppedAfterSilence:
            NoorSystemImage.heardNothing.image
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var message: some View {
        switch state {
        case .preparing:
            Text(l("voice_search.preparing"))
        case .needsModel(let byteCount):
            Text(lFormat("recitation_follow.needs_model", Self.size(byteCount)))
                .font(.subheadline)
        case .downloading(let progress):
            Text(l("voice_search.downloading"))
                .font(.subheadline)
            ProgressView(value: progress)
                .accessibilityValue(Self.percent.format(progress))
        case .ready:
            Text(l("recitation_follow.ready"))
                .font(.subheadline)
        case .listening:
            Text(l("recitation_follow.listening"))
                .font(.subheadline)
        case .following(let verse):
            Text(l("recitation_follow.following"))
                .font(.subheadline.weight(.semibold))
            let reference: MultipartText = "\(ayah: verse)"
            reference.view(ofSize: .footnote, allowsWrapping: false)
                .foregroundStyle(.secondary)
        case .lost:
            Text(l("recitation_follow.lost"))
                .font(.subheadline)
        case .stoppedAfterSilence:
            Text(l("recitation_follow.stopped"))
                .font(.subheadline)
        case .failed:
            Text(l("voice_search.failed.text"))
                .font(.subheadline)
        }
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .needsModel(let byteCount):
            AsyncButton(action: download) {
                Text(lFormat("voice_search.download.button", Self.size(byteCount)))
            }
            .buttonStyle(.borderedProminent)
        case .ready, .stoppedAfterSilence:
            AsyncButton(action: listen) {
                Text(l("voice_search.recite"))
            }
            .buttonStyle(.borderedProminent)
        default:
            EmptyView()
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
}

#Preview("Following") {
    VStack {
        Spacer()
        RecitationFollowCapsule(
            state: .following(Quran.hafsMadani1405.suras[111].firstVerse),
            download: {},
            listen: {},
            stop: {}
        )
        RecitationFollowCapsule(state: .lost, download: {}, listen: {}, stop: {})
        RecitationFollowCapsule(state: .needsModel(byteCount: 84_288_886), download: {}, listen: {}, stop: {})
    }
}
