//
//  HifzPracticeView.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Localization
import MemorizationPersistence
import MemorizationService
import NoorFont
import NoorUI
import QuranKit
import SwiftUI
import UIKit
import UIx

/// The practice controls, where the audio bar sits. Hidden words are never read out: the bar names
/// the ayah, and shows a first letter only when asked; the ayah's words appear only once it is checked.
struct HifzPracticeView: View {
    @Bindable var viewModel: HifzPracticeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if viewModel.phase == .reciting || viewModel.phase == .grading {
                    optionsMenu
                }
                AsyncButton(action: { await viewModel.end() }) {
                    NoorSystemImage.cancel.image
                        .padding(8)
                        .contentShape(Circle())
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel(l("hifz_practice.end"))
            }
            if viewModel.phase == .reciting {
                liveRecitationBanner
            }
            if let cues = viewModel.linePageCues {
                ScrollView(.horizontal) {
                    Text(cues)
                        .font(.custom(FontName.uthmanicHafs, size: Self.wordFontSize, relativeTo: .title3))
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
            actions
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 24))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .task { await viewModel.start() }
        .alert(
            failureTitle,
            isPresented: Binding(
                get: { viewModel.liveRecitationFailure != nil },
                set: { if !$0 { viewModel.liveRecitationFailure = nil } }
            ),
            presenting: viewModel.liveRecitationFailure
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
        .onChange(of: viewModel.liveRecitationState) { _, state in
            switch state {
            case .offTrack:
                UIAccessibility.post(notification: .announcement, argument: l("hifz_practice.recite.off_track"))
            case .stoppedAfterSilence:
                UIAccessibility.post(notification: .announcement, argument: l("recitation_follow.stopped"))
            default:
                break
            }
        }
    }

    // MARK: Private

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let hintFontSize: CGFloat = 24
    private static let wordFontSize: CGFloat = 22

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .fixedCurrentLocaleNumbers
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = .fixedCurrentLocaleNumbers
        return formatter
    }()

    private static func formattedSize(_ byteCount: Int64) -> String {
        let megabytes = Int((Double(byteCount) / 1_000_000).rounded())
        return lFormat("download_amount_in_megabytes", table: .android, NumberFormatter.shared.format(megabytes))
    }

    @ViewBuilder private var title: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
        case .reciting, .grading, .markingMistakes:
            if let verse = viewModel.currentVerse {
                let reference: MultipartText = "\(ayah: verse)"
                reference.view(ofSize: .subheadline, allowsWrapping: false)
                    .fontWeight(.semibold)
                if viewModel.usesLinePage {
                    Text(l("hifz_practice.ayah_mask"))
                        .font(.caption)
                }
                progressText
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let hint = viewModel.hint {
                hintText(hint)
                    .font(.subheadline)
            } else if viewModel.phase != .reciting || viewModel.liveRecitationState == .off {
                Text(l(promptKey))
                    .font(.subheadline)
            }
        case .finished(let progress):
            Text(l("hifz_practice.saved"))
                .font(.subheadline.weight(.semibold))
            if let due = progress.due {
                Text(lFormat("hifz_practice.next_review", Self.dateFormatter.string(from: due)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Text(l("hifz_practice.failed"))
                .font(.subheadline)
        }
    }

    @ViewBuilder private var liveRecitationBanner: some View {
        switch viewModel.liveRecitationState {
        case .off:
            EmptyView()
        case .preparing:
            HStack(spacing: 8) {
                ProgressView()
                Text(l("voice_search.preparing"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .needsModel(let byteCount):
            HStack(spacing: 8) {
                Text(lFormat("recitation_follow.needs_model", Self.formattedSize(byteCount)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AsyncButton(action: { await viewModel.downloadRecitationModel() }) {
                    Text(lFormat("voice_search.download.button", Self.formattedSize(byteCount)))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                Text(l("voice_search.downloading"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .accessibilityValue(Self.percentFormatter.format(progress))
            }
        case .listening:
            HStack(spacing: 6) {
                NoorSystemImage.listening.image
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(l("hifz_practice.recite.listening"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .offTrack:
            HStack(spacing: 6) {
                NoorSystemImage.listening.image
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(l("hifz_practice.recite.off_track"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .stoppedAfterSilence:
            HStack(spacing: 6) {
                NoorSystemImage.heardNothing.image
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(l("recitation_follow.stopped"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Text(l("voice_search.failed.text"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var promptKey: String {
        switch viewModel.phase {
        case .grading: "hifz_practice.grade_prompt"
        case .markingMistakes: "hifz_practice.mark_prompt"
        default: viewModel.resumed ? "hifz_practice.resumed" : "hifz_practice.recite_prompt"
        }
    }

    private var progressText: Text {
        guard let current = viewModel.currentStep else {
            return Text(verbatim: "")
        }
        let ayahs = Text(lFormat(
            "hifz_practice.progress",
            NumberFormatter.shared.format(viewModel.position + 1),
            NumberFormatter.shared.format(viewModel.totalPositions)
        ))
        guard viewModel.order == .cumulative else {
            return ayahs
        }
        let step = Text(lFormat(
            "hifz_practice.step_progress",
            NumberFormatter.shared.format(current.step + 1),
            NumberFormatter.shared.format(viewModel.steps.count)
        ))
        return Text("\(step) · \(ayahs)")
    }

    private var optionsMenu: some View {
        Menu {
            Picker(l("hifz_practice.cues"), selection: Binding(get: { viewModel.cueLevel }, set: viewModel.setCueLevel)) {
                Text(l("hifz_practice.cues.none")).tag(PracticeCueLevel.none)
                Text(l("hifz_practice.cues.first_word")).tag(PracticeCueLevel.firstWord)
                Text(l("hifz_practice.cues.alternate_words")).tag(PracticeCueLevel.alternateWords)
            }
            .pickerStyle(.menu)
            Picker(l("hifz_practice.order"), selection: Binding(get: { viewModel.order }, set: viewModel.setOrder)) {
                Text(l("hifz_practice.order.straight")).tag(PracticeOrder.straight)
                Text(l("hifz_practice.order.cumulative")).tag(PracticeOrder.cumulative)
            }
            .pickerStyle(.menu)
            .disabled(!viewModel.canChangeOrder)
        } label: {
            NoorSystemImage.practiceOptions.image
                .padding(8)
                .contentShape(Circle())
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel(l("hifz_practice.options"))
    }

    @ViewBuilder private var actions: some View {
        switch viewModel.phase {
        case .reciting:
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        recitingIconButtons
                    }
                    .buttonStyle(.bordered)
                    .labelStyle(.iconOnly)
                    checkButton(fullWidth: true)
                }
            } else {
                HStack {
                    recitingIconButtons
                    Spacer(minLength: 0)
                    checkButton(fullWidth: false)
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
            }
        case .grading:
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    gradingButtons
                }
                .buttonStyle(.bordered)
            } else {
                HStack {
                    gradingButtons
                }
                .buttonStyle(.bordered)
            }
        case .markingMistakes:
            VStack(alignment: .trailing, spacing: 10) {
                WrappingHStack(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(viewModel.wordChoices) { choice in
                        wordButton(choice)
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                AsyncButton(action: { await viewModel.saveMistakes() }) {
                    Text(l("hifz_practice.save_mistakes"))
                }
                .buttonStyle(.borderedProminent)
            }
        case .finished, .failed:
            HStack {
                Spacer()
                AsyncButton(action: { await viewModel.end() }) {
                    Text(l("button.close"))
                }
                .buttonStyle(.borderedProminent)
            }
        case .loading:
            EmptyView()
        }
    }

    @ViewBuilder private var recitingIconButtons: some View {
        AsyncButton(action: { await viewModel.toggleLiveRecitation() }) {
            if viewModel.isLiveReciting {
                Label(l("hifz_practice.stop_reciting"), systemImage: NoorSystemImage.listening.rawValue)
            } else {
                Label(l("hifz_practice.recite"), systemImage: NoorSystemImage.reciteAlong.rawValue)
            }
        }
        .tint(liveReciteTint)
        .disabled(viewModel.liveRecitationState == .preparing || isDownloadingModel)
        .accessibilityAddTraits(viewModel.isLiveReciting ? .isSelected : [])
        Button(action: viewModel.toggleListening) {
            if viewModel.isListening {
                Label(l("hifz_practice.stop_listening"), systemImage: NoorSystemImage.stopListening.rawValue)
            } else {
                Label(l("hifz_practice.listen"), systemImage: NoorSystemImage.listenAndRepeat.rawValue)
            }
        }
        Button(action: viewModel.showHint) {
            Label(l("hifz_practice.hint"), systemImage: NoorSystemImage.firstLetterHint.rawValue)
        }
        .disabled(!viewModel.hasHiddenWord)
        Button(action: viewModel.revealNextWord) {
            Label(l("hifz_practice.next_word"), systemImage: NoorSystemImage.revealWord.rawValue)
        }
        .disabled(!viewModel.hasHiddenWord)
    }

    @ViewBuilder private var gradingButtons: some View {
        gradeButton("hifz_practice.forgot", .revealed)
        Button(action: viewModel.markMistakes) {
            Text(l("hifz_practice.mistakes"))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
        }
        gradeButton("hifz_practice.correct", .correct)
            .buttonStyle(.borderedProminent)
    }

    private func checkButton(fullWidth: Bool) -> some View {
        Button(action: viewModel.check) {
            Text(l("hifz_practice.check"))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .fixedSize(horizontal: !fullWidth, vertical: false)
    }

    private var isDownloadingModel: Bool {
        if case .downloading = viewModel.liveRecitationState { return true }
        return false
    }

    private var liveReciteTint: Color? {
        switch viewModel.liveRecitationState {
        case .listening: .red
        case .offTrack: .orange
        default: nil
        }
    }

    private var failureTitle: String {
        switch viewModel.liveRecitationFailure {
        case .downloadFailed: l("voice_search.download.failed.title")
        case .microphoneDenied, .microphoneUnavailable, nil: l("voice_search.microphone.title")
        }
    }

    private func failureMessage(_ failure: HifzPracticeViewModel.LiveRecitationFailure) -> String {
        switch failure {
        case .downloadFailed: l("voice_search.download.failed.message")
        case .microphoneDenied: l("recitation_follow.microphone.denied")
        case .microphoneUnavailable: l("voice_search.microphone.unavailable")
        }
    }

    /// A word of the checked ayah, in the Quran font; marked words are tinted red and read as selected.
    private func wordButton(_ choice: HifzPracticeViewModel.WordChoice) -> some View {
        let marked = viewModel.markedWords.isSuperset(of: choice.words)
        return Button { viewModel.toggleMistake(choice) } label: {
            Text(choice.text)
                .font(.custom(FontName.uthmanicHafs, size: Self.wordFontSize, relativeTo: .title3))
                .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .tint(marked ? .red : nil)
        .accessibilityAddTraits(marked ? .isSelected : [])
    }

    /// The localized sentence with the letter in the Quran font, never the system font.
    private func hintText(_ hint: String) -> Text {
        let parts = l("hifz_practice.hint_text").components(separatedBy: "%@")
        let letter = Text(hint).font(.custom(FontName.uthmanicHafs, size: Self.hintFontSize, relativeTo: .title3))
        return Text("\(parts.first ?? "")\(letter)\(parts.dropFirst().joined())")
    }

    private func gradeButton(_ key: String, _ outcome: RecallOutcome) -> some View {
        AsyncButton(action: { await viewModel.grade(outcome) }) {
            Text(l(key))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
        }
    }
}
