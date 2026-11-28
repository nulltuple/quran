//
//  PronunciationAssessor.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation

/// Arabic short vowel (harakah) in the Quran Phonetic Script.
public enum PhoneticVowel: UInt32, Equatable, Sendable {
    case fatha = 0x064E // َ
    case damma = 0x064F // ُ
    case kasra = 0x0650 // ِ

    public init?(scalar: Unicode.Scalar) {
        self.init(rawValue: scalar.value)
    }

    public var displayName: String {
        switch self {
        case .fatha: "a (fatha)"
        case .damma: "u (damma)"
        case .kasra: "i (kasra)"
        }
    }
}

/// One clear pronunciation finding (lahn jali — V4) on a word. Kept strictly separate from
/// memorization verdicts (`RecitationCheck`) and fine tajweed rules (V5).
public struct PronunciationIssue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case wrongVowel(expected: PhoneticVowel, heard: PhoneticVowel)
        case wrongConsonant(expected: String, heard: String)
        case droppedSound(expected: String)
        case addedSound(heard: String)
        case missingShadda(letter: String)
        case wordNotHeard
    }

    public enum Certainty: Equatable, Sendable {
        /// Acoustic model confidence met the confirmation threshold.
        case confirmed
        /// Model confidence was below the threshold; never surfaced as a confirmed mistake.
        case uncertain
    }

    public let kind: Kind
    public let certainty: Certainty
    public let confidence: Float
    /// 0-based index into `PhoneticReference.phonemes`.
    public let expectedOffset: Int

    public init(kind: Kind, certainty: Certainty, confidence: Float, expectedOffset: Int) {
        self.kind = kind
        self.certainty = certainty
        self.confidence = confidence
        self.expectedOffset = expectedOffset
    }

    public var summary: String {
        switch kind {
        case .wrongVowel(let expected, let heard):
            "Wrong vowel: heard \(heard.displayName) instead of \(expected.displayName)"
        case .wrongConsonant(let expected, let heard):
            "Wrong sound: heard \(heard) instead of \(expected)"
        case .droppedSound(let expected):
            "Dropped sound: \(expected)"
        case .addedSound(let heard):
            "Extra sound: \(heard)"
        case .missingShadda(let letter):
            "Shadda not doubled on \(letter)"
        case .wordNotHeard:
            "Word not heard"
        }
    }
}

/// Pronunciation assessment verdict for one word in a passage.
public struct WordPronunciationAssessment: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case correct
        case mistake
        case uncertain
    }

    public let wordIndex: Int
    public let wordNumber: Int
    public let displayText: String
    public let expectedPhonemes: String
    public let heardPhonemes: String
    public let status: Status
    public let issues: [PronunciationIssue]

    public var confirmedIssues: [PronunciationIssue] {
        issues.filter { $0.certainty == .confirmed }
    }

    public var uncertainIssues: [PronunciationIssue] {
        issues.filter { $0.certainty == .uncertain }
    }
}

/// Output of `PronunciationAssessor` (V4): phoneme and vowel accuracy, strictly separate from
/// memorization (`RecitationCheck`) and fine tajweed rules (V5).
public struct PronunciationAssessment: Equatable, Sendable {
    public let expectedPhonemes: String
    public let heardPhonemes: String
    /// `1 - editDistance / max(expected.count, heard.count)`, in `0...1`.
    public let phonemeMatchRate: Double
    public let words: [WordPronunciationAssessment]

    public var confirmedMistakeCount: Int {
        words.reduce(0) { $0 + $1.confirmedIssues.count }
    }

    public var uncertainCount: Int {
        words.reduce(0) { $0 + $1.uncertainIssues.count }
    }
}

/// Shared alignment helpers over QPS symbol arrays, reused by both V4 `PronunciationAssessor` and
/// V5 tajweed assessment.
enum PhoneticAlignment {
    enum OpKind: Equatable {
        case equal
        case replace
        case delete
        case insert
    }

    struct Opcode: Equatable {
        let kind: OpKind
        let expectedRange: Range<Int>
        let heardRange: Range<Int>
    }

    /// Computes Levenshtein edit opcodes turning `expected` into `heard`.
    static func opcodes(expected: [Unicode.Scalar], heard: [Unicode.Scalar]) -> [Opcode] {
        let n = expected.count
        let m = heard.count
        let cols = m + 1
        var dp = [Int](repeating: 0, count: (n + 1) * cols)
        for i in 0 ... n {
            dp[i * cols] = i
        }
        for j in 0 ... m {
            dp[j] = j
        }

        if n > 0, m > 0 {
            for i in 1 ... n {
                let row = i * cols
                let prevRow = (i - 1) * cols
                for j in 1 ... m {
                    let sub = dp[prevRow + j - 1] + (expected[i - 1] == heard[j - 1] ? 0 : 1)
                    let del = dp[prevRow + j] + 1
                    let ins = dp[row + j - 1] + 1
                    dp[row + j] = min(sub, min(del, ins))
                }
            }
        }

        // Backtrack step-by-step operations in reverse, then coalesce contiguous runs of the same kind.
        var steps: [(OpKind, Int, Int, Int, Int)] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, expected[i - 1] == heard[j - 1], dp[i * cols + j] == dp[(i - 1) * cols + j - 1] {
                steps.append((.equal, i - 1, i, j - 1, j))
                i -= 1
                j -= 1
            } else if i > 0, j > 0, dp[i * cols + j] == dp[(i - 1) * cols + j - 1] + 1 {
                steps.append((.replace, i - 1, i, j - 1, j))
                i -= 1
                j -= 1
            } else if i > 0, dp[i * cols + j] == dp[(i - 1) * cols + j] + 1 {
                steps.append((.delete, i - 1, i, j, j))
                i -= 1
            } else {
                steps.append((.insert, i, i, j - 1, j))
                j -= 1
            }
        }
        steps.reverse()

        var coalesced: [Opcode] = []
        for (kind, i1, i2, j1, j2) in steps {
            if let last = coalesced.last, last.kind == kind {
                coalesced[coalesced.count - 1] = Opcode(
                    kind: kind,
                    expectedRange: last.expectedRange.lowerBound ..< i2,
                    heardRange: last.heardRange.lowerBound ..< j2
                )
            } else {
                coalesced.append(Opcode(kind: kind, expectedRange: i1 ..< i2, heardRange: j1 ..< j2))
            }
        }
        return coalesced
    }

    /// Maps every index `0...expected.count` to its corresponding position in `heard`.
    static func boundaries(expectedCount: Int, heardCount: Int, opcodes: [Opcode]) -> [Int] {
        var map = [Int](repeating: 0, count: expectedCount + 1)
        for op in opcodes {
            let i1 = op.expectedRange.lowerBound
            let i2 = op.expectedRange.upperBound
            let j1 = op.heardRange.lowerBound
            let j2 = op.heardRange.upperBound
            let spanI = i2 - i1
            let spanJ = j2 - j1
            for k in i1 ... i2 {
                if spanI > 0 {
                    map[k] = j1 + Int((Double(k - i1) * Double(spanJ) / Double(spanI)).rounded())
                } else {
                    map[k] = j1
                }
            }
        }
        map[expectedCount] = heardCount
        return map
    }

    /// Collapses repeated scalars and removes tajweed-length markers (`ا`, `ۥ`, `ۦ`, `ں`, `ڇ`, `۾`).
    static func stripLengthAndTajweedMarks(_ scalars: ArraySlice<Unicode.Scalar>) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        for ch in scalars {
            if out.last == ch { continue }
            if longVowels.contains(ch) || tajweedMarkers.contains(ch) { continue }
            out.append(ch)
        }
        return out
    }

    static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        String(String.UnicodeScalarView(scalars))
    }

    static let longVowels: Set<Unicode.Scalar> = ["ا", "ۥ", "ۦ"].compactMap(\.unicodeScalars.first).reduce(into: []) { $0.insert($1) }
    static let harakat: Set<Unicode.Scalar> = [Unicode.Scalar(0x064E)!, Unicode.Scalar(0x064F)!, Unicode.Scalar(0x0650)!]
    static let tajweedMarkers: Set<Unicode.Scalar> = ["ں", "ڇ", "۾"].compactMap(\.unicodeScalars.first).reduce(into: []) { $0.insert($1) }
    static let nasalLetters: Set<Unicode.Scalar> = ["ن", "م"].compactMap(\.unicodeScalars.first).reduce(into: []) { $0.insert($1) }

    /// Length and range of a contiguous run of `target` overlapping `heard[range]`, grown across
    /// adjacent identical scalars so an extended vowel or nasal is counted as one run.
    static func symbolRun(in heard: [Unicode.Scalar], searchRange: Range<Int>, target: Unicode.Scalar) -> (count: Int, range: Range<Int>) {
        let lo = max(0, searchRange.lowerBound)
        let hi = min(heard.count, searchRange.upperBound)
        guard lo < hi, let hit = (lo ..< hi).first(where: { heard[$0] == target }) else {
            return (0, lo ..< lo)
        }
        var start = hit
        var end = hit + 1
        while start > 0, heard[start - 1] == target {
            start -= 1
        }
        while end < heard.count, heard[end] == target {
            end += 1
        }
        return (end - start, start ..< end)
    }
}

/// Evaluates phoneme and vowel (harakah) accuracy (V4) by aligning a `PhoneticTranscription`
/// against a `PhoneticReference`. Adapted from HisnLabs `imam.py` (Apache-2.0) with strict
/// confidence gating so uncertain recognition is never reported as a confirmed mistake.
public struct PronunciationAssessor: Sendable {
    // MARK: Lifecycle

    public init(
        minimumConfirmedConfidence: Float = 0.70,
        onsetConfirmedConfidence: Float = 0.85,
        onsetSymbolCount: Int = 3
    ) {
        self.minimumConfirmedConfidence = minimumConfirmedConfidence
        self.onsetConfirmedConfidence = onsetConfirmedConfidence
        self.onsetSymbolCount = onsetSymbolCount
    }

    // MARK: Public

    /// Minimum CTC posterior probability to confirm a clear pronunciation mistake.
    public let minimumConfirmedConfidence: Float
    /// Stricter confidence required in the first `onsetSymbolCount` symbols of a breath.
    public let onsetConfirmedConfidence: Float
    public let onsetSymbolCount: Int

    public func assess(
        transcription: PhoneticTranscription,
        against reference: PhoneticReference
    ) -> PronunciationAssessment {
        let expected = Array(reference.phonemes.unicodeScalars)
        let heard = transcription.symbols.map(\.symbol)
        let probs = transcription.symbols.map(\.probability)

        let opcodes = PhoneticAlignment.opcodes(expected: expected, heard: heard)
        let boundaries = PhoneticAlignment.boundaries(expectedCount: expected.count, heardCount: heard.count, opcodes: opcodes)

        let edits = opcodes.reduce(0) { sum, op in
            switch op.kind {
            case .equal: sum
            case .replace: sum + max(op.expectedRange.count, op.heardRange.count)
            case .delete: sum + op.expectedRange.count
            case .insert: sum + op.heardRange.count
            }
        }
        let denom = max(expected.count, heard.count)
        let matchRate = denom == 0 ? 1.0 : max(0.0, 1.0 - Double(edits) / Double(denom))

        // Mark positions belonging to tajweed rule units so V4 does not double-report madd/ghunnah/
        // ikhfa/iqlab/idgham/qalqalah differences as clear pronunciation errors (those belong to V5).
        var coveredByTajweed = [Bool](repeating: false, count: expected.count)
        for unit in reference.units {
            for pos in unit.phonemeRange where pos < coveredByTajweed.count {
                coveredByTajweed[pos] = true
            }
        }

        var issuesByWord = [[PronunciationIssue]](repeating: [], count: reference.words.count)

        // 1. Check shadda (gemination is a clear pronunciation mistake — lahn jali — when dropped to 1).
        for unit in reference.units where unit.kind == .shadda {
            guard unit.wordIndex >= 0, unit.wordIndex < issuesByWord.count else { continue }
            let hs = boundaries[min(unit.phonemeRange.lowerBound, boundaries.count - 1)]
            let he = boundaries[min(unit.phonemeRange.upperBound, boundaries.count - 1)]
            let search = max(0, hs - 1) ..< min(heard.count, he + 1)
            let (runCount, runRange) = PhoneticAlignment.symbolRun(in: heard, searchRange: search, target: unit.symbol)
            if runCount == 1 {
                let conf = spanConfidence(probs: probs, range: runRange)
                let threshold = unit.phonemeRange.lowerBound < onsetSymbolCount ? onsetConfirmedConfidence : minimumConfirmedConfidence
                issuesByWord[unit.wordIndex].append(PronunciationIssue(
                    kind: .missingShadda(letter: String(unit.symbol)),
                    certainty: conf >= threshold ? .confirmed : .uncertain,
                    confidence: conf,
                    expectedOffset: unit.phonemeRange.lowerBound
                ))
            }
        }

        // 2. Inspect non-equal alignment opcodes for clear vowel, consonant, dropped and added errors.
        let allowedRuleChars = PhoneticAlignment.longVowels
            .union(PhoneticAlignment.tajweedMarkers)
            .union(PhoneticAlignment.nasalLetters)

        for op in opcodes where op.kind != .equal {
            let i1 = op.expectedRange.lowerBound
            let i2 = op.expectedRange.upperBound
            let j1 = op.heardRange.lowerBound
            let j2 = op.heardRange.upperBound
            let expSlice = expected[i1 ..< i2]
            let gotSlice = heard[j1 ..< j2]

            // Skip differences wholly inside tajweed rule spans whose heard characters are length/rule variants.
            if i2 > i1, (i1 ..< i2).allSatisfy({ coveredByTajweed[$0] }) {
                let allowed = Set(expSlice).union(allowedRuleChars)
                if gotSlice.isEmpty || gotSlice.allSatisfy({ allowed.contains($0) }) {
                    continue
                }
            }
            // Skip pure madd extensions adjacent to a madd unit (V5 judges madd length).
            if op.kind == .insert, reference.units.contains(where: { unit in
                unit.kind == .madd && unit.phonemeRange.lowerBound <= i1 && i1 <= unit.phonemeRange.upperBound
                    && gotSlice.allSatisfy { ch in ch == unit.symbol }
            }) {
                continue
            }

            let expCore = PhoneticAlignment.stripLengthAndTajweedMarks(expSlice)
            let gotCore = PhoneticAlignment.stripLengthAndTajweedMarks(gotSlice)
            if expCore == gotCore {
                continue // Only length or tajweed markers differed.
            }

            let wordIndex = wordIndex(for: i1, in: reference.words)
            guard wordIndex >= 0, wordIndex < issuesByWord.count else { continue }

            let confidence = spanConfidence(probs: probs, range: j1 ..< j2)
            let threshold = i1 < onsetSymbolCount ? onsetConfirmedConfidence : minimumConfirmedConfidence
            let certainty: PronunciationIssue.Certainty = confidence >= threshold ? .confirmed : .uncertain

            switch op.kind {
            case .replace:
                if expCore.count == 1, gotCore.count == 1,
                   let expScalar = expCore.first, let gotScalar = gotCore.first,
                   let expVowel = PhoneticVowel(scalar: expScalar),
                   let gotVowel = PhoneticVowel(scalar: gotScalar)
                {
                    issuesByWord[wordIndex].append(PronunciationIssue(
                        kind: .wrongVowel(expected: expVowel, heard: gotVowel),
                        certainty: certainty,
                        confidence: confidence,
                        expectedOffset: i1
                    ))
                } else {
                    issuesByWord[wordIndex].append(PronunciationIssue(
                        kind: .wrongConsonant(
                            expected: PhoneticAlignment.string(expSlice),
                            heard: PhoneticAlignment.string(gotSlice)
                        ),
                        certainty: certainty,
                        confidence: confidence,
                        expectedOffset: i1
                    ))
                }

            case .delete:
                // A single omitted vowel sign is within CTC frame noise; do not flag.
                if expSlice.count == 1, let only = expSlice.first,
                   PhoneticAlignment.longVowels.contains(only) || PhoneticAlignment.harakat.contains(only)
                {
                    continue
                }
                issuesByWord[wordIndex].append(PronunciationIssue(
                    kind: .droppedSound(expected: PhoneticAlignment.string(expSlice)),
                    certainty: certainty,
                    confidence: confidence,
                    expectedOffset: i1
                ))

            case .insert:
                // Ignore audio before the first word or after the last word.
                if i1 == 0 || i1 == expected.count {
                    continue
                }
                // Pure long-vowel insertion is a madd rule (V5), not a V4 consonant/vowel mistake.
                if gotSlice.allSatisfy({ PhoneticAlignment.longVowels.contains($0) }) {
                    continue
                }
                // Single extra short vowel is within CTC noise.
                if gotSlice.count == 1, let only = gotSlice.first, PhoneticAlignment.harakat.contains(only) {
                    continue
                }
                issuesByWord[wordIndex].append(PronunciationIssue(
                    kind: .addedSound(heard: PhoneticAlignment.string(gotSlice)),
                    certainty: certainty,
                    confidence: confidence,
                    expectedOffset: i1
                ))

            case .equal:
                break
            }
        }

        // 3. Detect completely skipped words (<= 25% of expected sounds heard).
        for (idx, word) in reference.words.enumerated() {
            let expLen = word.phonemeRange.count
            guard expLen > 0 else { continue }
            let hs = boundaries[word.phonemeRange.lowerBound]
            let he = boundaries[word.phonemeRange.upperBound]
            if he - hs <= max(0, expLen / 4) {
                let conf = spanConfidence(probs: probs, range: hs ..< he)
                // If the whole transcription is empty, the user didn't speak or mic was silent -> uncertain.
                let certainty: PronunciationIssue.Certainty = !heard.isEmpty && conf >= minimumConfirmedConfidence ? .confirmed : .uncertain
                issuesByWord[idx] = [PronunciationIssue(
                    kind: .wordNotHeard,
                    certainty: certainty,
                    confidence: conf,
                    expectedOffset: word.phonemeRange.lowerBound
                )]
            }
        }

        let wordResults: [WordPronunciationAssessment] = reference.words.enumerated().map { idx, word in
            let hs = boundaries[word.phonemeRange.lowerBound]
            let he = boundaries[word.phonemeRange.upperBound]
            let expStr = PhoneticAlignment.string(expected[word.phonemeRange])
            let gotStr = hs < he ? PhoneticAlignment.string(heard[hs ..< he]) : ""
            let issues = issuesByWord[idx]
            let status: WordPronunciationAssessment.Status = if issues.contains(where: { $0.certainty == .confirmed }) {
                .mistake
            } else if !issues.isEmpty {
                .uncertain
            } else {
                .correct
            }
            return WordPronunciationAssessment(
                wordIndex: word.wordIndex,
                wordNumber: word.wordNumber,
                displayText: word.displayText,
                expectedPhonemes: expStr,
                heardPhonemes: gotStr,
                status: status,
                issues: issues
            )
        }

        return PronunciationAssessment(
            expectedPhonemes: reference.phonemes,
            heardPhonemes: transcription.text,
            phonemeMatchRate: matchRate,
            words: wordResults
        )
    }

    // MARK: Private

    private func wordIndex(for phonemeIndex: Int, in words: [WordPhoneticSpan]) -> Int {
        for (idx, word) in words.enumerated() where word.phonemeRange.contains(phonemeIndex) {
            return idx
        }
        return max(0, words.count - 1)
    }

    /// Confidence over the exact heard span `range`; when `range` is empty (a deletion), falls back
    /// to the minimum probability of the immediately adjacent heard symbols (or 0 if none).
    private func spanConfidence(probs: [Float], range: Range<Int>) -> Float {
        guard !probs.isEmpty else { return 0 }
        let lo = max(0, min(probs.count, range.lowerBound))
        let hi = max(lo, min(probs.count, range.upperBound))
        if lo < hi {
            return probs[lo ..< hi].min() ?? 0
        }
        let neighborLo = max(0, lo - 1)
        let neighborHi = min(probs.count, lo + 1)
        guard neighborLo < neighborHi else { return 0 }
        return probs[neighborLo ..< neighborHi].min() ?? 0
    }
}
