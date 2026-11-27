//
//  PracticePlan.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranKit

/// The order a passage's ayahs are practiced in (roadmap H2, slice b).
public enum PracticeOrder: String, Codable, Hashable, Sendable, CaseIterable {
    /// Each ayah once, first to last.
    case straight
    /// Each new ayah alone, then every ayah so far together: A, B, A+B, C, A+B+C …
    case cumulative
}

/// How many words stay visible as cues inside the hidden ayahs (progressive masking, roadmap H2).
/// The levels are deterministic, so the same page looks the same every session.
public enum PracticeCueLevel: String, Codable, Hashable, Sendable, CaseIterable {
    /// Every other word shows (the 1st, 3rd, 5th …): for an ayah being learned.
    case alternateWords
    /// Each ayah's first word shows: the usual cue for revising.
    case firstWord
    /// Nothing shows until asked.
    case none

    // MARK: Public

    /// The visible word numbers (QUL numbering) of an ayah of `wordCount` words.
    public func cueWords(wordCount: Int) -> [Int] {
        guard wordCount > 0 else {
            return []
        }
        switch self {
        case .alternateWords: return Array(stride(from: 1, through: wordCount, by: 2))
        case .firstWord: return [1]
        case .none: return []
        }
    }
}

/// One stretch recited from memory in one go: a single ayah, or (cumulative) the ayahs so far.
public struct PracticeStep: Hashable, Sendable {
    public let verses: [AyahNumber]

    /// Whether the step goes back over ayahs already practiced alone.
    public var isReview: Bool {
        verses.count > 1
    }
}

public enum PracticePlan {
    /// The steps that practice `verses` (in Quran order) in `order`.
    ///
    /// Cumulative practice of n ayahs has 2n − 1 steps and recites 1 + (n − 1)(n + 4) / 2 ayahs, so it suits
    /// a few new ayahs rather than a whole page.
    public static func steps(for verses: [AyahNumber], order: PracticeOrder) -> [PracticeStep] {
        let verses = verses.sorted()
        switch order {
        case .straight:
            return verses.map { PracticeStep(verses: [$0]) }
        case .cumulative:
            var steps: [PracticeStep] = []
            for index in verses.indices {
                steps.append(PracticeStep(verses: [verses[index]]))
                if index > 0 {
                    steps.append(PracticeStep(verses: Array(verses[...index])))
                }
            }
            return steps
        }
    }
}
