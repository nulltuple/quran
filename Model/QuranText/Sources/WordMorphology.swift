//
//  WordMorphology.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import QuranKit

/// A word's morphology from the Quranic Arabic Corpus, on canonical word numbers (roadmap C2).
public struct WordMorphology: Hashable, Sendable {
    public init(word: Word, segments: [MorphologySegment]) {
        self.word = word
        self.segments = segments
    }

    public let word: Word
    /// The word's parts in reading order: prefixes, one or more stems, suffixes.
    public let segments: [MorphologySegment]

    /// The segment that carries the word's meaning: its first stem with a root, else its first stem.
    public var headSegment: MorphologySegment? {
        let stems = segments.filter { $0.grammar.role == .stem }
        return stems.first { $0.root != nil } ?? stems.first
    }
}

/// One part of a word: a prefix (`وَ`, `ٱلْ`), a stem, or a suffix (a pronoun).
public struct MorphologySegment: Hashable, Sendable {
    public init(text: String, grammar: WordGrammar, lemma: WordLemma?, root: WordRoot?) {
        self.text = text
        self.grammar = grammar
        self.lemma = lemma
        self.root = root
    }

    /// The segment's Arabic text as the corpus writes it; an elided suffix is empty.
    public let text: String
    public let grammar: WordGrammar
    public let lemma: WordLemma?
    public let root: WordRoot?
}

/// A dictionary form. The corpus spells a few lemmas the same under two roots; `id` keeps them apart.
public struct WordLemma: Hashable, Sendable {
    public init(id: Int, text: String, occurrences: Int) {
        self.id = id
        self.text = text
        self.occurrences = occurrences
    }

    public let id: Int
    public let text: String
    /// How many segments in the Quran have this lemma, as the corpus counts.
    public let occurrences: Int
}

/// A root, usually three letters.
public struct WordRoot: Hashable, Sendable {
    public init(id: Int, letters: String, occurrences: Int) {
        self.id = id
        self.letters = letters
        self.occurrences = occurrences
    }

    public let id: Int
    /// The root letters without spaces, as the corpus writes them (`حمد`).
    public let letters: String
    /// How many segments in the Quran have this root, as the corpus counts (ح م د: 68).
    public let occurrences: Int

    /// The letters separated by spaces (`ح م د`), the way roots are usually shown.
    public var spacedLetters: String {
        letters.map(String.init).joined(separator: " ")
    }
}

/// A segment's grammar, decoded from corpus tags by `Tools/build-quran-morphology.py`, which
/// rejects any tag it does not know. Every field the corpus leaves out is `nil`.
public struct WordGrammar: Hashable, Sendable {
    public enum Part: String, Sendable {
        case noun = "N"
        case verb = "V"
        case particle = "P"
    }

    public enum Role: String, Sendable {
        case prefix
        case stem
        case suffix
    }

    public enum Gender: String, Sendable {
        case masculine = "M"
        case feminine = "F"
    }

    public enum Number: String, Sendable {
        case singular = "S"
        case dual = "D"
        case plural = "P"
    }

    public enum Aspect: String, Sendable {
        case perfect = "PERF"
        case imperfect = "IMPF"
        case imperative = "IMPV"
    }

    public enum Voice: String, Sendable {
        case active
        case passive
    }

    public enum Mood: String, Sendable {
        case indicative = "IND"
        case subjunctive = "SUBJ"
        case jussive = "JUS"
    }

    public enum Case: String, Sendable {
        case nominative = "NOM"
        case accusative = "ACC"
        case genitive = "GEN"
    }

    /// The verbs and particles that govern like كَانَ, إِنَّ and كَادَ.
    public enum Family: String, Sendable {
        case kana
        case inna
        case kada
    }

    public init(
        part: Part,
        tag: String,
        derivation: String? = nil,
        role: Role,
        person: Int? = nil,
        gender: Gender? = nil,
        number: Number? = nil,
        verbForm: Int? = nil,
        aspect: Aspect? = nil,
        voice: Voice? = nil,
        mood: Mood? = nil,
        grammaticalCase: Case? = nil,
        isIndefinite: Bool = false,
        family: Family? = nil
    ) {
        self.part = part
        self.tag = tag
        self.derivation = derivation
        self.role = role
        self.person = person
        self.gender = gender
        self.number = number
        self.verbForm = verbForm
        self.aspect = aspect
        self.voice = voice
        self.mood = mood
        self.grammaticalCase = grammaticalCase
        self.isIndefinite = isIndefinite
        self.family = family
    }

    public let part: Part
    /// The corpus part-of-speech tag: `N` (noun), `PN`, `PRON`, `ADJ`, ... for nouns, `V` for verbs,
    /// `P` (preposition), `CONJ`, `DET`, ... for particles.
    public let tag: String
    /// For nouns derived from verbs: `ACT_PCPL`, `PASS_PCPL` or `VN`.
    public let derivation: String?
    public let role: Role
    /// 1, 2 or 3.
    public let person: Int?
    public let gender: Gender?
    public let number: Number?
    /// Verb form I to XII (1...12).
    public let verbForm: Int?
    public let aspect: Aspect?
    public let voice: Voice?
    public let mood: Mood?
    public let grammaticalCase: Case?
    public let isIndefinite: Bool
    public let family: Family?
}

/// What a word-study occurrence list is for: every word with a lemma, or with a root.
public enum WordStudyTerm: Hashable, Sendable {
    case lemma(WordLemma)
    case root(WordRoot)

    /// How many times the corpus counts the term in the Quran.
    public var occurrences: Int {
        switch self {
        case .lemma(let lemma): lemma.occurrences
        case .root(let root): root.occurrences
        }
    }
}
