//
//  WordAligner.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import QuranKit

/// Canonical words as the Uthmani text writes them: usually one word, but a few tokens write two
/// words together (`لَّوۡمَا`, 15:7) and one word can span two tokens (`إِلۡ يَاسِينَ`, 37:130), in
/// which case `text` joins them. `words` are consecutive and never empty.
public struct ExpectedWordText: Equatable, Sendable {
    // MARK: Lifecycle

    public init(words: [Word], text: String) {
        precondition(!words.isEmpty, "an expected text covers at least one word")
        self.words = words
        self.text = text
    }

    // MARK: Public

    public let words: [Word]
    public let text: String
}

/// One step of an alignment, in recitation order.
public struct WordAlignmentStep: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The recited words fit the expected words (similarity at least `WordAligner.matchSimilarity`).
        case matched
        /// Something was recited in the expected words' place, but it differs from them.
        case mismatched
        /// The expected words have nothing recited for them.
        case omitted
        /// A recited word fits no expected word (a repeat, the basmala before a verse, noise).
        case inserted
    }

    public let kind: Kind
    /// The canonical words of this step; empty for `.inserted`.
    public let expected: [Word]
    /// The recited words of this step; empty for `.omitted`.
    public let recognized: [RecognizedWord]
    /// 0–1 letter similarity of the recited and expected text; 0 for `.omitted` and `.inserted`.
    public let similarity: Double

    /// The frames the recited words span, when the transcript had timing.
    public var frames: ClosedRange<Int>? {
        let ranges = recognized.compactMap(\.frames)
        guard let first = ranges.first else {
            return nil
        }
        return ranges.dropFirst().reduce(first) { min($0.lowerBound, $1.lowerBound) ... max($0.upperBound, $1.upperBound) }
    }
}

/// Aligns a transcript's words to the canonical words of the passage it recites, keeping each
/// recited word's frames: the word-level timing that live follow (V2) and mistake detection (V3)
/// build on.
///
/// A word-level edit-distance program: a pair costs 2 × (1 − letter similarity), an omitted or
/// inserted word 1, and two recited words for one expected word (or one for two) the pair cost plus
/// 0.4, which covers the imla'i and Uthmani writings that split words differently (`يا أيها` and
/// `يَٰٓأَيُّهَا`). Similarity compares the letters of `ArabicMatchNormalizer` with hamza carriers
/// folded, and takes the better of that and the same letters without alef, because the Uthmani
/// script often leaves out an alef the plain text writes (`ٱلۡعَٰلَمِينَ`, `صَٰٓفَّٰتٖ`). The costs and
/// the folding were chosen on the 350 EveryAyah transcripts of `VerseMatcherRecitationTests` (V0 (b)
/// trail): 98% of canonical words matched, the rest mostly misheard words of clips over 20 s.
///
/// The cost is recited words × expected words letter comparisons: align a transcript to the verses
/// it was identified with, not to a whole sura.
public struct WordAligner: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public static let matchSimilarity = 0.7

    public func align(_ recognized: [RecognizedWord], to expected: [ExpectedWordText]) -> [WordAlignmentStep] {
        let recited = recognized.map { Self.letters($0.text) }
        let written = expected.map { Self.letters($0.text) }
        let steps = Self.path(recited: recited, written: written)
        return steps.map { step in
            let recognizedWords = Array(recognized[step.recited])
            let expectedWords = expected[step.written].flatMap(\.words)
            if recognizedWords.isEmpty {
                return WordAlignmentStep(kind: .omitted, expected: expectedWords, recognized: [], similarity: 0)
            }
            if expectedWords.isEmpty {
                return WordAlignmentStep(kind: .inserted, expected: [], recognized: recognizedWords, similarity: 0)
            }
            let similarity = Self.similarity(recited[step.recited].flatMap { $0 }, written[step.written].flatMap { $0 })
            return WordAlignmentStep(
                kind: similarity >= Self.matchSimilarity ? .matched : .mismatched,
                expected: expectedWords,
                recognized: recognizedWords,
                similarity: similarity
            )
        }
    }

    // MARK: Internal

    /// Letters compared for alignment: the matcher's letters with `ؤ` → `و`, `ئ` → `ي` and `ء`
    /// dropped (the two scripts seat hamza differently).
    static func letters(_ text: String) -> [UInt16] {
        ArabicMatchNormalizer.letters(text).compactMap { letter in
            switch letter {
            case 0x0624: return 0x0648
            case 0x0626: return 0x064A
            case 0x0621: return nil
            default: return letter
            }
        }
    }

    /// The better of the plain letter ratio and the ratio without alef.
    static func similarity(_ a: [UInt16], _ b: [UInt16]) -> Double {
        let plain = EditDistance.ratio(a, b)
        let a = a.filter { $0 != alef }
        let b = b.filter { $0 != alef }
        guard !a.isEmpty || !b.isEmpty else {
            return plain
        }
        return max(plain, EditDistance.ratio(a, b))
    }

    // MARK: Private

    private struct Step {
        let recited: Range<Int>
        let written: Range<Int>
    }

    private static let alef: UInt16 = 0x0627
    private static let gapCost = 1.0
    private static let regroupingCost = 0.4

    /// The cheapest sequence of steps through both word lists.
    private static func path(recited: [[UInt16]], written: [[UInt16]]) -> [Step] {
        let n = recited.count, m = written.count
        let width = m + 1
        var cost = [Double](repeating: .infinity, count: (n + 1) * width)
        var back = [(Int, Int)](repeating: (0, 0), count: (n + 1) * width)
        cost[0] = 0
        func pairCost(_ a: [UInt16], _ b: [UInt16]) -> Double {
            2 * (1 - similarity(a, b))
        }
        for i in 0 ... n {
            for j in 0 ... m {
                let here = cost[i * width + j]
                guard here.isFinite else { continue }
                func relax(_ di: Int, _ dj: Int, _ stepCost: () -> Double) {
                    let ii = i + di, jj = j + dj
                    guard ii <= n, jj <= m else { return }
                    let total = here + stepCost()
                    if total < cost[ii * width + jj] {
                        cost[ii * width + jj] = total
                        back[ii * width + jj] = (i, j)
                    }
                }
                // Order matters only for ties: a pair before gaps and regroupings.
                if i < n, j < m {
                    relax(1, 1) { pairCost(recited[i], written[j]) }
                }
                relax(1, 0) { gapCost }
                relax(0, 1) { gapCost }
                if i + 1 < n, j < m {
                    relax(2, 1) { pairCost(recited[i] + recited[i + 1], written[j]) + regroupingCost }
                }
                if i < n, j + 1 < m {
                    relax(1, 2) { pairCost(recited[i], written[j] + written[j + 1]) + regroupingCost }
                }
            }
        }
        var steps: [Step] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            let (pi, pj) = back[i * width + j]
            steps.append(Step(recited: pi ..< i, written: pj ..< j))
            (i, j) = (pi, pj)
        }
        return steps.reversed()
    }
}
