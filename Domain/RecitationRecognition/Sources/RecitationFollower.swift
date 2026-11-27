//
//  RecitationFollower.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import QuranKit

/// Follows a reciter through a passage from streaming recognition (roadmap V2a): each update takes
/// the words recognized in the latest few seconds of audio, aligns them within the passage near
/// the place reached so far (`WordAligner.alignWithin`), and moves the place to the last word they
/// match.
///
/// A window moves the place only when it fits the passage where it ends: at least
/// `minimumMatches` matched words in all (`minimumMatchesToStart` before the first fit, when the
/// whole passage is searched), and at least two of its last four recognized words matched. A
/// window of recitation (`isSpeaking`) that does not fit is a miss, unless it is the basmala or the
/// isti'adha said before a sura or a passage; `missesBeforeLost` misses in a row lose the place
/// once there is one.
/// A window with no words (silence) changes nothing. The caller finds a lost place anew, for
/// example with `VerseMatcher`, and starts a new follower there.
public struct RecitationFollower: Sendable {
    public enum State: Equatable, Sendable {
        /// No window has fit the passage yet.
        case searching
        /// `word` is the latest canonical word recited.
        case following(Word)
        /// Recitation goes on but has not fit near the place for `missesBeforeLost` windows;
        /// `lastWord` is the last word followed.
        case lost(lastWord: Word?)
    }

    // MARK: Lifecycle

    /// `expected`: the canonical words of the passage, from where the reciter is likely to start
    /// (the page in view) onward.
    public init(expected: [ExpectedWordText]) {
        self.expected = expected
    }

    // MARK: Public

    /// Expected units searched behind and ahead of the place.
    public static let unitsBehind = 20
    public static let unitsAhead = 80
    /// When fewer than this many units are left after the place, append the next verses.
    public static let unitsToKeepAhead = 100
    /// The most units kept: older ones are dropped as the reciter moves on.
    public static let maximumUnits = 600
    public static let minimumMatches = 2
    public static let minimumMatchesToStart = 3
    public static let missesBeforeLost = 3

    public private(set) var expected: [ExpectedWordText]
    public private(set) var state: State = .searching
    /// The index in `expected` of the latest unit recited; nil before the first fit.
    public private(set) var position: Int?

    /// The passage ends close ahead of the place: append the verses after `expected`'s last.
    public var needsMoreText: Bool {
        expected.count - (position ?? 0) < Self.unitsToKeepAhead
    }

    /// The last verse of `expected`.
    public var lastVerse: AyahNumber? {
        expected.last?.words.last?.verse
    }

    /// The last `missesBeforeLost` windows of recitation did not fit: the place is lost, or, before
    /// the first fit, the reciter may be reciting another passage.
    public var hasMissedRepeatedly: Bool {
        misses >= Self.missesBeforeLost
    }

    /// The latest word followed, or nil before the first fit.
    public var word: Word? {
        position.flatMap { expected[$0].words.last }
    }

    /// Appends the passage's next units; drops the oldest beyond `maximumUnits`.
    public mutating func append(_ units: [ExpectedWordText]) {
        expected += units
        guard expected.count > Self.maximumUnits, let position else {
            return
        }
        let drop = min(expected.count - Self.maximumUnits, max(0, position - Self.unitsBehind))
        expected.removeFirst(drop)
        self.position = position - drop
    }

    /// Follows the words of the latest window (their frames are not used) and returns the new state.
    /// `isSpeaking`: the window's latest audio is louder than the room (`SpeechLevel`); a window
    /// that doesn't fit counts as a miss only then, since the model can hear a pause in a noisy
    /// room as a few words.
    @discardableResult
    public mutating func update(with recognized: [RecognizedWord], isSpeaking: Bool = true) -> State {
        guard !recognized.isEmpty, !expected.isEmpty else {
            return state
        }
        let region: Range<Int> = if let position {
            max(0, position - Self.unitsBehind) ..< min(expected.count, position + Self.unitsAhead + 1)
        } else {
            0 ..< expected.count
        }
        // Between two windows a reciter says a word or two: prefer places just past the last one.
        let preferredEnd = (position ?? -1) + 2 - region.lowerBound
        let passage = Array(expected[region])
        let requiredMatches = position == nil ? Self.minimumMatchesToStart : Self.minimumMatches
        var fit = Fit(WordAligner().alignWithin(recognized, to: passage, preferredEnd: preferredEnd), recognizedCount: recognized.count)
        // A window that ends on words that don't fit may end on a phrase the reciter went back (or
        // ahead) to: one alignment keeps the passage's order, so it can't hold both places.
        if fit.trailingUnmatched >= Self.minimumMatches, fit.trailingUnmatched < recognized.count {
            let tail = Array(recognized.suffix(fit.trailingUnmatched))
            let tailFit = Fit(WordAligner().alignWithin(tail, to: passage, preferredEnd: preferredEnd), recognizedCount: tail.count)
            if tailFit.accepts(requiredMatches: requiredMatches) {
                fit = tailFit
            }
        }

        if fit.accepts(requiredMatches: requiredMatches), let lastMatched = fit.lastMatched {
            let position = region.lowerBound + lastMatched.upperBound - 1
            self.position = position
            misses = 0
            if let word = expected[position].words.last {
                state = .following(word)
            }
            return state
        }

        if isSpeaking, !Self.isOpening(recognized.suffix(Self.tailLength)) {
            misses += 1
        }
        // Before the first fit there is no place to lose: room noise before the recitation starts
        // keeps searching (`hasMissedRepeatedly` lets the caller look elsewhere).
        if misses >= Self.missesBeforeLost, position != nil {
            state = .lost(lastWord: word)
        }
        return state
    }

    // MARK: Internal

    /// The recognized words at a window's end that must fit for the place to move.
    static let tailLength = 4
    static let requiredTailMatches = 2

    /// The basmala and the isti'adha, which a reciter says before a sura or a passage but which
    /// are not words of the passage (the basmala is a verse only in Al-Fatihah).
    static let openingWords: [[UInt16]] = "أعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم"
        .split(separator: " ")
        .map { WordAligner.letters(String($0)) }

    /// At least two of `words` are words of the basmala or the isti'adha.
    static func isOpening(_ words: some Collection<RecognizedWord>) -> Bool {
        let openingCount = words.count(where: { word in
            let letters = WordAligner.letters(word.text)
            return openingWords.contains { WordAligner.similarity(letters, $0) >= WordAligner.matchSimilarity }
        })
        return openingCount >= min(2, words.count)
    }

    // MARK: Private

    /// What one alignment of a window says about the place.
    private struct Fit {
        // MARK: Lifecycle

        init(_ steps: [WordAlignmentStep], recognizedCount: Int) {
            let tailStart = max(0, recognizedCount - RecitationFollower.tailLength)
            var recognizedIndex = 0
            for step in steps {
                let indices = recognizedIndex ..< recognizedIndex + step.recognized.count
                if step.kind == .matched, !step.expectedUnits.isEmpty {
                    matches += 1
                    tailMatches += indices.clamped(to: tailStart ..< recognizedCount).count
                    lastMatched = step.expectedUnits
                }
                trailingUnmatched = step.kind == .matched ? 0 : trailingUnmatched + step.recognized.count
                recognizedIndex = indices.upperBound
            }
            requiredTailMatches = min(RecitationFollower.requiredTailMatches, recognizedCount)
        }

        // MARK: Internal

        /// Matched steps.
        var matches = 0
        /// Recognized words among the window's last `tailLength` that matched.
        var tailMatches = 0
        /// The expected units of the last matched step.
        var lastMatched: Range<Int>?
        /// Recognized words after the last matched one.
        var trailingUnmatched = 0
        let requiredTailMatches: Int

        func accepts(requiredMatches: Int) -> Bool {
            matches >= requiredMatches && tailMatches >= requiredTailMatches && lastMatched != nil
        }
    }

    private var misses = 0
}
