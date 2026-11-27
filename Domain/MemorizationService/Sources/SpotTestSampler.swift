//
//  SpotTestSampler.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import QuranKit

/// SplitMix64 deterministic generator for reproducible spot tests (not for cryptography).
public struct SpotTestRNG: RandomNumberGenerator, Sendable {
    // MARK: Lifecycle

    public init(seed: UInt64) {
        state = seed
    }

    // MARK: Public

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    // MARK: Private

    private var state: UInt64
}

/// Pure, seeded random-start sampler for H4 spot tests.
public enum SpotTestSampler {
    // MARK: Public

    /// Samples up to `count` random-start questions from `pool` deterministically for `seed`.
    ///
    /// Rules:
    /// - Questions never bridge across gaps between non-contiguous ranges in `pool`.
    /// - Prefers non-overlapping spans first; if `pool` is smaller than `count * length`, falls
    ///   back to unused start verses so every sampled question has a distinct start verse.
    /// - Returns empty when `pool` is empty or `count <= 0`.
    public static func sampleQuestions(
        from pool: AyahRangeSet,
        length: SpotTestQuestionLength,
        count: Int,
        seed: UInt64,
        lineSpans: [AyahNumber: VerseLineSpan] = [:]
    ) -> [SpotTestQuestion] {
        guard !pool.isEmpty, count > 0 else { return [] }
        let clampedLength = length.clamped

        struct Candidate {
            let blockIndex: Int
            let startIndex: Int
            let passage: Passage
            let lineCount: Int?
        }

        var candidates: [Candidate] = []
        for (blockIndex, range) in pool.ranges.enumerated() {
            let blockVerses = range.verses
            guard !blockVerses.isEmpty else { continue }
            for startIndex in blockVerses.indices {
                let (endIndex, lineCount) = spanEnd(
                    in: blockVerses,
                    from: startIndex,
                    length: clampedLength,
                    lineSpans: lineSpans
                )
                candidates.append(
                    Candidate(
                        blockIndex: blockIndex,
                        startIndex: startIndex,
                        passage: Passage(blockVerses[startIndex], blockVerses[endIndex]),
                        lineCount: lineCount
                    )
                )
            }
        }

        guard !candidates.isEmpty else { return [] }

        var rng = SpotTestRNG(seed: seed)
        candidates.shuffle(using: &rng)

        var chosen: [Candidate] = []
        var usedStarts: Set<AyahNumber> = []

        // First pass: pick non-overlapping questions so a test covers distinct portions of the pool.
        for candidate in candidates where chosen.count < count {
            let start = candidate.passage.first
            guard !usedStarts.contains(start) else { continue }
            let overlaps = chosen.contains { existing in
                candidate.passage.first <= existing.passage.last && candidate.passage.last >= existing.passage.first
            }
            if !overlaps {
                chosen.append(candidate)
                usedStarts.insert(start)
            }
        }

        // Second pass: if the pool is small, fill remaining slots with distinct start verses.
        if chosen.count < count {
            for candidate in candidates where chosen.count < count {
                let start = candidate.passage.first
                guard !usedStarts.contains(start) else { continue }
                chosen.append(candidate)
                usedStarts.insert(start)
            }
        }

        return chosen.enumerated().map { index, candidate in
            SpotTestQuestion(id: index, passage: candidate.passage, targetLineCount: candidate.lineCount)
        }
    }

    // MARK: Private

    private struct PageLine: Hashable {
        let page: Int
        let line: Int
    }

    private static let defaultLinesPerPage = 15.0

    private static func spanEnd(
        in block: [AyahNumber],
        from startIndex: Int,
        length: SpotTestQuestionLength,
        lineSpans: [AyahNumber: VerseLineSpan]
    ) -> (endIndex: Int, lineCount: Int?) {
        switch length {
        case .ayahs(let targetAyahs):
            let end = min(block.count - 1, startIndex + max(1, targetAyahs) - 1)
            return (end, nil)

        case .lines(let targetLines):
            let target = max(1, targetLines)
            if lineSpans[block[startIndex]] != nil {
                var seenLines: Set<PageLine> = []
                var end = startIndex
                for index in startIndex ..< block.count {
                    end = index
                    let verse = block[index]
                    if let span = lineSpans[verse] {
                        for line in span.firstLine ... span.lastLine {
                            seenLines.insert(PageLine(page: span.page, line: line))
                        }
                    } else {
                        // Missing geometry mid-span: treat as 1 fallback line so loop terminates cleanly.
                        seenLines.insert(PageLine(page: verse.page.pageNumber, line: -(index + 1)))
                    }
                    if seenLines.count >= target {
                        break
                    }
                }
                return (end, max(1, seenLines.count))
            } else {
                // Fallback estimate when Mushaf line geometry is not supplied (e.g. pure unit tests):
                // Madani Mushaf pages have 15 lines.
                var accumulatedLines = 0.0
                var end = startIndex
                for index in startIndex ..< block.count {
                    end = index
                    let versesOnPage = max(1, block[index].page.verses.count)
                    accumulatedLines += defaultLinesPerPage / Double(versesOnPage)
                    if accumulatedLines >= Double(target) {
                        break
                    }
                }
                return (end, max(1, Int(accumulatedLines.rounded())))
            }
        }
    }
}
