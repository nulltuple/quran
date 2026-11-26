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
    /// "Listen. Which letter is it?" The exercise's audio plays; options are letters.
    case listenForLetter
    /// "Which of these letters is in this word?" Options are isolated letters; only one appears in
    /// the word, written plainly.
    case letterInWord(QuranWordText)
    /// "Trace the letter" over its stroke guide.
    case traceLetter(ArabicLetter)
    /// "Listen. Which one is it?" The exercise's audio plays; options are syllables (a letter with
    /// a vowel or sukun).
    case listenForSyllable
    /// "How is this read?" Options are recordings (`Kind.audioChoice`).
    case readSyllable(String)
    /// "Listen. Which word starts with this sound?" The audio is the first syllable; options are
    /// Quran words.
    case wordStartingWithSound
    /// "How does this word start?" Options are recordings of its first letter with each vowel.
    case firstSoundOfWord(QuranWordText)
    /// "Which letter of this word has <feature>?" Options are graphemes of the word.
    case markInWord(QuranWordText, ReadingFeature)
    /// Match each letter to its name.
    case matchLettersToNames
    /// An explanation to read; continuing counts as done.
    case explanation(String)
}

public struct Exercise: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// One correct option.
        case choice(options: [String], answer: Int)
        /// One correct recording; the learner plays them and picks one (answered with `.choice`).
        case audioChoice(options: [AudioClip], answer: Int)
        /// Pairs to match; `right` is shuffled, `answers[i]` is the index in `right` for `left[i]`.
        case match(left: [String], right: [String], answers: [Int])
        case explanation
        /// Trace the guide's strokes in order; graded by `TraceChecker`.
        case trace(guide: [GuideStroke])
    }

    public init(skills: [SkillID], prompt: ExercisePrompt, kind: Kind, audio: AudioClip? = nil) {
        self.skills = skills
        self.prompt = prompt
        self.kind = kind
        self.audio = audio
    }

    /// The skills this exercise gives evidence for: one for choice and explanation, one per pair for match.
    public let skills: [SkillID]

    /// The same exercise giving evidence for `skills` instead (a unit check asks a taught skill's
    /// exercise but scores the check).
    public func scoring(_ skills: [SkillID]) -> Exercise {
        Exercise(skills: skills, prompt: prompt, kind: kind, audio: audio)
    }

    public let prompt: ExercisePrompt
    public let kind: Kind
    /// A recording to play with the prompt (required for `listenForLetter`).
    public let audio: AudioClip?
}

public enum ExerciseResponse: Hashable, Sendable {
    case choice(Int)
    /// For each left item, the chosen index in `right`.
    case match([Int])
    case acknowledged
    /// The traced strokes, in drawing order, as canvas fractions.
    case trace([[CanvasPoint]])
    case skipped
}

public enum ExerciseGrader {
    /// One outcome per `exercise.skills` entry. Skipping is unscorable, never wrong.
    public static func grade(_ exercise: Exercise, _ response: ExerciseResponse) -> [AttemptOutcome] {
        switch (exercise.kind, response) {
        case (_, .skipped):
            return exercise.skills.map { _ in .unscorable }
        case (.choice(_, let answer), .choice(let chosen)), (.audioChoice(_, let answer), .choice(let chosen)):
            return [chosen == answer ? .correct : .incorrect]
        case (.match(_, _, let answers), .match(let chosen)) where chosen.count == answers.count:
            return zip(answers, chosen).map { $0 == $1 ? .correct : .incorrect }
        case (.explanation, .acknowledged):
            return [.correct]
        case (.trace(let guide), .trace(let drawn)):
            return [TraceChecker().check(drawn, against: guide) == .passed ? .correct : .incorrect]
        default:
            return exercise.skills.map { _ in .unscorable }
        }
    }
}
