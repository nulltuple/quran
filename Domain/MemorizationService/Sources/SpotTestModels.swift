//
//  SpotTestModels.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import QuranKit

/// Curated spot-test presets (roadmap H4).
public enum SpotTestPreset: String, CaseIterable, Hashable, Codable, Sendable {
    /// Strong, well-held passages to build confidence (falls back to all memorized if none strong yet).
    case warmUp
    /// Passages currently weak or in learning/relearning.
    case weakest
    /// Passages currently due in the review queue.
    case due
    /// Recently practiced or declared passages (within 14 days).
    case recent
    /// Longest-unpracticed or older memorized passages (more than 14 days old).
    case old
}

/// Where spot-test questions are sampled from.
public enum SpotTestSource: Hashable, Sendable {
    /// Union of all declared memorized ranges and practiced passages.
    case memorized
    /// User-selected canonical ranges (may be non-contiguous).
    case custom(AyahRangeSet)
    /// One of the curated presets derived from memorization history.
    case preset(SpotTestPreset)
}

/// How long each sampled spot-test question spans.
public enum SpotTestQuestionLength: Hashable, Codable, Sendable {
    case ayahs(Int)
    case lines(Int)

    // MARK: Public

    public static let ayahBounds = 1 ... 30
    public static let lineBounds = 1 ... 15

    public var clamped: Self {
        switch self {
        case .ayahs(let value):
            .ayahs(min(max(value, Self.ayahBounds.lowerBound), Self.ayahBounds.upperBound))
        case .lines(let value):
            .lines(min(max(value, Self.lineBounds.lowerBound), Self.lineBounds.upperBound))
        }
    }
}

/// Whether the spot test runs for a fixed number of questions or a countdown timer.
public enum SpotTestLimit: Hashable, Codable, Sendable {
    case count(Int)
    case timer(seconds: Int)

    // MARK: Public

    public static let countBounds = 1 ... 50
    public static let timerSecondsBounds = 60 ... 3600

    public var clamped: Self {
        switch self {
        case .count(let value):
            .count(min(max(value, Self.countBounds.lowerBound), Self.countBounds.upperBound))
        case .timer(let seconds):
            .timer(seconds: min(max(seconds, Self.timerSecondsBounds.lowerBound), Self.timerSecondsBounds.upperBound))
        }
    }
}

/// What prompt starts each spot-test question before the user reveals or asks for hints.
public enum SpotTestStartCue: String, CaseIterable, Hashable, Codable, Sendable {
    case firstWord
    case firstTwoWords
    case firstAyah
    case referenceOnly
}

/// Full configuration for a seeded spot test (roadmap H4).
public struct SpotTestConfiguration: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        source: SpotTestSource = .memorized,
        questionLength: SpotTestQuestionLength = .ayahs(3),
        limit: SpotTestLimit = .count(5),
        startCue: SpotTestStartCue = .firstTwoWords,
        hideLocation: Bool = false,
        isTemporary: Bool = false,
        seed: UInt64 = UInt64.random(in: 1 ... UInt64.max)
    ) {
        self.source = source
        self.questionLength = questionLength.clamped
        self.limit = limit.clamped
        self.startCue = startCue
        self.hideLocation = hideLocation
        self.isTemporary = isTemporary
        self.seed = seed
    }

    // MARK: Public

    public var source: SpotTestSource
    public var questionLength: SpotTestQuestionLength
    public var limit: SpotTestLimit
    public var startCue: SpotTestStartCue
    public var hideLocation: Bool
    /// When `true`, results are scored and displayed but never persisted to memorization history.
    public var isTemporary: Bool
    /// Seed driving deterministic question sampling.
    public var seed: UInt64

    /// When location is hidden, `referenceOnly` would leave an empty prompt, so fall back to `firstWord`.
    public var effectiveStartCue: SpotTestStartCue {
        if hideLocation, startCue == .referenceOnly {
            return .firstWord
        }
        return startCue
    }
}

/// Exact Mushaf page and line span of one verse, supplied by the caller from word-frame geometry.
public struct VerseLineSpan: Hashable, Sendable {
    // MARK: Lifecycle

    public init(page: Int, firstLine: Int, lastLine: Int) {
        self.page = page
        self.firstLine = min(firstLine, lastLine)
        self.lastLine = max(firstLine, lastLine)
    }

    // MARK: Public

    public let page: Int
    public let firstLine: Int
    public let lastLine: Int
}

/// One sampled spot-test question.
public struct SpotTestQuestion: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(id: Int, passage: Passage, targetLineCount: Int? = nil) {
        self.id = id
        self.passage = passage
        verses = passage.verses
        self.targetLineCount = targetLineCount
    }

    // MARK: Public

    public let id: Int
    public let passage: Passage
    public let verses: [AyahNumber]
    /// Number of Mushaf lines spanned when sampled in `.lines` mode; `nil` in `.ayahs` mode.
    public let targetLineCount: Int?
}

/// Per-verse grading outcome inside a spot-test question.
public struct SpotTestVerseOutcome: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        verse: AyahNumber,
        totalWords: Int,
        outcome: RecallOutcome,
        assistance: Int = 0,
        mistakenWords: Set<Int> = []
    ) {
        self.verse = verse
        self.totalWords = max(0, totalWords)
        self.outcome = outcome
        self.assistance = max(0, assistance)
        self.mistakenWords = mistakenWords
    }

    // MARK: Public

    public let verse: AyahNumber
    public let totalWords: Int
    public let outcome: RecallOutcome
    public let assistance: Int
    public let mistakenWords: Set<Int>

    /// Number of target words assessed for this verse (0 when skipped).
    public var assessedWords: Int {
        outcome == .skipped ? 0 : totalWords
    }

    /// Number of words recalled cleanly for this verse.
    public var recalledWords: Int {
        switch outcome {
        case .skipped, .revealed:
            return 0
        case .mistake:
            let missedCount = mistakenWords.isEmpty ? min(totalWords, 1) : min(totalWords, mistakenWords.count)
            return max(0, totalWords - missedCount)
        case .correct, .hint, .selfCorrected:
            return max(0, totalWords - min(totalWords, mistakenWords.count))
        }
    }
}

/// Graded or skipped result of one spot-test question.
public struct SpotTestQuestionResult: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        question: SpotTestQuestion,
        verseOutcomes: [SpotTestVerseOutcome],
        skipped: Bool = false,
        hintsUsed: Int? = nil
    ) {
        self.question = question
        self.verseOutcomes = verseOutcomes
        self.skipped = skipped
        let verseHints = verseOutcomes.reduce(0) { $0 + $1.assistance }
        self.hintsUsed = max(hintsUsed ?? verseHints, verseHints)
    }

    // MARK: Public

    public let question: SpotTestQuestion
    public let verseOutcomes: [SpotTestVerseOutcome]
    public let skipped: Bool
    public let hintsUsed: Int

    public var id: Int { question.id }

    /// Whether the question was attempted and graded (not skipped).
    public var isAssessed: Bool {
        !skipped && verseOutcomes.contains { $0.outcome != .skipped }
    }

    /// Strict Hifz pass: assessed, zero hints/assistance, every verse correct with no mistakes.
    public var isStrictPerfect: Bool {
        guard isAssessed, hintsUsed == 0 else { return false }
        return verseOutcomes.allSatisfy {
            $0.outcome == .correct && $0.assistance == 0 && $0.mistakenWords.isEmpty
        }
    }

    /// Whether any hint, word peek, or full reveal was used on an assessed question.
    public var neededAssistance: Bool {
        guard isAssessed else { return false }
        return hintsUsed > 0 || verseOutcomes.contains {
            $0.assistance > 0 || $0.outcome == .hint || $0.outcome == .revealed
        }
    }

    /// Count of verses in this question graded `.revealed` (forgot).
    public var revealedVerseCount: Int {
        guard isAssessed else { return 0 }
        return verseOutcomes.count(where: { $0.outcome == .revealed })
    }

    public var assessedWords: Int {
        guard isAssessed else { return 0 }
        return verseOutcomes.reduce(0) { $0 + $1.assessedWords }
    }

    public var recalledWords: Int {
        guard isAssessed else { return 0 }
        return verseOutcomes.reduce(0) { $0 + $1.recalledWords }
    }
}
