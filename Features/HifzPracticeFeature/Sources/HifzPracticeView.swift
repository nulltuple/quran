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
import RecitationRecognition
import SwiftUI
import UIKit
import UIx

/// Compact Tarteel-inspired floating practice dock pinned above the bottom safe area.
/// Hidden words are never read out to VoiceOver; live status chips sit directly above a single
/// compact row of small circular icon controls alongside the circular green microphone button.
struct HifzPracticeView: View {
    @Bindable var viewModel: HifzPracticeViewModel

    var body: some View {
        Group {
            switch viewModel.phase {
            case .reciting:
                recitingDock
            case .loading, .grading, .markingMistakes, .finished, .failed:
                compactCard
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
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
        .sheet(isPresented: $showingLiveMistakes) {
            LivePracticeMistakesSheet(
                mistakes: viewModel.liveMistakes,
                onDispute: { viewModel.disputeLiveMistake($0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Private

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconButtonSize: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var micButtonSize: CGFloat = 54
    @State private var showingLiveMistakes = false

    private static let hintFontSize: CGFloat = 20
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

    private static let twoDigitFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .fixedCurrentLocaleNumbers
        formatter.minimumIntegerDigits = 2
        return formatter
    }()

    private static func formattedSize(_ byteCount: Int64) -> String {
        let megabytes = Int((Double(byteCount) / 1_000_000).rounded())
        return lFormat("download_amount_in_megabytes", table: .android, NumberFormatter.shared.format(megabytes))
    }

    private static func formattedElapsed(since start: Date, at now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        let minutes = twoDigitFormatter.string(from: NSNumber(value: elapsed / 60)) ?? "00"
        let seconds = twoDigitFormatter.string(from: NSNumber(value: elapsed % 60)) ?? "00"
        return "\(minutes):\(seconds)"
    }

    // MARK: Compact Reciting Dock (Tarteel layout)

    private var recitingDock: some View {
        VStack(alignment: .leading, spacing: 6) {
            modelStatusBanner
            if let cues = viewModel.linePageCues {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(cues)
                        .font(.custom(FontName.uthmanicHafs, size: Self.wordFontSize, relativeTo: .title3))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .environment(\.layoutDirection, .rightToLeft)
                .glassEffect(in: .capsule)
            }
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    statusChipStrip
                    compactIconRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                micHeroButton
            }
        }
    }

    /// Top micro-status strip: mistakes badge, accuracy/ayah pill, live timer, and optional hint.
    private var statusChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                mistakesChip
                accuracyChip
                liveTimerOrStatusChip
                if let hint = viewModel.hint {
                    hintChip(hint)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var hasMistakes: Bool {
        !viewModel.liveMistakes.isEmpty
    }

    private var mistakesChip: some View {
        let countText = NumberFormatter.shared.format(viewModel.liveMistakes.count)
        return Button {
            showingLiveMistakes = true
        } label: {
            HStack(spacing: 4) {
                NoorSystemImage.mistakeHeatmap.image
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                Text(countText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(hasMistakes ? Color.white : Color.primary)
            .background {
                if hasMistakes {
                    Capsule().fill(Color.practiceMistakeWord)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasMistakes)
        .accessibilityLabel(lFormat("recitation_check.mistakes", countText))
    }

    private var accuracyChip: some View {
        let accuracy = viewModel.liveAccuracyPercent ?? 100
        let accuracyText = Self.percentFormatter.format(Double(accuracy) / 100.0)
        let verseNumberText = viewModel.currentVerse.map {
            "\(NumberFormatter.shared.format($0.sura.suraNumber)):\(NumberFormatter.shared.format($0.ayah))"
        }
        return HStack(spacing: 5) {
            if let verseNumberText {
                Text(verseNumberText)
                    .monospacedDigit()
                Text("|")
                    .opacity(0.5)
            }
            Text(accuracyText)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(hasMistakes ? Color.white : Color.primary)
        .background {
            if hasMistakes {
                Capsule().fill(Color.practiceMistakeWord)
            } else {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var liveTimerOrStatusChip: some View {
        switch viewModel.liveRecitationState {
        case .listening:
            if let startedAt = viewModel.liveRecitationStartedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.practiceMistakeWord)
                            .frame(width: 7, height: 7)
                        Text(Self.formattedElapsed(since: startedAt, at: context.date))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                }
            }
        case .offTrack:
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                Text(l("hifz_practice.recite.off_track"))
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.75))
        case .preparing:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text(l("voice_search.preparing"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(.ultraThinMaterial))
        case .stoppedAfterSilence:
            HStack(spacing: 4) {
                NoorSystemImage.heardNothing.image
                    .font(.caption2)
                Text(l("recitation_follow.stopped"))
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(.ultraThinMaterial))
        case .failed:
            Text(l("voice_search.failed.text"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(.ultraThinMaterial))
        case .off, .needsModel, .downloading:
            EmptyView()
        }
    }

    private func hintChip(_ hint: String) -> some View {
        hintText(hint)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.practiceActiveWord.opacity(0.4), lineWidth: 0.75))
    }

    /// Single compact row of small circular icon buttons (book mode toggle, reveal word/ayah pill,
    /// hint, listen, options, close).
    private var compactIconRow: some View {
        let activeBorder = viewModel.isLiveReciting
            ? Color.practiceActiveWord.opacity(0.45)
            : Color.primary.opacity(0.12)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if viewModel.canToggleReaderMode {
                    dockCircleButton(
                        icon: viewModel.isTranslationMode ? .book : .bookFilled,
                        accessibilityLabel: l(viewModel.isTranslationMode ? "menu.arabic" : "menu.translation"),
                        borderColor: activeBorder,
                        action: viewModel.toggleReaderMode
                    )
                }

                // Grouped reveal pill: `<` reveals next word, `<<` reveals/checks the whole ayah.
                HStack(spacing: 0) {
                    Button(action: viewModel.revealNextWord) {
                        NoorSystemImage.nextVerse.image
                            .font(.subheadline.weight(.semibold))
                            .frame(width: iconButtonSize, height: iconButtonSize)
                            .contentShape(Rectangle())
                    }
                    .disabled(!viewModel.hasHiddenWord)
                    .accessibilityLabel(l("hifz_practice.next_word"))

                    Divider()
                        .frame(height: iconButtonSize * 0.5)

                    Button(action: viewModel.check) {
                        NoorSystemImage.revealAyah.image
                            .font(.subheadline.weight(.semibold))
                            .frame(width: iconButtonSize, height: iconButtonSize)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(l("hifz_practice.check"))
                }
                .foregroundStyle(.primary)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(activeBorder, lineWidth: 1))

                dockCircleButton(
                    icon: .firstLetterHint,
                    accessibilityLabel: l("hifz_practice.hint"),
                    borderColor: activeBorder,
                    disabled: !viewModel.hasHiddenWord,
                    action: viewModel.showHint
                )

                dockCircleButton(
                    icon: viewModel.isListening ? .stopListening : .listenAndRepeat,
                    accessibilityLabel: l(viewModel.isListening ? "hifz_practice.stop_listening" : "hifz_practice.listen"),
                    tint: viewModel.isListening ? Color.practiceMistakeWord : nil,
                    borderColor: activeBorder,
                    action: viewModel.toggleListening
                )

                optionsMenu(borderColor: activeBorder)

                AsyncButton(action: { await viewModel.end() }) {
                    NoorSystemImage.cancel.image
                        .font(.subheadline.weight(.semibold))
                        .frame(width: iconButtonSize, height: iconButtonSize)
                        .contentShape(Circle())
                }
                .foregroundStyle(.secondary)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .accessibilityLabel(l("hifz_practice.end"))
            }
            .padding(.vertical, 1)
            .buttonStyle(.plain)
        }
    }

    private func dockCircleButton(
        icon: NoorSystemImage,
        accessibilityLabel: String,
        tint: Color? = nil,
        borderColor: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon.image
                .font(.subheadline.weight(.semibold))
                .frame(width: iconButtonSize, height: iconButtonSize)
                .contentShape(Circle())
        }
        .foregroundStyle(tint ?? .primary)
        .opacity(disabled ? 0.35 : 1)
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(Circle().strokeBorder(borderColor, lineWidth: 1))
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func optionsMenu(borderColor: Color) -> some View {
        Menu {
            Toggle(l("hifz_practice.highlight_mistakes"), isOn: $viewModel.highlightLiveMistakes)
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
                .font(.subheadline.weight(.semibold))
                .frame(width: iconButtonSize, height: iconButtonSize)
                .contentShape(Circle())
        }
        .foregroundStyle(.primary)
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(Circle().strokeBorder(borderColor, lineWidth: 1))
        .accessibilityLabel(l("hifz_practice.options"))
    }

    /// Tarteel-style circular green microphone / stop hero button.
    private var micHeroButton: some View {
        AsyncButton(action: { await viewModel.toggleLiveRecitation() }) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.practiceMicStart, .practiceMicEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.practiceActiveWord.opacity(0.38), radius: 8, y: 2)
                if viewModel.liveRecitationState == .preparing || isDownloadingModel {
                    ProgressView()
                        .tint(.white)
                } else if viewModel.isLiveReciting {
                    NoorSystemImage.stop.image
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    NoorSystemImage.listening.image
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: micButtonSize, height: micButtonSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.liveRecitationState == .preparing || isDownloadingModel)
        .accessibilityLabel(l(viewModel.isLiveReciting ? "hifz_practice.stop_reciting" : "hifz_practice.recite"))
        .accessibilityAddTraits(viewModel.isLiveReciting ? .isSelected : [])
    }

    @ViewBuilder private var modelStatusBanner: some View {
        switch viewModel.liveRecitationState {
        case .needsModel(let byteCount):
            HStack(spacing: 8) {
                Text(lFormat("recitation_follow.needs_model", Self.formattedSize(byteCount)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AsyncButton(action: { await viewModel.downloadRecitationModel() }) {
                    Text(lFormat("voice_search.download.button", Self.formattedSize(byteCount)))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 16))
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                Text(l("voice_search.downloading"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .accessibilityValue(Self.percentFormatter.format(progress))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 16))
        default:
            EmptyView()
        }
    }

    // MARK: Compact Grading / Mistake-Marking / Finished Card

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    cardTitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                AsyncButton(action: { await viewModel.end() }) {
                    NoorSystemImage.cancel.image
                        .padding(6)
                        .contentShape(Circle())
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel(l("hifz_practice.end"))
            }
            cardActions
        }
        .padding(12)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    @ViewBuilder private var cardTitle: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
        case .grading, .markingMistakes, .reciting:
            if let verse = viewModel.currentVerse {
                let reference: MultipartText = "\(ayah: verse)"
                reference.view(ofSize: .subheadline, allowsWrapping: false)
                    .fontWeight(.semibold)
            }
            Text(l(viewModel.phase == .markingMistakes ? "hifz_practice.mark_prompt" : "hifz_practice.grade_prompt"))
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    @ViewBuilder private var cardActions: some View {
        switch viewModel.phase {
        case .grading:
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    gradingButtons
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 8) {
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
                if hasMistakes {
                    mistakesChip
                }
                Spacer()
                AsyncButton(action: { await viewModel.end() }) {
                    Text(l("button.close"))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        case .loading, .reciting:
            EmptyView()
        }
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

    private var isDownloadingModel: Bool {
        if case .downloading = viewModel.liveRecitationState { return true }
        return false
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
        .tint(marked ? Color.practiceMistakeWord : nil)
        .accessibilityAddTraits(marked ? .isSelected : [])
    }

    /// The localized sentence with the letter in the Quran font, never the system font.
    private func hintText(_ hint: String) -> Text {
        let parts = l("hifz_practice.hint_text").components(separatedBy: "%@")
        let letter = Text(hint).font(.custom(FontName.uthmanicHafs, size: Self.hintFontSize, relativeTo: .body))
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

private struct LivePracticeMistakesSheet: View {
    let mistakes: [LivePracticeMistake]
    let onDispute: (LivePracticeMistake) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if mistakes.isEmpty {
                    ContentUnavailableView {
                        Label(l("recitation_check.no_mistakes"), systemImage: NoorSystemImage.confirmMistake.rawValue)
                    }
                } else {
                    List(mistakes) { mistake in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                let reference: MultipartText = "\(ayah: mistake.word.verse)"
                                reference.view(ofSize: .subheadline, allowsWrapping: false)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(kindLabel(mistake.kind))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.practiceMistakeWord)
                            }
                            HStack(alignment: .firstTextBaseline) {
                                Text(l("hifz_practice.live_mistakes.expected"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(mistake.expectedText)
                                    .font(.custom(FontName.uthmanicHafs, size: 22, relativeTo: .title3))
                                    .foregroundStyle(Color.practiceActiveWord)
                            }
                            if !mistake.recitedText.isEmpty {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(l("hifz_practice.live_mistakes.recited"))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(mistake.recitedText)
                                        .font(.custom(FontName.uthmanicHafs, size: 22, relativeTo: .title3))
                                        .foregroundStyle(Color.practiceMistakeWord)
                                }
                            }
                            Button(role: .destructive) {
                                onDispute(mistake)
                            } label: {
                                Label(l("mistake_history.action.dispute"), systemImage: NoorSystemImage.disputeMistake.rawValue)
                                    .font(.footnote)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(l("hifz_practice.mistakes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        NoorSystemImage.cancel.image
                    }
                    .accessibilityLabel(l("button.close"))
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    private func kindLabel(_ kind: LivePracticeMistake.Kind) -> String {
        switch kind {
        case .substitution: l("hifz_practice.live_mistakes.kind.substitution")
        case .omitted: l("hifz_practice.live_mistakes.kind.omitted")
        case .stumble: l("hifz_practice.live_mistakes.kind.stumble")
        case .hesitation: l("hifz_practice.live_mistakes.kind.hesitation")
        }
    }
}
