//
//  Passage.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import QuranKit

/// An ayah range a person recites in one go, the unit review is scheduled by (roadmap §4).
public struct Passage: Hashable, Sendable {
    // MARK: Lifecycle

    /// `first` and `last` in either order.
    public init(_ first: AyahNumber, _ last: AyahNumber) {
        self.first = min(first, last)
        self.last = max(first, last)
    }

    // MARK: Public

    public let first: AyahNumber
    public let last: AyahNumber

    public var verses: [AyahNumber] {
        first.array(to: last)
    }
}

/// How well a passage is held, from its practice sessions.
public enum PassageStrength: Hashable, Sendable {
    /// Never graded.
    case unassessed
    /// Recently learned or forgotten: short intervals.
    case learning
    /// Last recited with help or mistakes.
    case weak
    /// Last recited correctly without help, on a review interval.
    case strong
}

/// A session's overall result, the rating its passage review gets.
public enum SessionGrade: Hashable, Sendable {
    case again
    case hard
    case good
}

/// What one practice session observed about one verse.
public struct VerseRecall: Hashable, Sendable {
    // MARK: Lifecycle

    public init(verse: AyahNumber, outcome: RecallOutcome, assistance: Int = 0, mistakenWords: [Int] = []) {
        self.verse = verse
        self.outcome = outcome
        self.assistance = assistance
        self.mistakenWords = mistakenWords
    }

    // MARK: Public

    public let verse: AyahNumber
    public let outcome: RecallOutcome
    /// Hints and peeks used in the verse.
    public let assistance: Int
    /// Word numbers (QUL numbering) marked as mistakes.
    public let mistakenWords: [Int]
}

/// A passage's state for the review queue.
public struct PassageProgress: Hashable, Sendable {
    public let passage: Passage
    public let strength: PassageStrength
    /// When the passage is next due; `nil` while unassessed.
    public let due: Date?
    public let gradedSessions: Int
    public let lastPracticed: Date?
    public let lastGrade: SessionGrade?
}
