//
//  PracticeViewModel.swift
//  ArabicLearning (Arabican app)
//

import ExerciseKit
import Foundation
import LearningContent
import LearningEngine
import LearningModel
import LearningPersistence
import Observation

/// Runs one practice session: plans it, generates exercises, grades answers and records evidence.
@MainActor
@Observable
public final class PracticeViewModel {
    // MARK: Lifecycle

    public init(
        profile: LearnerProfile,
        content: LearningContentStore,
        progress: ProgressStore,
        scheduler: ReviewScheduler = ReviewScheduler(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.profile = profile
        self.content = content
        self.progress = progress
        self.scheduler = scheduler
        self.now = now
    }

    // MARK: Public

    public struct Summary: Equatable, Sendable {
        public var correct = 0
        public var incorrect = 0
        public var unscorable = 0
    }

    public enum State: Equatable {
        case idle
        case loading
        case exercise(Exercise)
        case feedback(Exercise, outcomes: [AttemptOutcome])
        case finished(Summary)
        case failed
    }

    public let profile: LearnerProfile
    public private(set) var state: State = .idle
    public private(set) var position = 0
    public private(set) var exercises: [Exercise] = []

    public func start() async {
        state = .loading
        do {
            async let curriculum = content.curriculum()
            async let letters = content.letters()
            async let evidence = progress.evidence()
            async let due = progress.dueDates()
            async let titles = content.skillTitles()
            async let clips = content.audioClips()
            async let strokes = content.strokeGuides()
            async let words = content.wordLetters()
            let (loadedCurriculum, loadedLetters, loadedEvidence, loadedDue, loadedTitles) =
                try await (curriculum, letters, evidence, due, titles)
            let (loadedClips, loadedStrokes, loadedWords) = try await (clips, strokes, words)
            let date = now()
            let plan = SessionPlanner(graph: SkillGraph(curriculum: loadedCurriculum))
                .plan(profile: profile.presentation, evidence: loadedEvidence, dueReviews: loadedDue, now: date)
            let generator = ExerciseGenerator(
                letters: loadedLetters,
                skillTitles: loadedTitles,
                clips: loadedClips,
                strokes: loadedStrokes,
                words: loadedWords
            )
            let seed = UInt64(date.timeIntervalSince1970)
            var built = plan.enumerated().compactMap { index, item in
                generator.exercise(for: item.skill, seed: seed &+ UInt64(index))
            }
            let newLetters = plan.filter { $0.reason == .newLesson }.map(\.skill)
            if let match = generator.matchExercise(for: newLetters, seed: seed), newLetters.count >= 3 {
                built.append(match)
            }
            exercises = built
            position = 0
            summary = Summary()
            state = built.first.map(State.exercise) ?? .finished(summary)
        } catch {
            state = .failed
        }
    }

    public func answer(_ response: ExerciseResponse) async {
        guard case .exercise(let exercise) = state else { return }
        let outcomes = ExerciseGrader.grade(exercise, response)
        let date = now()
        do {
            for (skill, outcome) in zip(exercise.skills, outcomes) {
                try await progress.record(outcome, for: skill, at: date, scheduler: scheduler)
                switch outcome {
                case .correct: summary.correct += 1
                case .incorrect: summary.incorrect += 1
                case .unscorable: summary.unscorable += 1
                }
            }
        } catch {
            state = .failed
            return
        }
        state = exercise.kind == .explanation || response == .skipped ? next() : .feedback(exercise, outcomes: outcomes)
    }

    public func advance() {
        guard case .feedback = state else { return }
        state = next()
    }

    // MARK: Private

    private let content: LearningContentStore
    private let progress: ProgressStore
    private let scheduler: ReviewScheduler
    private let now: @Sendable () -> Date
    private var summary = Summary()

    private func next() -> State {
        position += 1
        return position < exercises.count ? .exercise(exercises[position]) : .finished(summary)
    }
}
