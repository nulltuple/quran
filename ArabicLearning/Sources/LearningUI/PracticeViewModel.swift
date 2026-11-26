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
/// It also runs the placement check, which asks unit checks in order and records the units the
/// learner places past.
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
        /// For a placement check, the units it placed the learner past (empty: start from the beginning).
        public var placedUnits: [String]?
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
        placement = nil
        do {
            async let loaded = loadGenerator()
            async let evidence = progress.evidence()
            async let due = progress.dueDates()
            async let placements = progress.placements()
            let ((curriculum, generator), loadedEvidence, loadedDue, loadedPlacements) = try await (loaded, evidence, due, placements)
            let date = now()
            let plan = SessionPlanner(graph: SkillGraph(curriculum: curriculum)).plan(
                profile: profile.presentation,
                evidence: loadedEvidence,
                dueReviews: loadedDue,
                placements: loadedPlacements,
                now: date
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

    /// Starts the placement check: unit checks in order, `PlacementTest`'s rules.
    public func startPlacement() async {
        state = .loading
        do {
            let (curriculum, generator) = try await loadGenerator()
            self.generator = generator
            placement = PlacementTest(curriculum: curriculum)
            seed = UInt64(now().timeIntervalSince1970)
            exercises = []
            position = 0
            summary = Summary(placedUnits: [])
            state = placementExercise().map(State.exercise) ?? .finished(summary)
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
            if var test = placement {
                let before = test.placedUnits
                test.record(outcomes.first ?? .unscorable)
                placement = test
                if test.placedUnits != before {
                    try await progress.recordPlacement(units: test.placedUnits, at: date)
                    summary.placedUnits = test.placedUnits
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
    private var placement: PlacementTest?
    private var generator: ExerciseGenerator?
    private var seed: UInt64 = 0

    private func next() -> State {
        position += 1
        if placement != nil {
            return placementExercise().map(State.exercise) ?? .finished(summary)
        }
        return position < exercises.count ? .exercise(exercises[position]) : .finished(summary)
    }

    /// The next placement exercise, appended to `exercises`; nil when the placement is over.
    private func placementExercise() -> Exercise? {
        guard let skill = placement?.current, let exercise = generator?.exercise(for: skill, seed: seed &+ UInt64(position)) else {
            return nil
        }
        exercises.append(exercise)
        return exercise
    }

    private func loadGenerator() async throws -> (Curriculum, ExerciseGenerator) {
        async let curriculum = content.curriculum()
        async let letters = content.letters()
        async let titles = content.skillTitles()
        async let clips = content.audioClips()
        async let strokes = content.strokeGuides()
        async let words = content.wordLetters()
        let (loadedCurriculum, loadedLetters, loadedTitles) = try await (curriculum, letters, titles)
        let (loadedClips, loadedStrokes, loadedWords) = try await (clips, strokes, words)
        let generator = ExerciseGenerator(
            letters: loadedLetters,
            skillTitles: loadedTitles,
            clips: loadedClips,
            strokes: loadedStrokes,
            words: loadedWords,
            checks: loadedCurriculum.checkRequirements
        )
        return (loadedCurriculum, generator)
    }
}
