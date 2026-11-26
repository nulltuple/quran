//
//  PracticeView.swift
//  ArabicLearning (Arabican app)
//

import ArabicScript
import ExerciseKit
import LearningEngine
import LearningModel
import Localization
import NoorFont
import NoorUI
import SwiftUI

struct PracticeView: View {
    let viewModel: PracticeViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                startView
            case .loading:
                ProgressView()
            case .exercise(let exercise):
                ExerciseView(exercise: exercise, feedback: nil, profile: viewModel.profile.presentation) { response in
                    Task { await viewModel.answer(response) }
                }
                .id(viewModel.position)
            case .feedback(let exercise, let outcomes):
                VStack {
                    ExerciseView(exercise: exercise, feedback: outcomes, profile: viewModel.profile.presentation) { _ in }
                    Button(String(localized: "practice.continue", bundle: .module)) { viewModel.advance() }
                        .buttonStyle(.borderedProminent)
                        .padding()
                }
            case .finished(let summary):
                finishedView(summary)
            case .failed:
                DataUnavailableView(
                    title: String(localized: "practice.error.title", bundle: .module),
                    text: String(localized: "practice.error.text", bundle: .module),
                    image: .practice
                )
            }
        }
        .animation(NoorAnimation.standard, value: viewModel.position)
    }

    private var startView: some View {
        ContentUnavailableView {
            Label { Text("practice.start.title", bundle: .module) } icon: { NoorSystemImage.practice.image }
        } description: {
            Text("practice.start.text", bundle: .module)
        } actions: {
            Button(String(localized: "practice.start.button", bundle: .module)) { Task { await viewModel.start() } }
                .buttonStyle(.borderedProminent)
            Button(String(localized: "practice.placement.button", bundle: .module)) { Task { await viewModel.startPlacement() } }
        }
    }

    private func finishedText(_ summary: PracticeViewModel.Summary) -> String {
        guard let placed = summary.placedUnits else {
            return String(
                format: String(localized: "practice.done.text", bundle: .module),
                NumberFormatter.shared.format(summary.correct),
                NumberFormatter.shared.format(summary.correct + summary.incorrect)
            )
        }
        if placed.isEmpty {
            return String(localized: "practice.placement.none.text", bundle: .module)
        }
        return String(format: String(localized: "practice.placement.done.text", bundle: .module), NumberFormatter.shared.format(placed.count))
    }

    private func finishedView(_ summary: PracticeViewModel.Summary) -> some View {
        ContentUnavailableView {
            Label {
                Text(summary.placedUnits == nil ? "practice.done.title" : "practice.placement.done.title", bundle: .module)
            } icon: { NoorSystemImage.checkmark.image }
        } description: {
            Text(finishedText(summary))
        } actions: {
            Button(String(localized: "practice.again", bundle: .module)) { Task { await viewModel.start() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Renders one exercise: choice, match, trace or explanation. `feedback` marks answers after
/// grading. An exercise with audio plays it when it appears and offers to play it again.
struct ExerciseView: View {
    let exercise: Exercise
    let feedback: [AttemptOutcome]?
    let profile: PresentationProfile
    let respond: (ExerciseResponse) -> Void

    @ScaledMetric private var glyphSize = 44.0
    @State private var matchSelection: [Int: Int] = [:]
    @State private var chosenSound: Int?
    @State private var selectedLeft: Int?
    @State private var player = ClipPlayer()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                prompt
                if exercise.audio != nil || exercise.recitation != nil {
                    Button { playPromptAudio() } label: {
                        Label { Text("exercise.playAudio", bundle: .module) } icon: { NoorSystemImage.play.image }
                    }
                    .buttonStyle(.bordered)
                }
                switch exercise.kind {
                case .choice(let options, let answer):
                    choice(options, answer: answer)
                case .audioChoice(let options, let answer):
                    audioChoice(options, answer: answer)
                case .match(let left, let right, let answers):
                    match(left: left, right: right, answers: answers)
                case .explanation:
                    Button(String(localized: "practice.continue", bundle: .module)) { respond(.acknowledged) }
                        .buttonStyle(.borderedProminent)
                case .trace(let guide):
                    TracingCanvas(guide: guide, accessibilityName: traceName, passed: feedback.map { $0 == [.correct] }) {
                        respond(.trace($0))
                    }
                }
                if feedback == nil, exercise.kind != .explanation {
                    Button(String(localized: "practice.skip", bundle: .module)) { respond(.skipped) }
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .task {
            if feedback == nil {
                playPromptAudio()
            }
        }
        .onDisappear { player.stop() }
    }

    private func playPromptAudio() {
        if let recitation = exercise.recitation {
            player.play(recitation)
        } else if let audio = exercise.audio {
            player.play(audio)
        }
    }

    private var traceName: String {
        if case .traceLetter(let letter) = exercise.prompt { return letter.rawValue }
        return ""
    }

    @ViewBuilder private var prompt: some View {
        switch exercise.prompt {
        case .findLetterNamed(let name):
            Text(String(format: String(localized: "exercise.findLetterNamed", bundle: .module), name)).font(.title2)
        case .soundOfLetter(let letter):
            Text("exercise.soundOfLetter", bundle: .module).font(.title2)
            arabic(letter.rawValue)
        case .letterInForm(let letter, let form):
            Text("exercise.letterInForm", bundle: .module).font(.title2)
            arabic(letter.text(in: form) ?? letter.rawValue)
        case .letterForSound(let sound):
            Text(String(format: String(localized: "exercise.letterForSound", bundle: .module), sound)).font(.title2)
        case .listenForLetter:
            Text("exercise.listenForLetter", bundle: .module).font(.title2)
        case .letterInWord(let word):
            Text("exercise.letterInWord", bundle: .module).font(.title2)
            arabic(word.text.text)
        case .traceLetter(let letter):
            Text("exercise.traceLetter", bundle: .module).font(.title2)
            Text(letter.rawValue)
                .font(.custom(.uthmanicHafs, size: glyphSize, relativeTo: .title))
                .accessibilityLabel(letter.rawValue)
        case .listenForSyllable:
            Text("exercise.listenForSyllable", bundle: .module).font(.title2)
        case .readSyllable(let text):
            Text("exercise.readSyllable", bundle: .module).font(.title2).multilineTextAlignment(.center)
            arabic(text)
        case .wordStartingWithSound:
            Text("exercise.wordStartingWithSound", bundle: .module).font(.title2).multilineTextAlignment(.center)
        case .firstSoundOfWord(let word):
            Text("exercise.firstSoundOfWord", bundle: .module).font(.title2).multilineTextAlignment(.center)
            arabic(word.text.text)
        case .markInWord(let word, let feature):
            Text(markQuestion(feature)).font(.title2).multilineTextAlignment(.center)
            arabic(word.text.text)
        case .listenForWord:
            Text("exercise.listenForWord", bundle: .module).font(.title2)
        case .meaningInAyah(let word, let ayah):
            Text("exercise.meaningInAyah", bundle: .module).font(.title2).multilineTextAlignment(.center)
            ayahText(ayah, highlighting: word)
        case .meaningOfLemma(let lemma):
            Text("exercise.meaningOfLemma", bundle: .module).font(.title2)
            arabic(lemma)
        case .tajweedSpot(let example):
            Text("exercise.tajweedSpot", bundle: .module).font(.title2).multilineTextAlignment(.center)
            tajweedAyah(example)
            if feedback != nil {
                tajweedExplanation(example.rule)
            }
        case .tajweedListen(let example):
            Text("exercise.tajweedListen", bundle: .module).font(.title2).multilineTextAlignment(.center)
            // The text stays hidden until the answer: this drill is by ear.
            if feedback != nil {
                tajweedAyah(example)
                tajweedExplanation(example.rule)
            }
        case .matchLettersToNames:
            Text("exercise.matchLettersToNames", bundle: .module).font(.title2)
        case .explanation(let text):
            Text(text).font(.title2).multilineTextAlignment(.center)
        }
    }

    private func markQuestion(_ feature: ReadingFeature) -> String {
        switch feature {
        case .longVowel: String(localized: "exercise.markInWord.longVowel", bundle: .module)
        case .sukun: String(localized: "exercise.markInWord.sukun", bundle: .module)
        case .shadda: String(localized: "exercise.markInWord.shadda", bundle: .module)
        case .tanwin: String(localized: "exercise.markInWord.tanwin", bundle: .module)
        case .silentLetter: String(localized: "exercise.markInWord.silentLetter", bundle: .module)
        default: String(localized: "exercise.markInWord.other", bundle: .module)
        }
    }

    /// Numbered recordings: tapping one plays and selects it; Check submits the selection.
    private func audioChoice(_ options: [AudioClip], answer: Int) -> some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: profile == .child ? 140 : 110))], spacing: 12) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, clip in
                    let number = NumberFormatter.shared.format(index + 1)
                    Button {
                        chosenSound = index
                        player.play(clip)
                    } label: {
                        Label { Text(number) } icon: { NoorSystemImage.play.image }
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: glyphSize * 1.6)
                    }
                    .buttonStyle(.bordered)
                    .tint(feedback == nil ? (chosenSound == index ? .accentColor : nil) : tint(for: index, answer: answer))
                    .accessibilityLabel(String(format: String(localized: "exercise.sound", bundle: .module), number))
                    .accessibilityAddTraits(chosenSound == index ? .isSelected : [])
                }
            }
            if feedback == nil {
                Button(String(localized: "practice.check", bundle: .module)) {
                    if let chosenSound { respond(.choice(chosenSound)) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(chosenSound == nil)
            }
        }
    }

    private func arabic(_ text: String) -> some View {
        Text(text)
            .font(.custom(.uthmanicHafs, size: glyphSize * 2, relativeTo: .largeTitle))
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityLabel(text)
    }

    /// An ayah with one word in the accent color.
    private func ayahText(_ ayah: [QuranWordText], highlighting word: QuranWordText) -> some View {
        let text = ayah.reduce(Text(verbatim: "")) { partial, item in
            let piece = Text(verbatim: item.text.text + " ")
            return partial + (item == word ? piece.foregroundColor(.accentColor).underline() : piece)
        }
        return text
            .font(.custom(.uthmanicHafs, size: glyphSize, relativeTo: .title))
            .multilineTextAlignment(.center)
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityLabel(ayah.map(\.text.text).joined(separator: " "))
            .accessibilityValue(word.text.text)
    }

    private func tajweedAyah(_ example: TajweedExample) -> some View {
        TajweedAyahText(example: example, size: glyphSize)
    }

    private func tajweedExplanation(_ rule: TajweedRule) -> some View {
        GroupBox {
            Text(rule.explanation)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(rule.name)
        }
    }

    private func isArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0600 ... 0x06FF).contains($0.value) }
    }

    private func choice(_ options: [String], answer: Int) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: profile == .child ? 140 : 110))], spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button { respond(.choice(index)) } label: {
                    Text(option)
                        .font(isArabic(option) ? .custom(.uthmanicHafs, size: glyphSize, relativeTo: .largeTitle) : .title2)
                        .frame(maxWidth: .infinity, minHeight: glyphSize * 1.6)
                }
                .buttonStyle(.bordered)
                .tint(tint(for: index, answer: answer))
                // Not .disabled: it greys out the green tint that shows the right answer.
                .allowsHitTesting(feedback == nil)
            }
        }
    }

    private func tint(for index: Int, answer: Int) -> Color? {
        guard let feedback else { return nil }
        if index == answer { return .green }
        return feedback == [.incorrect] ? .secondary : nil
    }

    private func match(left: [String], right: [String], answers: [Int]) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    ForEach(Array(left.enumerated()), id: \.offset) { index, text in
                        Button { selectedLeft = index } label: {
                            Text(text).font(.custom(.uthmanicHafs, size: glyphSize, relativeTo: .largeTitle)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedLeft == index ? .accentColor : matchTint(index, answers: answers))
                    }
                }
                VStack(spacing: 8) {
                    ForEach(Array(right.enumerated()), id: \.offset) { index, text in
                        Button {
                            if let selectedLeft { matchSelection[selectedLeft] = index }
                            selectedLeft = nil
                        } label: {
                            Text(text).font(.title3).frame(maxWidth: .infinity, minHeight: glyphSize)
                        }
                        .buttonStyle(.bordered)
                        .tint(matchSelection.values.contains(index) ? .accentColor : nil)
                    }
                }
            }
            .allowsHitTesting(feedback == nil)
            if feedback == nil {
                Button(String(localized: "practice.check", bundle: .module)) {
                    respond(.match(left.indices.map { matchSelection[$0] ?? -1 }))
                }
                .buttonStyle(.borderedProminent)
                .disabled(matchSelection.count < left.count)
            }
        }
    }

    private func matchTint(_ index: Int, answers: [Int]) -> Color? {
        guard let feedback, feedback.indices.contains(index) else { return nil }
        return feedback[index] == .correct ? .green : .secondary
    }
}

/// An ayah with a tajweed rule's words underlined and its graphemes in the accent color, then the
/// rule's letters on their own. The Quran font draws some letter pairs as one ligature (حَمَّ), and a
/// color change inside a ligature is lost, so the underline and the letters below carry the cue too.
/// Graphemes split as `ArabicScript.graphemes`, matching the compiled spans.
struct TajweedAyahText: View {
    let example: TajweedExample
    let size: Double

    var body: some View {
        VStack(spacing: 8) {
            ayah
                .font(.custom(.uthmanicHafs, size: size, relativeTo: .title))
                .multilineTextAlignment(.center)
                .accessibilityLabel(example.ayah.map(\.text.text).joined(separator: " "))
            Text(verbatim: letters.joined(separator: " "))
                .font(.custom(.uthmanicHafs, size: size * 1.4, relativeTo: .title))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(letters.joined(separator: " "))
        }
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityElement(children: .combine)
    }

    /// The colored graphemes of each word the rule touches, in order.
    var letters: [String] {
        example.words.compactMap { word in
            guard let range = example.highlights[word.word], let graphemes = ArabicScript.graphemes(of: word.text.text) else { return nil }
            return graphemes.enumerated().filter { range.contains($0.offset) }.map(\.element.text).joined()
        }
    }

    private var ayah: Text {
        example.ayah.reduce(Text(verbatim: "")) { partial, item in
            guard let range = example.highlights[item.word], let graphemes = ArabicScript.graphemes(of: item.text.text) else {
                return partial + Text(verbatim: item.text.text + " ")
            }
            let word = graphemes.enumerated().reduce(Text(verbatim: "")) { word, pair in
                let piece = Text(verbatim: pair.element.text).underline()
                return word + (range.contains(pair.offset) ? piece.foregroundColor(.accentColor) : piece)
            }
            return partial + word + Text(verbatim: " ")
        }
    }
}
