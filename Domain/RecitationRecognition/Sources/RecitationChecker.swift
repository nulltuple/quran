//
//  RecitationChecker.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import QuranKit

/// The verdict on one canonical word of a checked passage.
public struct CheckedWord: Equatable, Sendable {
    public enum Mark: Equatable, Sendable {
        /// Recited as written, or corrected by the reciter straight after a slip.
        case correct
        /// Not recited, while the words around it were.
        case omitted
        /// Something else was recited in its place, and the model is confident it heard it.
        case substituted(recited: String)
        /// It differs from what was heard, but too little to call a mistake: the model may have
        /// misheard it. Shown to the reciter as "check this", never as a mistake.
        case uncertain
        /// After the last word recited: the reciter stopped before it.
        case notReached
    }

    public init(word: Word, mark: Mark, frames: ClosedRange<Int>?) {
        self.word = word
        self.mark = mark
        self.frames = frames
    }

    public let word: Word
    public let mark: Mark
    /// The frames of the recited words that stood for it, when there are any.
    public let frames: ClosedRange<Int>?

    public var isMistake: Bool {
        switch mark {
        case .omitted, .substituted: true
        case .correct, .uncertain, .notReached: false
        }
    }
}

/// The result of checking a recitation against the passage it should recite. Nothing in it is
/// stored.
public struct RecitationCheck: Equatable, Sendable {
    public init(words: [CheckedWord], skippedVerses: [AyahNumber]) {
        self.words = words
        self.skippedVerses = skippedVerses
    }

    /// Every canonical word of the passage, in order.
    public let words: [CheckedWord]
    /// Verses of which no word was recited, before the last word that was.
    public let skippedVerses: [AyahNumber]

    public var mistakes: [CheckedWord] {
        words.filter(\.isMistake)
    }
}

/// Checks a recitation's words against the expected words of a passage (V3a recite and check).
///
/// The words are aligned with `WordAligner`, then each step becomes a verdict, gated so that a
/// slip of the model is not blamed on the reciter:
/// - a recited word close to the written one (similarity ≥ `WordAligner.matchSimilarity`) is correct;
///   a small mistake in a word's ending therefore passes (phoneme-level checks are V4);
/// - a different word counts as a substitution only when it is clearly different (similarity below
///   `uncertainSimilarity`) and the model was confident in every recited word of it
///   (`RecognizedWord.confidence` ≥ `minimumConfidence`); otherwise it is uncertain;
/// - an omission or substitution next to an extra recited word that matches the expected word is a
///   self-correction ("قل هو الله أحد" recited "قل هو ... هو الله أحد"), so correct;
/// - repeats and other extra words are never mistakes: reciters go back over phrases;
/// - the words after the last one recited are not reached, not omitted (the reciter stopped);
/// - a verse with no recited word, before the last recited word, is a skipped verse.
///
/// Thresholds were chosen on the 350 EveryAyah transcripts with planted mistakes
/// (`RecitationCheckerRecitationTests`, V3a trail).
public struct RecitationChecker: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public static let uncertainSimilarity = 0.5
    public static let minimumConfidence: Float = 0.6

    public func check(_ recognized: [RecognizedWord], against expected: [ExpectedWordText]) -> RecitationCheck {
        // Semi-global, preferring the earliest place: a recitation stopped early ends where it
        // stopped instead of stretching over the passage with omissions. Words before the first
        // step were left out (the reciter chose where the passage starts); after the last, not reached.
        let steps = WordAligner().alignWithin(recognized, to: expected, preferredEnd: 0)
        let recited = steps.filter { $0.kind == .matched || $0.kind == .mismatched }
        let firstRecitedUnit = recited.first?.expectedUnits.lowerBound ?? 0
        let lastRecitedUnit = recited.last?.expectedUnits.upperBound ?? 0

        var words: [CheckedWord] = expected[0 ..< min(firstRecitedUnit, lastRecitedUnit)].flatMap { unit in
            unit.words.map { CheckedWord(word: $0, mark: .omitted, frames: nil) }
        }
        for (index, step) in steps.enumerated() where step.kind != .inserted {
            guard step.expectedUnits.lowerBound >= firstRecitedUnit || lastRecitedUnit == 0 else { continue }
            let mark: CheckedWord.Mark = if step.expectedUnits.lowerBound >= lastRecitedUnit {
                .notReached
            } else if step.kind == .matched || isSelfCorrected(steps, at: index, expected: expected) {
                .correct
            } else if step.kind == .omitted {
                .omitted
            } else if step.similarity < Self.uncertainSimilarity,
                      step.recognized.allSatisfy({ ($0.confidence ?? 1) >= Self.minimumConfidence })
            {
                .substituted(recited: step.recognized.map(\.text).joined(separator: " "))
            } else {
                .uncertain
            }
            let left = mark == .notReached ? [] : unitsLeftOut(of: step, expected: expected)
            for unit in step.expectedUnits {
                let unitMark = left.contains(unit) ? .omitted : mark
                words += expected[unit].words.map { CheckedWord(word: $0, mark: unitMark, frames: unitMark == .omitted ? nil : step.frames) }
            }
        }
        let covered = steps.last { $0.kind != .inserted }?.expectedUnits.upperBound ?? 0
        words += expected[covered...].flatMap { unit in
            unit.words.map { CheckedWord(word: $0, mark: .notReached, frames: nil) }
        }

        var skipped: [AyahNumber] = []
        var index = 0
        while index < words.count {
            let verse = words[index].word.verse
            let end = words[index...].firstIndex { $0.word.verse != verse } ?? words.count
            if words[index ..< end].allSatisfy({ $0.mark == .omitted }) {
                skipped.append(verse)
            }
            index = end
        }
        return RecitationCheck(words: words, skippedVerses: skipped)
    }

    // MARK: Private

    /// The aligner lets one recited word stand for two expected ones (the scripts split some words
    /// differently, and the model sometimes joins words), so a short word left out between two
    /// recited ones is absorbed: "تفسدوا" for "تُفۡسِدُواْ فِي" still matches. When each recited word
    /// fits one of the step's expected units alone at least as well as the step does, the other
    /// units were left out.
    private func unitsLeftOut(of step: WordAlignmentStep, expected: [ExpectedWordText]) -> Set<Int> {
        guard step.kind != .omitted, step.expectedUnits.count > step.recognized.count, !step.recognized.isEmpty else {
            return []
        }
        let threshold = max(WordAligner.matchSimilarity, step.similarity)
        var fitted = Set<Int>()
        for word in step.recognized {
            let letters = WordAligner.letters(word.text)
            let fits = step.expectedUnits.map { ($0, WordAligner.similarity(letters, WordAligner.letters(expected[$0].text))) }
            guard let best = fits.max(by: { $0.1 < $1.1 }), best.1 >= threshold else {
                return []
            }
            fitted.insert(best.0)
        }
        guard fitted.count == step.recognized.count else {
            return []
        }
        return Set(step.expectedUnits).subtracting(fitted)
    }

    /// Whether an extra recited word right before or after `steps[index]` matches its expected text.
    private func isSelfCorrected(_ steps: [WordAlignmentStep], at index: Int, expected: [ExpectedWordText]) -> Bool {
        let step = steps[index]
        guard step.kind == .omitted || step.kind == .mismatched else {
            return false
        }
        let written = WordAligner.letters(expected[step.expectedUnits].map(\.text).joined(separator: " "))
        let neighbors = [index - 1, index + 1].filter { steps.indices.contains($0) && steps[$0].kind == .inserted }
        return neighbors.contains { neighbor in
            steps[neighbor].recognized.contains { WordAligner.similarity(WordAligner.letters($0.text), written) >= WordAligner.matchSimilarity }
        }
    }
}
