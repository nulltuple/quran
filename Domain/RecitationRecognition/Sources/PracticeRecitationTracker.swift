//
//  PracticeRecitationTracker.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import QuranKit

/// Tracks live recitation through a Hifz practice stretch (roadmap V2b): each streaming window is
/// aligned within a bounded region around the current ayah (`WordAligner.alignWithin`), revealing
/// words monotonically as they are recited and advancing to the next ayah only once the current
/// ayah has been recited through its end (or matched before crossing into the next ayah).
///
/// Unlike `RecitationFollower` (which searches whole pages and jumps anywhere in the Quran), this
/// tracker uses the practice stretch as a strict prior: it never jumps ahead past an unrecited
/// ayah, never un-reveals words revealed manually (`sync`), and adapts its match threshold for
/// one-word and two-word ayahs.
public struct PracticeRecitationTracker: Sendable {
    public struct Update: Equatable, Sendable {
        /// Ayahs completed by this window, in recitation order.
        public let completedVerses: [AyahNumber]
        /// Canonical word count (QUL numbering) revealed in the current ayah after this update.
        public let revealedWords: Int
        /// Whether speaking windows have missed repeatedly (`missesBeforeOffTrack` in a row).
        public let isOffTrack: Bool
    }

    // MARK: Lifecycle

    /// `expected`: the canonical words of one monotonic practice stretch (in straight order, the
    /// remaining passage; in cumulative order, the remaining ayahs of the current step).
    public init(expected: [ExpectedWordText]) {
        self.expected = expected
        var verses: [AyahNumber] = []
        var ranges: [Range<Int>] = []
        for (index, unit) in expected.enumerated() {
            guard let verse = unit.words.first?.verse else { continue }
            if verses.last == verse {
                let lastIndex = ranges.count - 1
                ranges[lastIndex] = ranges[lastIndex].lowerBound ..< (index + 1)
            } else {
                verses.append(verse)
                ranges.append(index ..< (index + 1))
            }
        }
        self.verses = verses
        verseRanges = ranges
    }

    // MARK: Public

    /// Preceding units kept in the search region so an 8 s rolling window still aligns smoothly
    /// across ayah boundaries.
    public static let unitsBehind = 20
    /// Forward search bound within the current (and, near its end, next) ayah.
    public static let unitsAhead = 15
    /// Remaining units in the current ayah at or below which the immediately next ayah enters the
    /// search region so seamless crossing works across a 1 s hop.
    public static let lookaheadTriggerUnits = 4
    public static let minimumMatches = 2
    public static let missesBeforeOffTrack = 3

    public let expected: [ExpectedWordText]
    public let verses: [AyahNumber]
    public private(set) var currentVerseIndex = 0
    public private(set) var isOffTrack = false

    public var currentVerse: AyahNumber? {
        verses.indices.contains(currentVerseIndex) ? verses[currentVerseIndex] : nil
    }

    /// Canonical word number (QUL numbering) revealed so far in `currentVerse`, or 0.
    public var currentRevealedWords: Int {
        guard verseRanges.indices.contains(currentVerseIndex) else {
            return 0
        }
        let range = verseRanges[currentVerseIndex]
        let upper = min(revealedUnitEnd, range.upperBound)
        guard upper > range.lowerBound else {
            return 0
        }
        return expected[upper - 1].words.last?.wordNumber ?? 0
    }

    /// Synchronizes manual progress (for example `Next Word` or a manual advance) so live
    /// recitation never hides manually revealed words or repeats a verse already passed.
    public mutating func sync(verse: AyahNumber, revealedWords: Int) {
        guard let targetIndex = verses.firstIndex(of: verse) else {
            return
        }
        if targetIndex != currentVerseIndex {
            currentVerseIndex = targetIndex
            revealedUnitEnd = verseRanges[targetIndex].lowerBound
            matchedAnyInCurrentVerse = false
            misses = 0
            isOffTrack = false
        }
        let range = verseRanges[targetIndex]
        if revealedWords > 0 {
            for unitIndex in range {
                let unitMax = expected[unitIndex].words.map(\.wordNumber).max() ?? 0
                if unitMax <= revealedWords {
                    revealedUnitEnd = max(revealedUnitEnd, unitIndex + 1)
                }
            }
        }
    }

    /// Processes the recognized words of one streaming window.
    @discardableResult
    public mutating func update(with recognized: [RecognizedWord], isSpeaking: Bool = true) -> Update {
        guard !recognized.isEmpty, verseRanges.indices.contains(currentVerseIndex) else {
            return Update(completedVerses: [], revealedWords: currentRevealedWords, isOffTrack: isOffTrack)
        }

        let currentRange = verseRanges[currentVerseIndex]
        let anchor = max(revealedUnitEnd, currentRange.lowerBound)
        let lowerBound = max(0, anchor - Self.unitsBehind)
        var upperBound = min(currentRange.upperBound, anchor + Self.unitsAhead)
        let remainingInCurrent = currentRange.upperBound - anchor
        if currentVerseIndex + 1 < verseRanges.count,
           remainingInCurrent <= Self.lookaheadTriggerUnits || currentRange.count <= Self.lookaheadTriggerUnits
        {
            let nextRange = verseRanges[currentVerseIndex + 1]
            upperBound = min(nextRange.upperBound, currentRange.upperBound + Self.unitsAhead)
        }
        guard lowerBound < upperBound else {
            return Update(completedVerses: [], revealedWords: currentRevealedWords, isOffTrack: isOffTrack)
        }

        let passage = Array(expected[lowerBound ..< upperBound])
        let preferredEnd = anchor + 2 - lowerBound
        let requiredMatches = min(Self.minimumMatches, currentRange.count)
        let aligner = WordAligner()
        var fit = Fit(aligner.alignWithin(recognized, to: passage, preferredEnd: preferredEnd), recognizedCount: recognized.count)
        if fit.trailingUnmatched >= Self.minimumMatches, fit.trailingUnmatched < recognized.count {
            let tail = Array(recognized.suffix(fit.trailingUnmatched))
            let tailFit = Fit(aligner.alignWithin(tail, to: passage, preferredEnd: preferredEnd), recognizedCount: tail.count)
            if tailFit.accepts(requiredMatches: requiredMatches) {
                fit = tailFit
            }
        }

        if fit.accepts(requiredMatches: requiredMatches),
           let lastMatched = fit.lastMatched,
           let matchedSpan = fit.matchedSpan
        {
            let matchedEnd = lowerBound + lastMatched.upperBound
            let matchedGlobalSpan = (lowerBound + matchedSpan.lowerBound) ..< (lowerBound + matchedSpan.upperBound)
            let matchedCurrentInWindow = matchedGlobalSpan.overlaps(currentRange)

            // Reciting only words from an earlier ayah still echoing in the rolling window is fine,
            // not a miss, and does not advance the current ayah.
            if matchedEnd <= currentRange.lowerBound {
                misses = 0
                isOffTrack = false
                return Update(completedVerses: [], revealedWords: currentRevealedWords, isOffTrack: false)
            }

            // Never complete the current ayah if the reciter skipped straight to the next ayah
            // without matching any word of the current ayah.
            if matchedEnd > currentRange.upperBound, !matchedAnyInCurrentVerse, !matchedCurrentInWindow {
                recordMissIfSpeaking(recognized, isSpeaking: isSpeaking)
                return Update(completedVerses: [], revealedWords: currentRevealedWords, isOffTrack: isOffTrack)
            }

            if matchedCurrentInWindow {
                matchedAnyInCurrentVerse = true
            }
            if matchedEnd > revealedUnitEnd {
                revealedUnitEnd = matchedEnd
            }
            misses = 0
            isOffTrack = false

            var completed: [AyahNumber] = []
            while verseRanges.indices.contains(currentVerseIndex),
                  revealedUnitEnd >= verseRanges[currentVerseIndex].upperBound
            {
                completed.append(verses[currentVerseIndex])
                currentVerseIndex += 1
                if verseRanges.indices.contains(currentVerseIndex) {
                    matchedAnyInCurrentVerse = revealedUnitEnd > verseRanges[currentVerseIndex].lowerBound
                } else {
                    matchedAnyInCurrentVerse = false
                }
            }
            return Update(completedVerses: completed, revealedWords: currentRevealedWords, isOffTrack: false)
        }

        recordMissIfSpeaking(recognized, isSpeaking: isSpeaking)
        return Update(completedVerses: [], revealedWords: currentRevealedWords, isOffTrack: isOffTrack)
    }

    // MARK: Private

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
                    if let existing = matchedSpan {
                        matchedSpan = min(existing.lowerBound, step.expectedUnits.lowerBound) ..< max(existing.upperBound, step.expectedUnits.upperBound)
                    } else {
                        matchedSpan = step.expectedUnits
                    }
                }
                trailingUnmatched = step.kind == .matched ? 0 : trailingUnmatched + step.recognized.count
                recognizedIndex = indices.upperBound
            }
            requiredTailMatches = min(RecitationFollower.requiredTailMatches, recognizedCount)
        }

        // MARK: Internal

        var matches = 0
        var tailMatches = 0
        var lastMatched: Range<Int>?
        var matchedSpan: Range<Int>?
        var trailingUnmatched = 0
        let requiredTailMatches: Int

        func accepts(requiredMatches: Int) -> Bool {
            let effectiveTail = min(requiredTailMatches, requiredMatches)
            return matches >= requiredMatches && tailMatches >= effectiveTail && lastMatched != nil
        }
    }

    private let verseRanges: [Range<Int>]
    private var revealedUnitEnd = 0
    private var matchedAnyInCurrentVerse = false
    private var misses = 0

    private mutating func recordMissIfSpeaking(_ recognized: [RecognizedWord], isSpeaking: Bool) {
        if isSpeaking, !RecitationFollower.isOpening(recognized.suffix(RecitationFollower.tailLength)) {
            misses += 1
        }
        if misses >= Self.missesBeforeOffTrack {
            isOffTrack = true
        }
    }
}
