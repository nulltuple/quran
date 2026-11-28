//
//  PracticeRecitationTracker.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import QuranKit

/// A live recitation mistake detected on a canonical word during hidden Hifz practice.
public struct LivePracticeMistake: Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Hashable, Sendable {
        /// A different word or grammatical inflection was recited in place of the expected word.
        case substitution
        /// The expected word was skipped while surrounding words were recited.
        case omitted
        /// Wrong words were spoken at this position before self-correcting.
        case stumble
        /// Repeated restarts of the preceding phrase while unable to recall this word.
        case hesitation
    }

    // MARK: Lifecycle

    public init(word: Word, kind: Kind, expectedText: String, recitedText: String) {
        self.word = word
        self.kind = kind
        self.expectedText = expectedText
        self.recitedText = recitedText
    }

    // MARK: Public

    public let word: Word
    public let kind: Kind
    public let expectedText: String
    public let recitedText: String

    public var id: Word { word }
}

/// Tracks live recitation through a Hifz practice stretch (roadmap V2b): each streaming window is
/// aligned within a bounded region around the current ayah (`WordAligner.alignWithin`), revealing
/// words monotonically as they are recited, detecting real-time mistakes (substitutions including
/// grammatical inflections, omissions, stumbles, and hesitations), and advancing to the next ayah
/// once the current ayah has been recited through its end.
///
/// Unlike `RecitationFollower` (which searches whole pages and jumps anywhere in the Quran), this
/// tracker uses the practice stretch as a strict prior: it never jumps ahead past an unrecited
/// multi-word ayah, never un-reveals words revealed manually (`sync`), and adapts its match
/// threshold for one-word and two-word ayahs.
public struct PracticeRecitationTracker: Sendable {
    public struct Update: Equatable, Sendable {
        /// Ayahs completed by this window, in recitation order.
        public let completedVerses: [AyahNumber]
        /// Canonical word count (QUL numbering) revealed in the current ayah after this update.
        public let revealedWords: Int
        /// Whether speaking windows have missed repeatedly (`missesBeforeOffTrack` in a row).
        public let isOffTrack: Bool
        /// All active live mistakes detected so far in passage order.
        public let liveMistakes: [LivePracticeMistake]
        /// Mistakes newly detected in this update.
        public let newMistakes: [LivePracticeMistake]
        /// The latest canonical word revealed, or nil before any word is revealed.
        public let currentWord: Word?
        /// The next hidden word when a live stumble/hesitation was just detected on it, so the
        /// Mushaf can tint its hidden baseline red before it is revealed.
        public let pendingMistakeWord: Word?

        public init(
            completedVerses: [AyahNumber],
            revealedWords: Int,
            isOffTrack: Bool,
            liveMistakes: [LivePracticeMistake] = [],
            newMistakes: [LivePracticeMistake] = [],
            currentWord: Word? = nil,
            pendingMistakeWord: Word? = nil
        ) {
            self.completedVerses = completedVerses
            self.revealedWords = revealedWords
            self.isOffTrack = isOffTrack
            self.liveMistakes = liveMistakes
            self.newMistakes = newMistakes
            self.currentWord = currentWord
            self.pendingMistakeWord = pendingMistakeWord
        }
    }

    // MARK: Lifecycle

    /// `expected`: the canonical words of one monotonic practice stretch (in straight order, the
    /// remaining passage; in cumulative order, the remaining ayahs of the current step).
    public init(expected: [ExpectedWordText]) {
        self.expected = expected
        expectedLetters = expected.map { WordAligner.letters($0.text) }
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

    /// Preceding units kept in the search region so a rolling window aligns smoothly across ayah boundaries.
    public static let unitsBehind = 24
    /// Forward search bound within the current (and, near its end, next) ayah.
    public static let unitsAhead = 15
    /// Remaining units in the current ayah at or below which the immediately next ayah enters the
    /// search region so seamless crossing works across a hop.
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

    /// Total expected units revealed so far across the stretch.
    public var totalRevealedUnits: Int {
        revealedUnitEnd
    }

    /// All active mistakes detected so far in passage order.
    public var activeMistakes: [LivePracticeMistake] {
        mistakesByUnit.keys.sorted().compactMap { mistakesByUnit[$0] }
    }

    /// Active mistakes belonging to `verse`, in word order.
    public func mistakes(for verse: AyahNumber) -> [LivePracticeMistake] {
        activeMistakes.filter { $0.word.verse == verse }
    }

    /// Removes a detected mistake (for example when the user disputes it).
    public mutating func removeMistake(for word: Word) {
        for (unitIndex, mistake) in mistakesByUnit where mistake.word == word {
            mistakesByUnit.removeValue(forKey: unitIndex)
            confirmedClean.insert(unitIndex)
        }
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
                    confirmedClean.insert(unitIndex)
                }
            }
        }
    }

    /// Processes the recognized words of one streaming window.
    @discardableResult
    public mutating func update(with recognized: [RecognizedWord], isSpeaking: Bool = true) -> Update {
        guard !recognized.isEmpty, verseRanges.indices.contains(currentVerseIndex) else {
            return makeUpdate(completedVerses: [], newMistakes: [])
        }

        let currentRange = verseRanges[currentVerseIndex]
        let anchor = max(revealedUnitEnd, currentRange.lowerBound)
        let lowerBound = max(0, anchor - Self.unitsBehind)
        var upperBound = min(currentRange.upperBound, anchor + Self.unitsAhead)
        let remainingInCurrent = currentRange.upperBound - anchor
        if currentVerseIndex + 1 < verseRanges.count,
           remainingInCurrent <= Self.lookaheadTriggerUnits || currentRange.count <= Self.lookaheadTriggerUnits
        {
            // Walk across consecutive very short ayahs (such as 42:1 حٓمٓ + 42:2 عٓسٓقٓ) so the next
            // substantive ayah is always inside the lookahead window and the tracker never stalls.
            var lookaheadIndex = currentVerseIndex + 1
            while lookaheadIndex < verseRanges.count {
                let nextRange = verseRanges[lookaheadIndex]
                upperBound = min(nextRange.upperBound, anchor + Self.unitsAhead)
                if nextRange.count > 2 || upperBound >= anchor + Self.unitsAhead {
                    break
                }
                lookaheadIndex += 1
            }
        }
        guard lowerBound < upperBound else {
            return makeUpdate(completedVerses: [], newMistakes: [])
        }

        let passage = Array(expected[lowerBound ..< upperBound])
        let preferredEnd = anchor + 1 - lowerBound
        let requiredMatches = min(Self.minimumMatches, currentRange.count)
        let aligner = WordAligner()
        var steps = aligner.alignWithin(recognized, to: passage, preferredEnd: preferredEnd)
        var fit = Fit(steps, recognized: recognized, expected: passage)
        var realignedTail = false
        var newMistakes: [LivePracticeMistake] = []

        if fit.trailingUnmatched.count >= Self.minimumMatches, fit.trailingUnmatched.count < recognized.count {
            let tail = fit.trailingUnmatched
            let tailSteps = aligner.alignWithin(tail, to: passage, preferredEnd: preferredEnd)
            let tailFit = Fit(tailSteps, recognized: tail, expected: passage)
            if tailFit.accepts(requiredMatches: requiredMatches) {
                if isSpeaking,
                   revealedUnitEnd > 0,
                   revealedUnitEnd < expected.count,
                   let tailLast = tailFit.lastMatched
                {
                    let tailEnd = lowerBound + tailLast.upperBound
                    if tailEnd >= revealedUnitEnd - 2, tailEnd <= revealedUnitEnd {
                        restartVotes[revealedUnitEnd, default: 0] += 1
                        if restartVotes[revealedUnitEnd, default: 0] >= 3 {
                            let phrase = tail.prefix(3).map(\.text).joined(separator: " ")
                            if let added = recordMistake(unitIndex: revealedUnitEnd, kind: .hesitation, recitedText: phrase) {
                                newMistakes.append(added)
                            }
                        }
                    }
                }
                steps = tailSteps
                fit = tailFit
                realignedTail = true
            }
        }

        // Check 1: Live stumble when wrong words sit directly at the next unrevealed word.
        if isSpeaking,
           revealedUnitEnd > 0,
           revealedUnitEnd < expected.count,
           !realignedTail,
           !fit.trailingUnmatched.isEmpty,
           !RecitationFollower.isOpening(fit.trailingUnmatched)
        {
            let recentExpected = (max(0, revealedUnitEnd - 5) ..< revealedUnitEnd).map { expectedLetters[$0] }
            let upcomingExpected = (revealedUnitEnd ..< min(expected.count, revealedUnitEnd + 2)).map { expectedLetters[$0] }
            let wrong = fit.trailingUnmatched.filter { word in
                let letters = WordAligner.letters(word.text)
                guard letters.count >= 2 else { return false }
                if recentExpected.contains(where: { WordAligner.similarity(letters, $0) >= 0.65 }) { return false }
                if upcomingExpected.contains(where: { WordAligner.similarity(letters, $0) >= 0.65 }) { return false }
                return (word.meanConfidence ?? 1) >= 0.60
            }
            let hasStumble = wrong.count >= 2 || (
                wrong.count == 1
                    && WordAligner.letters(wrong[0].text).count >= 4
                    && (wrong[0].confidence ?? 1) >= 0.65
            )
            if hasStumble {
                let phrase = wrong.prefix(3).map(\.text).joined(separator: " ")
                stumbleVotes[revealedUnitEnd, default: 0] += 1
                if stumbleVotes[revealedUnitEnd, default: 0] >= 2 {
                    if let added = recordMistake(unitIndex: revealedUnitEnd, kind: .stumble, recitedText: phrase) {
                        newMistakes.append(added)
                    }
                }
            }
        }

        let singleNextWordMatch = if revealedUnitEnd > 0,
                                     fit.matches >= 1,
                                     let lastMatched = fit.lastMatched,
                                     lowerBound + lastMatched.upperBound == anchor + 1,
                                     fit.maxMatchedConfidence >= 0.70
        {
            true
        } else {
            false
        }

        let canAdvance = (fit.accepts(requiredMatches: requiredMatches) || singleNextWordMatch)
            && fit.lastMatched != nil
            && fit.matchedSpan != nil

        if canAdvance,
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
                if isSpeaking {
                    newMistakes += inspectInteriorSteps(steps, lowerBound: lowerBound, canConfirmClean: true)
                }
                return makeUpdate(completedVerses: [], newMistakes: newMistakes)
            }

            // Never skip an unrecited multi-word ayah, except consecutive 1-word ayahs (e.g. huruf
            // muqatta'at like `حمٓ` + `عٓسٓقٓ` on page 483) when the reciter cleanly matched >= 2
            // words immediately after them.
            let unrecitedUpper = max(currentRange.lowerBound, min(matchedGlobalSpan.lowerBound, expected.count))
            let unrecitedSpan = currentRange.lowerBound ..< unrecitedUpper
            let onlyBridgesOneWordAyahs = currentRange.count == 1
                && (currentVerseIndex ..< verseRanges.count).allSatisfy { idx in
                    let r = verseRanges[idx]
                    guard r.lowerBound < unrecitedSpan.upperBound else { return true }
                    return r.count == 1
                }
            let allowSingleWordBridge = onlyBridgesOneWordAyahs
                && fit.matches >= 2
                && matchedEnd <= upperBound
            if matchedEnd > currentRange.upperBound, !matchedAnyInCurrentVerse, !matchedCurrentInWindow, !allowSingleWordBridge {
                recordMissIfSpeaking(recognized, isSpeaking: isSpeaking)
                return makeUpdate(completedVerses: [], newMistakes: newMistakes)
            }

            if matchedCurrentInWindow || allowSingleWordBridge {
                matchedAnyInCurrentVerse = true
            }
            if matchedEnd > revealedUnitEnd, matchedEnd <= upperBound {
                revealedUnitEnd = matchedEnd
            }
            misses = 0
            isOffTrack = false

            if isSpeaking {
                newMistakes += inspectInteriorSteps(steps, lowerBound: lowerBound, canConfirmClean: true)
            }

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
            return makeUpdate(completedVerses: completed, newMistakes: newMistakes)
        }

        if isSpeaking {
            newMistakes += inspectInteriorSteps(steps, lowerBound: lowerBound, canConfirmClean: false)
        }
        recordMissIfSpeaking(recognized, isSpeaking: isSpeaking)
        return makeUpdate(completedVerses: [], newMistakes: newMistakes)
    }

    // MARK: Private

    private struct Fit {
        // MARK: Lifecycle

        init(_ steps: [WordAlignmentStep], recognized: [RecognizedWord], expected: [ExpectedWordText]) {
            let recognizedCount = recognized.count
            let tailStart = max(0, recognizedCount - RecitationFollower.tailLength)
            var recognizedIndex = 0
            for step in steps {
                let indices = recognizedIndex ..< recognizedIndex + step.recognized.count
                let isInflection = Self.isInflectionStep(step, expected: expected)
                if step.kind == .matched || isInflection, !step.expectedUnits.isEmpty {
                    matches += 1
                    tailMatches += indices.clamped(to: tailStart ..< recognizedCount).count
                    lastMatched = step.expectedUnits
                    if let existing = matchedSpan {
                        matchedSpan = min(existing.lowerBound, step.expectedUnits.lowerBound) ..< max(existing.upperBound, step.expectedUnits.upperBound)
                    } else {
                        matchedSpan = step.expectedUnits
                    }
                    for word in step.recognized {
                        maxMatchedConfidence = max(maxMatchedConfidence, word.confidence ?? 1)
                    }
                    trailingUnmatched = []
                } else {
                    trailingUnmatched.append(contentsOf: step.recognized)
                }
                recognizedIndex = indices.upperBound
            }
            requiredTailMatches = min(RecitationFollower.requiredTailMatches, recognizedCount)
        }

        // MARK: Internal

        var matches = 0
        var tailMatches = 0
        var lastMatched: Range<Int>?
        var matchedSpan: Range<Int>?
        var trailingUnmatched: [RecognizedWord] = []
        var maxMatchedConfidence: Float = 0
        let requiredTailMatches: Int

        func accepts(requiredMatches: Int) -> Bool {
            let effectiveTail = min(requiredTailMatches, requiredMatches)
            return matches >= requiredMatches && tailMatches >= effectiveTail && lastMatched != nil
        }

        static func isInflectionStep(_ step: WordAlignmentStep, expected: [ExpectedWordText]) -> Bool {
            guard step.expectedUnits.count == 1, step.recognized.count == 1 else {
                return false
            }
            return WordAligner.isInflectionMismatch(
                step.recognized[0].text,
                expected[step.expectedUnits.lowerBound].text
            )
        }
    }

    private let expectedLetters: [[UInt16]]
    private let verseRanges: [Range<Int>]
    private var revealedUnitEnd = 0
    private var matchedAnyInCurrentVerse = false
    private var misses = 0
    private var confirmedClean: Set<Int> = []
    private var mistakesByUnit: [Int: LivePracticeMistake] = [:]
    private var stumbleVotes: [Int: Int] = [:]
    private var substitutionVotes: [Int: Int] = [:]
    private var omissionVotes: [Int: Int] = [:]
    private var restartVotes: [Int: Int] = [:]

    private var latestRevealedWord: Word? {
        guard revealedUnitEnd > 0, revealedUnitEnd <= expected.count else {
            return nil
        }
        return expected[revealedUnitEnd - 1].words.last
    }

    private var pendingHiddenMistakeWord: Word? {
        guard revealedUnitEnd < expected.count,
              let mistake = mistakesByUnit[revealedUnitEnd]
        else {
            return nil
        }
        return mistake.word
    }

    private func makeUpdate(completedVerses: [AyahNumber], newMistakes: [LivePracticeMistake]) -> Update {
        Update(
            completedVerses: completedVerses,
            revealedWords: currentRevealedWords,
            isOffTrack: isOffTrack,
            liveMistakes: activeMistakes,
            newMistakes: newMistakes,
            currentWord: latestRevealedWord,
            pendingMistakeWord: pendingHiddenMistakeWord
        )
    }

    private mutating func recordMistake(unitIndex: Int, kind: LivePracticeMistake.Kind, recitedText: String) -> LivePracticeMistake? {
        guard expected.indices.contains(unitIndex),
              mistakesByUnit[unitIndex] == nil,
              let canonicalWord = expected[unitIndex].words.first
        else {
            return nil
        }
        let mistake = LivePracticeMistake(
            word: canonicalWord,
            kind: kind,
            expectedText: expected[unitIndex].text,
            recitedText: recitedText
        )
        mistakesByUnit[unitIndex] = mistake
        return mistake
    }

    /// Inspects finalized interior alignment steps (strictly behind the live edge) for substitutions,
    /// grammatical inflection mismatches, absorbed wrong prefixes, omissions, and grouped wrong
    /// starts, while locking cleanly matched words into `confirmedClean`.
    private mutating func inspectInteriorSteps(
        _ steps: [WordAlignmentStep],
        lowerBound: Int,
        canConfirmClean: Bool
    ) -> [LivePracticeMistake] {
        var added: [LivePracticeMistake] = []
        guard revealedUnitEnd > 1 else {
            return added
        }

        // Pass 1: Confirm clean words strictly behind the live edge and detect absorbed wrong-prefix 2:1 steps.
        if canConfirmClean {
            for step in steps where !step.expectedUnits.isEmpty {
                let globalStart = lowerBound + step.expectedUnits.lowerBound
                let globalEnd = lowerBound + step.expectedUnits.upperBound
                guard globalEnd <= revealedUnitEnd - 1 else { continue }

                let isInflection = step.expectedUnits.count == 1
                    && step.recognized.count == 1
                    && WordAligner.isInflectionMismatch(step.recognized[0].text, expected[globalStart].text)
                if isInflection {
                    continue
                }

                if step.expectedUnits.count == 1, step.recognized.count == 2 {
                    let r0 = WordAligner.letters(step.recognized[0].text)
                    let r1 = WordAligner.letters(step.recognized[1].text)
                    let exp = expectedLetters[globalStart]
                    if r0.count >= 4,
                       (step.recognized[0].confidence ?? 1) >= 0.65,
                       WordAligner.similarity(r1, exp) >= 0.65,
                       WordAligner.similarity(r0, exp) < 0.50
                    {
                        let prevExpected = (max(0, globalStart - 3) ..< globalStart).map { expectedLetters[$0] }
                        if !prevExpected.contains(where: { WordAligner.similarity(r0, $0) >= 0.65 }) {
                            substitutionVotes[globalStart, default: 0] += 1
                            if substitutionVotes[globalStart, default: 0] >= 2, !confirmedClean.contains(globalStart) {
                                if let mistake = recordMistake(unitIndex: globalStart, kind: .stumble, recitedText: step.recognized[0].text) {
                                    added.append(mistake)
                                }
                            }
                            continue
                        }
                    }
                }

                if step.kind == .matched {
                    for unit in globalStart ..< globalEnd {
                        confirmedClean.insert(unit)
                    }
                }
            }
        }

        // Pass 2: Interior inflection mismatches, confident substitutions, and sustained omissions.
        for step in steps where !step.expectedUnits.isEmpty {
            let globalStart = lowerBound + step.expectedUnits.lowerBound
            let globalEnd = lowerBound + step.expectedUnits.upperBound
            guard globalEnd <= revealedUnitEnd - 1 else { continue }
            let globalRange = globalStart ..< globalEnd
            if globalRange.allSatisfy({ confirmedClean.contains($0) }) { continue }

            let isInflection = step.expectedUnits.count == 1
                && step.recognized.count == 1
                && WordAligner.isInflectionMismatch(step.recognized[0].text, expected[globalStart].text)

            if isInflection {
                guard !confirmedClean.contains(globalStart),
                      step.recognized.allSatisfy({ ($0.meanConfidence ?? 1) >= 0.55 })
                else {
                    continue
                }
                substitutionVotes[globalStart, default: 0] += 1
                if substitutionVotes[globalStart, default: 0] >= 2 {
                    let recited = step.recognized.map(\.text).joined(separator: " ")
                    if let mistake = recordMistake(unitIndex: globalStart, kind: .substitution, recitedText: recited) {
                        added.append(mistake)
                    }
                }
            } else if step.kind == .mismatched,
                      step.similarity <= 0.50,
                      step.recognized.count <= 2,
                      step.recognized.allSatisfy({ ($0.confidence ?? 1) >= 0.65 })
            {
                guard !confirmedClean.contains(globalStart) else { continue }
                substitutionVotes[globalStart, default: 0] += 1
                if substitutionVotes[globalStart, default: 0] >= 3 {
                    let recited = step.recognized.map(\.text).joined(separator: " ")
                    if let mistake = recordMistake(unitIndex: globalStart, kind: .substitution, recitedText: recited) {
                        added.append(mistake)
                    }
                }
            } else if step.kind == .omitted {
                for unit in globalRange where !confirmedClean.contains(unit) && expectedLetters[unit].count >= 3 {
                    omissionVotes[unit, default: 0] += 1
                    if omissionVotes[unit, default: 0] >= 4 {
                        if let mistake = recordMistake(unitIndex: unit, kind: .omitted, recitedText: "") {
                            added.append(mistake)
                        }
                    }
                }
            }
        }

        // Pass 3: Grouped consecutive insertions immediately before a matched word (rapid wrong-start + self-correction).
        var index = 0
        while index < steps.count {
            if steps[index].kind == .inserted {
                var insertedWords: [RecognizedWord] = []
                while index < steps.count, steps[index].kind == .inserted {
                    insertedWords.append(contentsOf: steps[index].recognized)
                    index += 1
                }
                if index < steps.count {
                    let nextStep = steps[index]
                    let nextIsMatch = nextStep.kind == .matched || (
                        nextStep.expectedUnits.count == 1
                            && nextStep.recognized.count == 1
                            && WordAligner.isInflectionMismatch(
                                nextStep.recognized[0].text,
                                expected[lowerBound + nextStep.expectedUnits.lowerBound].text
                            )
                    )
                    if nextIsMatch, !nextStep.expectedUnits.isEmpty {
                        let targetUnit = lowerBound + nextStep.expectedUnits.lowerBound
                        if mistakesByUnit[targetUnit] == nil,
                           targetUnit >= revealedUnitEnd - 8,
                           targetUnit < revealedUnitEnd,
                           !RecitationFollower.isOpening(insertedWords)
                        {
                            let nearbyRange = max(0, targetUnit - 4) ..< min(expected.count, targetUnit + 5)
                            let nearbyExpected = nearbyRange.map { expectedLetters[$0] }
                            let wrong = insertedWords.filter { word in
                                let letters = WordAligner.letters(word.text)
                                guard letters.count >= 3, (word.meanConfidence ?? 1) >= 0.65 else { return false }
                                return !nearbyExpected.contains { WordAligner.similarity(letters, $0) >= 0.65 }
                            }
                            let qualifies = wrong.count >= 2 || (
                                wrong.count == 1
                                    && WordAligner.letters(wrong[0].text).count >= 4
                                    && (wrong[0].confidence ?? 1) >= 0.68
                            )
                            if qualifies {
                                stumbleVotes[targetUnit, default: 0] += 1
                                if stumbleVotes[targetUnit, default: 0] >= 2 {
                                    let phrase = insertedWords.prefix(4).map(\.text).joined(separator: " ")
                                    if let mistake = recordMistake(unitIndex: targetUnit, kind: .stumble, recitedText: phrase) {
                                        added.append(mistake)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                index += 1
            }
        }

        return added
    }

    private mutating func recordMissIfSpeaking(_ recognized: [RecognizedWord], isSpeaking: Bool) {
        if isSpeaking, !RecitationFollower.isOpening(recognized.suffix(RecitationFollower.tailLength)) {
            misses += 1
        }
        if misses >= Self.missesBeforeOffTrack {
            isOffTrack = true
        }
    }
}
