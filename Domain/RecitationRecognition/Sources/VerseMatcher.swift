//
//  VerseMatcher.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Foundation
import QuranKit

/// One ranked answer: a verse, or a run of consecutive verses of one sura.
public struct VerseCandidate: Equatable, Sendable {
    /// The first verse recited.
    public let firstVerse: AyahNumber
    /// The last verse recited; `firstVerse` for a single verse.
    public let lastVerse: AyahNumber
    /// 0–1: the whole-text similarity, or for a fragment of a longer text, mostly how well it fits.
    public let score: Double
    /// 0–1: how well the transcript fits as a contiguous part of the candidate's text.
    public let fragmentFit: Double
}

/// The matcher's answer for one transcript.
public struct VerseIdentification: Equatable, Sendable {
    public let transcript: String
    /// Best first. Verses with identical text (such as the 31 times of 55:13) score the same and
    /// keep Quran order; audio cannot tell them apart.
    public let candidates: [VerseCandidate]
    /// Whether the first candidate passed the trust gate. Never show an unconfident answer as the
    /// verse that was recited; offer the candidates instead.
    public let isConfident: Bool
    /// How many letters of the transcript were matched (basmala removed). Below
    /// `VerseMatcher.minimumTrustedLetters` the transcript is too short to offer even unconfident
    /// candidates, such as the stray letters a model hears in silence or noise.
    public let letterCount: Int

    /// Whether the candidates are worth showing: trusted, or from enough letters to be a real try.
    public var isWorthOffering: Bool {
        !candidates.isEmpty && (isConfident || letterCount >= VerseMatcher.minimumTrustedLetters)
    }
}

/// Identifies the verse(s) a transcript recites by comparing it with every verse's plain text.
///
/// Retrieval: the verses sharing the most letter pairs with the transcript. Scoring: the edit-distance
/// ratio of the whole text, and for a transcript shorter than the verse, how well it fits as a part of
/// it. Runs of two or three consecutive verses around the best singles are scored too. The trust gate,
/// the fragment blend and the minimum letter count are Tilawi's `@tilawi/quran-asr` constants (MIT),
/// chosen there on 600 EveryAyah recitations and a noisy-fragment sweep.
public final class VerseMatcher: Sendable {
    // MARK: Lifecycle

    /// `verses`: every verse with its plain imla'i text (`GRDBQuranVerseTextPersistence.searchTextOfAllVerses`).
    /// The search text puts the basmala before verse 1 of every sura but 1 and 9; it is not part of
    /// those verses, so it is removed here (and from a transcript that starts with it).
    public init(verses: [(verse: AyahNumber, text: String)]) {
        let entries = verses.map { verse, text in
            var letters = ArabicMatchNormalizer.letters(text)
            let sura = verse.sura.suraNumber
            if verse.ayah == 1, sura != 1, sura != 9, letters.starts(with: Self.basmala), letters.count > Self.basmala.count {
                letters.removeFirst(Self.basmala.count)
            }
            return Entry(verse: verse, letters: letters)
        }
        var postings: [UInt32: [Int32]] = [:]
        for (index, entry) in entries.enumerated() {
            for bigram in Set(Self.bigrams(entry.letters)) {
                postings[bigram, default: []].append(Int32(index))
            }
        }
        self.entries = entries
        self.postings = postings
        indexByVerse = Dictionary(entries.enumerated().map { ($1.verse, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Public

    public static let minimumTrustedLetters = 5

    public func identify(transcript: String, limit: Int = 5) -> VerseIdentification {
        let query = Array(Self.removingLeadingBasmala(ArabicMatchNormalizer.letters(transcript)).prefix(Self.maximumQueryLetters))
        guard query.count >= 2 else {
            return VerseIdentification(transcript: transcript, candidates: [], isConfident: false, letterCount: query.count)
        }
        var scored = shortlist(query).map { score(query, range: $0 ... $0) }
        scored.sort(by: Self.isRankedBefore)
        let spanSeeds = scored.prefix(Self.spanSeedCount).map(\.range.lowerBound)
        var seen = Set(scored.map(\.range))
        for seed in spanSeeds {
            for range in spans(around: seed) where seen.insert(range).inserted {
                scored.append(score(query, range: range))
            }
        }
        scored.sort(by: Self.isRankedBefore)

        let candidates = scored.prefix(max(limit, 1)).map { item in
            VerseCandidate(
                firstVerse: entries[item.range.lowerBound].verse,
                lastVerse: entries[item.range.upperBound].verse,
                score: item.score,
                fragmentFit: item.fit
            )
        }
        return VerseIdentification(
            transcript: transcript,
            candidates: Array(candidates.prefix(limit)),
            isConfident: isTrusted(scored, queryLength: query.count),
            letterCount: query.count
        )
    }

    // MARK: Internal

    /// The letters `verse` is matched against (normalized, basmala removed), for tests.
    func matchingLetters(of verse: AyahNumber) -> [UInt16]? {
        indexByVerse[verse].map { entries[$0].letters }
    }

    // MARK: Private

    private struct Entry: Sendable {
        let verse: AyahNumber
        let letters: [UInt16]
    }

    private struct Scored {
        let range: ClosedRange<Int>
        let letters: [UInt16]
        let score: Double
        let fit: Double
    }

    /// About 15–20 s of recitation: enough to tell any passage apart, and it bounds the cost of a
    /// long recording (each comparison is query length × verse length).
    private static let maximumQueryLetters = 240
    private static let shortlistSize = 64
    private static let spanSeedCount = 4
    private static let fragmentBlend = 0.82
    private static let trustedScore = 0.8
    private static let fragmentTrustFloor = 0.62
    private static let fragmentFitMinimum = 0.75
    private static let fragmentFitMarginMinimum = 0.15
    private static let fragmentMinimumLetters = 12

    private let entries: [Entry]
    private let postings: [UInt32: [Int32]]
    private let indexByVerse: [AyahNumber: Int]

    private static let basmala = ArabicMatchNormalizer.letters("بسم الله الرحمن الرحيم")

    /// A transcript that opens with the basmala and goes on to a verse is matched without it; the
    /// basmala alone stays (it is 1:1). Up to two misheard letters still count as the basmala.
    private static func removingLeadingBasmala(_ letters: [UInt16]) -> [UInt16] {
        guard letters.count >= basmala.count + minimumTrustedLetters,
              EditDistance.distance(Array(letters.prefix(basmala.count)), basmala) <= 2
        else {
            return letters
        }
        return Array(letters.dropFirst(basmala.count))
    }

    private static func bigrams(_ letters: [UInt16]) -> [UInt32] {
        guard letters.count >= 2 else { return [] }
        return (0 ..< letters.count - 1).map { UInt32(letters[$0]) << 16 | UInt32(letters[$0 + 1]) }
    }

    private static func isRankedBefore(_ lhs: Scored, _ rhs: Scored) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.range.lowerBound != rhs.range.lowerBound { return lhs.range.lowerBound < rhs.range.lowerBound }
        return lhs.range.upperBound < rhs.range.upperBound
    }

    /// Indexes of the verses that share the most distinct letter pairs with the query.
    private func shortlist(_ query: [UInt16]) -> [Int] {
        var counts = [Int32](repeating: 0, count: entries.count)
        for bigram in Set(Self.bigrams(query)) {
            for index in postings[bigram] ?? [] {
                counts[Int(index)] += 1
            }
        }
        let ranked = counts.indices.filter { counts[$0] > 0 }.sorted {
            counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1
        }
        return Array(ranked.prefix(Self.shortlistSize))
    }

    /// Runs of two or three consecutive verses of the same sura that contain `index`.
    private func spans(around index: Int) -> [ClosedRange<Int>] {
        let sura = entries[index].verse.sura
        var ranges: [ClosedRange<Int>] = []
        for length in 2 ... 3 {
            for start in (index - length + 1) ... index {
                let end = start + length - 1
                guard start >= 0, end < entries.count,
                      entries[start].verse.sura == sura, entries[end].verse.sura == sura
                else {
                    continue
                }
                ranges.append(start ... end)
            }
        }
        return ranges
    }

    private func score(_ query: [UInt16], range: ClosedRange<Int>) -> Scored {
        let letters = range.flatMap { entries[$0].letters }
        let whole = EditDistance.ratio(query, letters)
        guard query.count < letters.count else {
            return Scored(range: range, letters: letters, score: whole, fit: whole)
        }
        let fit = EditDistance.fragmentFit(query, in: letters)
        let blended = Self.fragmentBlend * fit + (1 - Self.fragmentBlend) * whole
        return Scored(range: range, letters: letters, score: max(whole, blended), fit: fit)
    }

    /// Tilawi's gate: a score of 0.8, or a strong, long, unambiguous fragment; at least five letters.
    private func isTrusted(_ ranked: [Scored], queryLength: Int) -> Bool {
        guard let best = ranked.first, queryLength >= Self.minimumTrustedLetters else {
            return false
        }
        if best.score >= Self.trustedScore {
            return true
        }
        // Rivals are candidates with other text that do not overlap the winner's verses.
        let rivals = ranked.dropFirst().filter { $0.letters != best.letters && !$0.range.overlaps(best.range) }
        let fitMargin = best.fit - (rivals.map(\.fit).max() ?? 0)
        return best.score >= Self.fragmentTrustFloor
            && best.fit >= Self.fragmentFitMinimum
            && fitMargin >= Self.fragmentFitMarginMinimum
            && queryLength >= Self.fragmentMinimumLetters
    }
}
