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
        }
    }

    private func finishedView(_ summary: PracticeViewModel.Summary) -> some View {
        ContentUnavailableView {
            Label { Text("practice.done.title", bundle: .module) } icon: { NoorSystemImage.checkmark.image }
        } description: {
            Text(String(
                format: String(localized: "practice.done.text", bundle: .module),
                NumberFormatter.shared.format(summary.correct),
                NumberFormatter.shared.format(summary.correct + summary.incorrect)
            ))
        } actions: {
            Button(String(localized: "practice.again", bundle: .module)) { Task { await viewModel.start() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Renders one exercise: choice, match or explanation. `feedback` marks answers after grading.
struct ExerciseView: View {
    let exercise: Exercise
    let feedback: [AttemptOutcome]?
    let profile: PresentationProfile
    let respond: (ExerciseResponse) -> Void

    @ScaledMetric private var glyphSize = 44.0
    @State private var matchSelection: [Int: Int] = [:]
    @State private var selectedLeft: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                prompt
                switch exercise.kind {
                case .choice(let options, let answer):
                    choice(options, answer: answer)
                case .match(let left, let right, let answers):
                    match(left: left, right: right, answers: answers)
                case .explanation:
                    Button(String(localized: "practice.continue", bundle: .module)) { respond(.acknowledged) }
                        .buttonStyle(.borderedProminent)
                }
                if feedback == nil, exercise.kind != .explanation {
                    Button(String(localized: "practice.skip", bundle: .module)) { respond(.skipped) }
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
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
        case .matchLettersToNames:
            Text("exercise.matchLettersToNames", bundle: .module).font(.title2)
        case .explanation(let text):
            Text(text).font(.title2).multilineTextAlignment(.center)
        }
    }

    private func arabic(_ text: String) -> some View {
        Text(text)
            .font(.custom(.uthmanicHafs, size: glyphSize * 2, relativeTo: .largeTitle))
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityLabel(text)
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
                .disabled(feedback != nil)
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
            .disabled(feedback != nil)
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
