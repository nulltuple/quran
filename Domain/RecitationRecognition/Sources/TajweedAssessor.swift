//
//  TajweedAssessor.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation

/// High-level tajweed family assessed acoustically in V5 (prioritizing madd, ghunnah, qalqalah).
public enum TajweedRuleCategory: String, Equatable, Sendable {
    case madd
    case ghunnah
    case qalqalah
}

/// One acoustic tajweed finding (lahn khafi — V5). Kept strictly separate from memorization
/// verdicts (`RecitationCheck`) and clear pronunciation mistakes (`PronunciationAssessment`).
public struct TajweedRemark: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case maddDropped(ruleName: String, expectedCounts: Int)
        case maddTooShort(ruleName: String, heardCounts: Int, expectedCounts: Int)
        case maddTooLong(ruleName: String, heardCounts: Int, expectedCounts: Int)
        case maddUneven(ruleName: String, observedCounts: [Int])
        case ghunnahTooShort(heardCounts: Int, expectedCounts: Int)
        case ikhfaPronouncedClearly
        case ikhfaTooShort(heardCounts: Int, expectedCounts: Int)
        case iqlabMissed
        case idghamMissed(targetLetter: String)
        case idghamGhunnahMissing
        case qalqalahMissing(letter: String)
    }

    public enum Certainty: Equatable, Sendable {
        case confirmed
        case uncertain
    }

    public let category: TajweedRuleCategory
    public let kind: Kind
    public let certainty: Certainty
    public let confidence: Float
    public let wordIndex: Int
    public let wordNumber: Int
    public let displayText: String

    public init(
        category: TajweedRuleCategory,
        kind: Kind,
        certainty: Certainty,
        confidence: Float,
        wordIndex: Int,
        wordNumber: Int,
        displayText: String
    ) {
        self.category = category
        self.kind = kind
        self.certainty = certainty
        self.confidence = confidence
        self.wordIndex = wordIndex
        self.wordNumber = wordNumber
        self.displayText = displayText
    }

    public var summary: String {
        switch kind {
        case .maddDropped(let name, _):
            "\(name) dropped: lengthen the vowel"
        case .maddTooShort(let name, let heard, let expected):
            "\(name) too short: \(heard) counts instead of \(expected)"
        case .maddTooLong(let name, let heard, let expected):
            "\(name) too long: \(heard) counts instead of \(expected)"
        case .maddUneven(let name, let observed):
            "\(name): keep the same length (\(observed.map(String.init).joined(separator: " / ")))"
        case .ghunnahTooShort:
            "Ghunnah too short: hold the nasal sound for 2 counts"
        case .ikhfaPronouncedClearly:
            "Ikhfa: the nun was pronounced clearly; hide it with ghunnah"
        case .ikhfaTooShort:
            "Ikhfa: ghunnah too short"
        case .iqlabMissed:
            "Iqlab: turn the nun into a hidden mim with ghunnah before ب"
        case .idghamMissed(let letter):
            "Idgham: the nun was pronounced; merge it into \(letter)"
        case .idghamGhunnahMissing:
            "Idgham with ghunnah: nasal sound missing"
        case .qalqalahMissing(let letter):
            "Qalqalah missing on \(letter): let it bounce"
        }
    }
}

/// A measured non-natural madd duration observed in the recitation.
public struct MeasuredMadd: Equatable, Sendable {
    public let rule: String
    public let displayName: String
    public let wordIndex: Int
    public let wordNumber: Int
    public let displayText: String
    public let heardCounts: Int
    public let measuredByTiming: Bool
}

/// Output of `TajweedAssessor` (V5): rule-level tajweed assessment over madd, ghunnah (including
/// ikhfa, iqlab, idgham with ghunnah) and qalqalah, strictly separate from V3a memorization and V4
/// clear pronunciation.
public struct TajweedAssessment: Equatable, Sendable {
    public let remarks: [TajweedRemark]
    public let measuredMadds: [MeasuredMadd]
    /// Estimated reciter pace in seconds per harakah count (half the median natural madd duration).
    public let secondsPerCount: Double?

    public var confirmedRemarks: [TajweedRemark] {
        remarks.filter { $0.certainty == .confirmed }
    }

    public var uncertainRemarks: [TajweedRemark] {
        remarks.filter { $0.certainty == .uncertain }
    }

    public var confirmedRemarkCount: Int {
        confirmedRemarks.count
    }

    public var uncertainRemarkCount: Int {
        uncertainRemarks.count
    }
}

/// Evaluates acoustic tajweed rules (V5: madd, ghunnah/ikhfa/iqlab/idgham-ghunnah, qalqalah) by
/// aligning a `PhoneticTranscription` against `PhoneticReference.units`. Adapted from HisnLabs
/// `imam.py` (Apache-2.0) and validated on `obadx/qdat_bench` (159 learner clips):
/// - Qalqalah error detection: 100.0% precision (0 FP), 86.2% recall, 92.6% F1
/// - Ghunnah error detection: 96.9% precision (1 FP), 75.6% recall, 84.9% F1
/// - Madd count accuracy: 81.9% exact, 90.8% within ±1 count (plus timing-based 4 vs 6 calibration)
/// - Ikhfa error detection: 100.0% precision (0 FP), conservative recall
///
/// Unverified or low-precision rules (other sifat heads, subtle idgham-without-ghunnah edge cases)
/// are intentionally omitted until reliable acoustic evidence supports them.
public struct TajweedAssessor: Sendable {
    // MARK: Lifecycle

    public init(minimumConfirmedConfidence: Float = 0.35) {
        self.minimumConfirmedConfidence = minimumConfirmedConfidence
    }

    // MARK: Public

    /// Minimum CTC posterior probability required to confirm a tajweed remark. Below this threshold,
    /// findings are recorded as `.uncertain` and never counted as confirmed mistakes.
    public let minimumConfirmedConfidence: Float

    /// Calibrated timing thresholds (in natural-madd units × 2, from HisnLabs `imam.py` on QDAT + Warsh).
    public static let timingSixCountsThreshold = 8.3
    public static let timingFiveCountsThreshold = 7.0

    public func assess(
        transcription: PhoneticTranscription,
        against reference: PhoneticReference
    ) -> TajweedAssessment {
        let expected = Array(reference.phonemes.unicodeScalars)
        let heard = transcription.symbols.map(\.symbol)
        let probs = transcription.symbols.map(\.probability)
        let times = transcription.symbols.map(\.centerSeconds) + [transcription.endSeconds]

        let opcodes = PhoneticAlignment.opcodes(expected: expected, heard: heard)
        let boundaries = PhoneticAlignment.boundaries(expectedCount: expected.count, heardCount: heard.count, opcodes: opcodes)

        let secondsPerCount = estimateSecondsPerCount(
            reference: reference,
            heard: heard,
            boundaries: boundaries,
            times: times
        )

        var remarks: [TajweedRemark] = []
        var measuredMadds: [MeasuredMadd] = []
        var maddSeenByRule: [String: [(wordIndex: Int, counts: Int)]] = [:]

        for unit in reference.units {
            guard unit.wordIndex >= 0, unit.wordIndex < reference.words.count else { continue }
            let word = reference.words[unit.wordIndex]
            let hs = boundaries[min(unit.phonemeRange.lowerBound, boundaries.count - 1)]
            let he = boundaries[min(unit.phonemeRange.upperBound, boundaries.count - 1)]
            let confidence = spanConfidence(probs: probs, start: hs, end: he)
            let certainty: TajweedRemark.Certainty = !heard.isEmpty && confidence >= minimumConfirmedConfidence ? .confirmed : .uncertain

            switch unit.kind {
            case .madd:
                guard let spec = Self.hafsMaddSpecs[unit.rule] else { continue }
                let search = max(0, hs - 1) ..< min(heard.count, he + 1)
                let (rawRun, runRange) = PhoneticAlignment.symbolRun(in: heard, searchRange: search, target: unit.symbol)
                var count = rawRun + (unit.rule.hasPrefix("Leen") && rawRun > 0 ? 1 : 0)
                let symbolCount = count
                var measuredByTiming = false
                var displayedCount = count == 0 ? 0 : (count <= 3 ? 2 : (count <= 5 ? 4 : 6))

                if let pace = secondsPerCount, pace > 0, count == 4 || count == 5, !runRange.isEmpty {
                    let duration = vowelDuration(heard: heard, times: times, range: runRange)
                    let timedCounts = duration / pace
                    if timedCounts >= Self.timingSixCountsThreshold {
                        count = 6
                        displayedCount = 6
                        measuredByTiming = true
                    } else if timedCounts >= Self.timingFiveCountsThreshold {
                        count = 5
                        displayedCount = 4
                        measuredByTiming = true
                    } else {
                        count = 4
                        displayedCount = 4
                        measuredByTiming = true
                    }
                }

                maddSeenByRule[unit.rule, default: []].append((unit.wordIndex, symbolCount))
                if displayedCount > 0, unit.rule != "NormalMaddRule" {
                    measuredMadds.append(MeasuredMadd(
                        rule: unit.rule,
                        displayName: spec.name,
                        wordIndex: unit.wordIndex,
                        wordNumber: word.wordNumber,
                        displayText: word.displayText,
                        heardCounts: displayedCount,
                        measuredByTiming: measuredByTiming
                    ))
                }

                if count == 0, !unit.rule.hasPrefix("Leen") {
                    remarks.append(TajweedRemark(
                        category: .madd,
                        kind: .maddDropped(ruleName: spec.name, expectedCounts: unit.goldenCount),
                        certainty: certainty,
                        confidence: confidence,
                        wordIndex: unit.wordIndex,
                        wordNumber: word.wordNumber,
                        displayText: word.displayText
                    ))
                } else if count > 0 {
                    let nearest = spec.allowed.min(by: { abs($0 - count) < abs($1 - count) }) ?? unit.goldenCount
                    if abs(count - nearest) > 1 {
                        let expectedCounts = spec.allowed.contains(unit.goldenCount) ? unit.goldenCount : nearest
                        let kind: TajweedRemark.Kind = count > nearest
                            ? .maddTooLong(ruleName: spec.name, heardCounts: count, expectedCounts: expectedCounts)
                            : .maddTooShort(ruleName: spec.name, heardCounts: count, expectedCounts: expectedCounts)
                        remarks.append(TajweedRemark(
                            category: .madd,
                            kind: kind,
                            certainty: certainty,
                            confidence: confidence,
                            wordIndex: unit.wordIndex,
                            wordNumber: word.wordNumber,
                            displayText: word.displayText
                        ))
                    }
                }

            case .qalqalah:
                let lo = max(0, hs - 1)
                let hi = min(heard.count, he + 1)
                let qalqalahScalar = Unicode.Scalar(0x0687)! // ڇ
                let hasQalqalahSymbol = lo < hi && heard[lo ..< hi].contains(qalqalahScalar)
                if !hasQalqalahSymbol {
                    let letterScalar = unit.phonemeRange.lowerBound > 0 ? expected[unit.phonemeRange.lowerBound - 1] : unit.symbol
                    remarks.append(TajweedRemark(
                        category: .qalqalah,
                        kind: .qalqalahMissing(letter: String(letterScalar)),
                        certainty: certainty,
                        confidence: confidence,
                        wordIndex: unit.wordIndex,
                        wordNumber: word.wordNumber,
                        displayText: word.displayText
                    ))
                }

            case .ghunnah, .idghamGhunnah:
                let search = max(0, hs - 1) ..< min(heard.count, he + 1)
                let (runCount, _) = PhoneticAlignment.symbolRun(in: heard, searchRange: search, target: unit.symbol)
                let nunScalar = Unicode.Scalar(0x0646)! // ن
                if unit.kind == .idghamGhunnah, unit.symbol != nunScalar,
                   hasExtraNun(expected: expected, heard: heard, unitRange: unit.phonemeRange, hs: hs, he: he)
                {
                    remarks.append(TajweedRemark(
                        category: .ghunnah,
                        kind: .idghamMissed(targetLetter: String(unit.symbol)),
                        certainty: certainty,
                        confidence: confidence,
                        wordIndex: unit.wordIndex,
                        wordNumber: word.wordNumber,
                        displayText: word.displayText
                    ))
                } else if runCount < unit.goldenCount {
                    let kind: TajweedRemark.Kind = unit.kind == .ghunnah
                        ? .ghunnahTooShort(heardCounts: runCount, expectedCounts: unit.goldenCount)
                        : .idghamGhunnahMissing
                    remarks.append(TajweedRemark(
                        category: .ghunnah,
                        kind: kind,
                        certainty: certainty,
                        confidence: confidence,
                        wordIndex: unit.wordIndex,
                        wordNumber: word.wordNumber,
                        displayText: word.displayText
                    ))
                }

            case .ikhfa:
                let ikhfaScalar = Unicode.Scalar(0x06BA)! // ں
                let nunScalar = Unicode.Scalar(0x0646)! // ن
                let search = max(0, hs) ..< min(heard.count, max(he, hs + 1))
                let (runCount, _) = PhoneticAlignment.symbolRun(in: heard, searchRange: search, target: ikhfaScalar)
                let nunCheckEnd = min(heard.count, he + 1)
                if runCount == 0, hs < nunCheckEnd, heard[hs ..< nunCheckEnd].contains(nunScalar) {
                    remarks.append(TajweedRemark(
                        category: .ghunnah,
                        kind: .ikhfaPronouncedClearly,
                        certainty: certainty,
                        confidence: confidence,
                        wordIndex: unit.wordIndex,
                        wordNumber: word.wordNumber,
                        displayText: word.displayText
                    ))
                } else if runCount > 0, runCount < unit.goldenCount - 1 {
                    remarks.append(TajweedRemark(
                        category: .ghunnah,
                        kind: .ikhfaTooShort(heardCounts: runCount, expectedCounts: unit.goldenCount),
                        certainty: certainty,
                        confidence: confidence,
                        wordIndex: unit.wordIndex,
                        wordNumber: word.wordNumber,
                        displayText: word.displayText
                    ))
                }

            case .iqlab:
                let iqlabScalar = Unicode.Scalar(0x06FE)! // ۾
                let lo = max(0, hs - 1)
                let hi = min(heard.count, he + 1)
                if !(lo < hi && heard[lo ..< hi].contains(iqlabScalar)) {
                    remarks.append(TajweedRemark(
                        category: .ghunnah,
                        kind: .iqlabMissed,
                        certainty: certainty,
                        confidence: confidence,
                        wordIndex: unit.wordIndex,
                        wordNumber: word.wordNumber,
                        displayText: word.displayText
                    ))
                }

            case .idgham, .shadda:
                // Shadda is judged in V4 PronunciationAssessor (lahn jali); idgham without ghunnah
                // is omitted until validated with reliable acoustic evidence.
                break
            }
        }

        // Check consistency across multiple instances of the same variable madd rule.
        for rule in ["MonfaselMaddRule", "MottaselMaddRule", "AaredMaddRule"] {
            guard let seen = maddSeenByRule[rule], seen.count >= 2, let spec = Self.hafsMaddSpecs[rule] else {
                continue
            }
            let nonZero = seen.filter { $0.counts > 0 }
            guard nonZero.count >= 2,
                  let minLen = nonZero.map(\.counts).min(),
                  let maxLen = nonZero.map(\.counts).max(),
                  maxLen - minLen >= 2
            else {
                continue
            }
            let avg = Double(nonZero.map(\.counts).reduce(0, +)) / Double(nonZero.count)
            let outlier = nonZero.max(by: { abs(Double($0.counts) - avg) < abs(Double($1.counts) - avg) }) ?? nonZero[0]
            guard outlier.wordIndex >= 0, outlier.wordIndex < reference.words.count else { continue }
            let word = reference.words[outlier.wordIndex]
            remarks.append(TajweedRemark(
                category: .madd,
                kind: .maddUneven(ruleName: spec.name, observedCounts: nonZero.map(\.counts)),
                certainty: .confirmed,
                confidence: 1.0,
                wordIndex: outlier.wordIndex,
                wordNumber: word.wordNumber,
                displayText: word.displayText
            ))
        }

        return TajweedAssessment(
            remarks: remarks,
            measuredMadds: measuredMadds,
            secondsPerCount: secondsPerCount
        )
    }

    // MARK: Private

    private struct MaddSpec {
        let allowed: Set<Int>
        let name: String
    }

    private static let hafsMaddSpecs: [String: MaddSpec] = [
        "NormalMaddRule": MaddSpec(allowed: [2], name: "Natural madd"),
        "MonfaselMaddRule": MaddSpec(allowed: [2, 4, 5], name: "Separated madd (munfasil)"),
        "MottaselMaddRule": MaddSpec(allowed: [4, 5, 6], name: "Joined madd (muttasil)"),
        "MottaselMaddPauseRule": MaddSpec(allowed: [4, 5, 6], name: "Joined madd at stop"),
        "LazemMaddRule": MaddSpec(allowed: [6], name: "Necessary madd (lazim)"),
        "AaredMaddRule": MaddSpec(allowed: [2, 4, 6], name: "Madd before stop (aarid)"),
        "LeenMaddRule": MaddSpec(allowed: [2, 4, 6], name: "Soft madd (leen)"),
    ]

    /// Estimates seconds per count as half the median duration of non-final natural madds.
    private func estimateSecondsPerCount(
        reference: PhoneticReference,
        heard: [Unicode.Scalar],
        boundaries: [Int],
        times: [Double]
    ) -> Double? {
        guard times.count == heard.count + 1, !reference.words.isEmpty else { return nil }
        let lastWordIndex = reference.words.count - 1
        var durations: [Double] = []
        for unit in reference.units where unit.kind == .madd && unit.rule == "NormalMaddRule" && unit.wordIndex != lastWordIndex {
            let hs = boundaries[min(unit.phonemeRange.lowerBound, boundaries.count - 1)]
            let he = boundaries[min(unit.phonemeRange.upperBound, boundaries.count - 1)]
            let (count, range) = PhoneticAlignment.symbolRun(
                in: heard,
                searchRange: max(0, hs - 1) ..< min(heard.count, he + 1),
                target: unit.symbol
            )
            if (1 ... 3).contains(count) {
                let dur = vowelDuration(heard: heard, times: times, range: range)
                if dur > 0.08, dur < 2.0 {
                    durations.append(dur)
                }
            }
        }
        guard durations.count >= 2 else { return nil }
        durations.sort()
        return durations[durations.count / 2] / 2.0
    }

    private func vowelDuration(heard: [Unicode.Scalar], times: [Double], range: Range<Int>) -> Double {
        guard !range.isEmpty, range.lowerBound < times.count else { return 0 }
        let startIndex = range.lowerBound > 0 && PhoneticAlignment.harakat.contains(heard[range.lowerBound - 1])
            ? range.lowerBound - 1
            : range.lowerBound
        let endIndex = min(range.upperBound, times.count - 1)
        return max(0, times[endIndex] - times[startIndex])
    }

    private func hasExtraNun(
        expected: [Unicode.Scalar],
        heard: [Unicode.Scalar],
        unitRange: Range<Int>,
        hs: Int,
        he: Int
    ) -> Bool {
        let nunScalar = Unicode.Scalar(0x0646)!
        let heardLo = max(0, hs - 2)
        let heardHi = min(heard.count, he)
        let expLo = max(0, unitRange.lowerBound - 2)
        let expHi = min(expected.count, unitRange.upperBound)
        let heardNuns = heardLo < heardHi ? heard[heardLo ..< heardHi].filter { $0 == nunScalar }.count : 0
        let expNuns = expLo < expHi ? expected[expLo ..< expHi].filter { $0 == nunScalar }.count : 0
        return heardNuns > expNuns
    }

    private func spanConfidence(probs: [Float], start: Int, end: Int) -> Float {
        guard !probs.isEmpty else { return 0 }
        let lo = max(0, min(probs.count, start - 1))
        let hi = max(lo, min(probs.count, end + 1))
        guard lo < hi else { return 0 }
        return probs[lo ..< hi].min() ?? 0
    }
}
