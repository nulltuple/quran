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
    /// The step's positions in the `expected` array it was aligned to; empty (at the next unit) for `.inserted`.
    public let expectedUnits: Range<Int>

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
        return makeSteps(Self.path(recited: recited, written: written, within: nil), recognized, recited, expected, written)
    }

    /// Aligns a short stretch of recitation (a streaming window) to the part of a longer passage it
    /// recites: the expected words before and after that part cost nothing, so the steps start at
    /// the first and end at the last expected word the recitation covers. Of equally good places,
    /// the one ending nearest `preferredEnd` (an index into `expected`) wins, so a repeated phrase
    /// is found where the reciter is rather than at its first occurrence.
    public func alignWithin(_ recognized: [RecognizedWord], to expected: [ExpectedWordText], preferredEnd: Int) -> [WordAlignmentStep] {
        let recited = recognized.map { Self.letters($0.text) }
        let written = expected.map { Self.letters($0.text) }
        let steps = Self.path(recited: recited, written: written, within: preferredEnd)
        return makeSteps(steps, recognized, recited, expected, written)
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

    /// Detects high-value Arabic grammatical inflection swaps that plain edit ratio (`≥ 0.7`)
    /// otherwise forgives on long words: masculine plural `-ون` ↔ `-ين` (e.g. `الظالمون` vs
    /// `الظالمين`) and pronoun suffix `-هم` ↔ `-كم` (e.g. `عليهم` vs `عليكم`), when the stems
    /// match closely (`similarity ≥ 0.80`).
    public static func isInflectionMismatch(_ recited: String, _ expected: String) -> Bool {
        isInflectionMismatch(letters(recited), letters(expected))
    }

    static func isInflectionMismatch(_ recited: [UInt16], _ expected: [UInt16]) -> Bool {
        guard recited.count >= 4, expected.count >= 4 else {
            return false
        }
        let rSuffix = (recited[recited.count - 2], recited[recited.count - 1])
        let eSuffix = (expected[expected.count - 2], expected[expected.count - 1])
        let swapped = switch (rSuffix, eSuffix) {
        case ((ya, nun), (waw, nun)), ((waw, nun), (ya, nun)),
             ((kaf, mim), (ha, mim)), ((ha, mim), (kaf, mim)):
            true
        default:
            false
        }
        guard swapped else {
            return false
        }
        return similarity(Array(recited.dropLast(2)), Array(expected.dropLast(2))) >= 0.8
    }

    // MARK: Private

    private struct Step {
        let recited: Range<Int>
        let written: Range<Int>
    }

    private static let alef: UInt16 = 0x0627
    private static let kaf: UInt16 = 0x0643
    private static let mim: UInt16 = 0x0645
    private static let nun: UInt16 = 0x0646
    private static let ha: UInt16 = 0x0647
    private static let waw: UInt16 = 0x0648
    private static let ya: UInt16 = 0x064A
    /// Per expected unit between a window's end and the preferred end: far below any mismatch, so it
    /// only breaks ties between equally good places.
    private static let distancePenalty = 0.001
    private static let gapCost = 1.0
    private static let regroupingCost = 0.4
    private static let tripleShortRegroupingCost = 0.45

    /// The cheapest sequence of steps through both word lists. With `within` (a preferred end),
    /// expected words before the first and after the last aligned one are free and left out.
    private static func path(recited: [[UInt16]], written: [[UInt16]], within preferredEnd: Int?) -> [Step] {
        let n = recited.count, m = written.count
        let width = m + 1
        var cost = [Double](repeating: .infinity, count: (n + 1) * width)
        var back = [(Int, Int)](repeating: (0, 0), count: (n + 1) * width)
        cost[0] = 0
        if preferredEnd != nil {
            for j in 0 ... m {
                cost[j] = 0
                back[j] = (0, j)
            }
        }
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
                // Huruf muqatta'at (e.g. `عٓسٓقٓ`) are often emitted as three separate short tokens (`ع س ق`).
                if i + 2 < n, j < m,
                   recited[i].count <= 2, recited[i + 1].count <= 2, recited[i + 2].count <= 2,
                   written[j].count <= 6
                {
                    relax(3, 1) { pairCost(recited[i] + recited[i + 1] + recited[i + 2], written[j]) + tripleShortRegroupingCost }
                }
            }
        }
        var j = m
        if let preferredEnd {
            // The free trailing words: end where the recitation ends, nearest the preferred end on a tie.
            j = (0 ... m).min { a, b in
                let costA = cost[n * width + a] + distancePenalty * Double(abs(a - 1 - preferredEnd))
                let costB = cost[n * width + b] + distancePenalty * Double(abs(b - 1 - preferredEnd))
                return costA < costB
            } ?? m
        }
        var steps: [Step] = []
        var i = n
        while i > 0 || (preferredEnd == nil && j > 0) {
            let (pi, pj) = back[i * width + j]
            steps.append(Step(recited: pi ..< i, written: pj ..< j))
            (i, j) = (pi, pj)
        }
        return steps.reversed()
    }

    private func makeSteps(
        _ steps: [Step],
        _ recognized: [RecognizedWord],
        _ recited: [[UInt16]],
        _ expected: [ExpectedWordText],
        _ written: [[UInt16]]
    ) -> [WordAlignmentStep] {
        steps.map { step in
            let recognizedWords = Array(recognized[step.recited])
            let expectedWords = expected[step.written].flatMap(\.words)
            if recognizedWords.isEmpty {
                return WordAlignmentStep(kind: .omitted, expected: expectedWords, recognized: [], similarity: 0, expectedUnits: step.written)
            }
            if expectedWords.isEmpty {
                return WordAlignmentStep(kind: .inserted, expected: [], recognized: recognizedWords, similarity: 0, expectedUnits: step.written)
            }
            let similarity = Self.similarity(recited[step.recited].flatMap { $0 }, written[step.written].flatMap { $0 })
            return WordAlignmentStep(
                kind: similarity >= Self.matchSimilarity ? .matched : .mismatched,
                expected: expectedWords,
                recognized: recognizedWords,
                similarity: similarity,
                expectedUnits: step.written
            )
        }
    }
}
