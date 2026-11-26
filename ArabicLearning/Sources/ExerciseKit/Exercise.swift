//
//  Exercise.swift
//  ArabicLearning (Arabican app)
//

import ArabicScript
import LearningEngine
import LearningModel

/// What the learner is asked. The UI turns these into localized sentences.
public enum ExercisePrompt: Hashable, Sendable {
    /// "Which letter is <name>?"; options are letters.
    case findLetterNamed(String)
    /// "Which sound does this letter write?"; options are sounds.
    case soundOfLetter(ArabicLetter)
    /// "Which letter is this?", shown in a positional form; options are isolated letters.
    case letterInForm(ArabicLetter, LetterForm)
    /// "Which letter writes <sound>?"; options are letters that are easy to confuse.
    case letterForSound(String)
    /// Match each letter to its name.
    case matchLettersToNames
    /// An explanation to read; continuing counts as done.
    case explanation(String)
}

public struct Exercise: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// One correct option.
        case choice(options: [String], answer: Int)
        /// Pairs to match; `right` is shuffled, `answers[i]` is the index in `right` for `left[i]`.
        case match(left: [String], right: [String], answers: [Int])
        case explanation
    }

    public init(skills: [SkillID], prompt: ExercisePrompt, kind: Kind) {
        self.skills = skills
        self.prompt = prompt
        self.kind = kind
    }

    /// The skills this exercise gives evidence for: one for choice and explanation, one per pair for match.
    public let skills: [SkillID]
    public let prompt: ExercisePrompt
    public let kind: Kind
}

public enum ExerciseResponse: Hashable, Sendable {
    case choice(Int)
    /// For each left item, the chosen index in `right`.
    case match([Int])
    case acknowledged
    case skipped
}

public enum ExerciseGrader {
    /// One outcome per `exercise.skills` entry. Skipping is unscorable, never wrong.
    public static func grade(_ exercise: Exercise, _ response: ExerciseResponse) -> [AttemptOutcome] {
        switch (exercise.kind, response) {
        case (_, .skipped):
            return exercise.skills.map { _ in .unscorable }
        case (.choice(_, let answer), .choice(let chosen)):
            return [chosen == answer ? .correct : .incorrect]
        case (.match(_, _, let answers), .match(let chosen)) where chosen.count == answers.count:
            return zip(answers, chosen).map { $0 == $1 ? .correct : .incorrect }
        case (.explanation, .acknowledged):
            return [.correct]
        default:
            return exercise.skills.map { _ in .unscorable }
        }
    }
}
