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
            if let cues = viewModel.linePageCues {
                ScrollView(.horizontal) {
                    Text(cues)
                        .font(.custom(FontName.uthmanicHafs, size: wordSize, relativeTo: .title3))
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
    }

    // MARK: Private

    @ScaledMetric(relativeTo: .title3) private var hintSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title3) private var wordSize: CGFloat = 22

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .fixedCurrentLocaleNumbers
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

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
            } else {
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
            HStack {
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
                Spacer(minLength: 0)
                Button(l("hifz_practice.check"), action: viewModel.check)
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
        case .grading:
            HStack {
                gradeButton("hifz_practice.forgot", .revealed)
                Button(action: viewModel.markMistakes) {
                    Text(l("hifz_practice.mistakes"))
                        .frame(maxWidth: .infinity)
                }
                gradeButton("hifz_practice.correct", .correct)
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
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

    /// A word of the checked ayah, in the Quran font; marked words are tinted red and read as selected.
    private func wordButton(_ choice: HifzPracticeViewModel.WordChoice) -> some View {
        let marked = viewModel.markedWords.isSuperset(of: choice.words)
        return Button { viewModel.toggleMistake(choice) } label: {
            Text(choice.text)
                .font(.custom(FontName.uthmanicHafs, size: wordSize, relativeTo: .title3))
                .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .tint(marked ? .red : nil)
        .accessibilityAddTraits(marked ? .isSelected : [])
    }

    /// The localized sentence with the letter in the Quran font, never the system font.
    private func hintText(_ hint: String) -> Text {
        let parts = l("hifz_practice.hint_text").components(separatedBy: "%@")
        let letter = Text(hint).font(.custom(FontName.uthmanicHafs, size: hintSize, relativeTo: .title3))
        return Text("\(parts.first ?? "")\(letter)\(parts.dropFirst().joined())")
    }

    private func gradeButton(_ key: String, _ outcome: RecallOutcome) -> some View {
        AsyncButton(action: { await viewModel.grade(outcome) }) {
            Text(l(key))
                .frame(maxWidth: .infinity)
        }
    }
}
