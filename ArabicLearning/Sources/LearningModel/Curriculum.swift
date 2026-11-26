//
//  Curriculum.swift
//  ArabicLearning (Arabican app)
//

import ArabicScript
import QuranKit
import QuranText

/// A letter with its teaching facts (name, sound, shape family) from the compiled content.
public struct LetterInfo: Hashable, Sendable {
    public init(letter: ArabicLetter, ordinal: Int, name: String, sound: String, family: String, forms: [LetterForm]) {
        self.letter = letter
        self.ordinal = ordinal
        self.name = name
        self.sound = sound
        self.family = family
        self.forms = forms
    }

    public let letter: ArabicLetter
    /// Position in teaching order, from 1.
    public let ordinal: Int
    public let name: String
    public let sound: String
    public let family: String
    public let forms: [LetterForm]
}

public struct Lesson: Identifiable, Hashable, Sendable {
    public init(id: String, unit: String, ordinal: Int, title: String, teaches: [SkillID], requires: [SkillID]) {
        self.id = id
        self.unit = unit
        self.ordinal = ordinal
        self.title = title
        self.teaches = teaches
        self.requires = requires
    }

    public let id: String
    public let unit: String
    /// Position in the curriculum, from 1.
    public let ordinal: Int
    public let title: String
    public let teaches: [SkillID]
    public let requires: [SkillID]
}

public struct LearningUnit: Identifiable, Hashable, Sendable {
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public let id: String
    public let title: String
}

/// Units and lessons in order, and the skill prerequisite graph (a DAG, validated by the content
/// compiler).
public struct Curriculum: Hashable, Sendable {
    public init(units: [LearningUnit], lessons: [Lesson], prerequisites: [SkillID: Set<SkillID>]) {
        self.units = units
        self.lessons = lessons
        self.prerequisites = prerequisites
    }

    public let units: [LearningUnit]
    public let lessons: [Lesson]
    /// The skills each skill directly depends on. Skills with none are absent.
    public let prerequisites: [SkillID: Set<SkillID>]

    /// The lessons of `unit`, in order.
    public func lessons(in unit: LearningUnit) -> [Lesson] {
        lessons.filter { $0.unit == unit.id }
    }

    /// Each unit check (`check.<unit>`) with the skills it requires, sorted by id: the skills
    /// whose exercises the check asks.
    public var checkRequirements: [SkillID: [SkillID]] {
        prerequisites.filter { $0.key.family == "check" }.mapValues { $0.sorted { $0.rawValue < $1.rawValue } }
    }

    /// Every skill some lesson teaches, in lesson order.
    public var taughtSkills: [SkillID] {
        lessons.flatMap(\.teaches)
    }
}

/// One canonical Quran word as written in the Uthmani text, byte for byte.
public struct QuranWordText: Hashable, Sendable {
    public init(word: Word, text: QuranText, sharesToken: Bool) {
        self.word = word
        self.text = text
        self.sharesToken = sharesToken
    }

    public let word: Word
    public let text: QuranText
    /// The text writes this word and a neighbor as one token (for example `لَّوۡمَا`, 15:7).
    public let sharesToken: Bool
}
