//
//  PassageSplitter.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import QuranKit

/// Splits a declared range into hafiz-sized review passages (roadmap §4, H3).
///
/// Rules:
/// - Never merges across sura boundaries (short suras like Al-Ikhlas, Al-Falaq, An-Nas stay distinct passages).
/// - Multi-page suras split at page boundaries.
/// - Any single sura-on-page chunk with more than `maxVersesPerChunk` verses splits into roughly equal halves
///   (~half a page), keeping each passage concise to recite in one go.
public enum PassageSplitter {
    public static let maxVersesPerChunk = 10

    public static func defaultPassages(covering range: ClosedRange<AyahNumber>) -> [Passage] {
        let verses = range.verses
        guard !verses.isEmpty else { return [] }

        var chunks: [[AyahNumber]] = []
        var current: [AyahNumber] = [verses[0]]
        for verse in verses.dropFirst() {
            let previous = current[current.count - 1]
            if verse.sura == previous.sura, verse.page == previous.page {
                current.append(verse)
            } else {
                chunks.append(current)
                current = [verse]
            }
        }
        chunks.append(current)

        var passages: [Passage] = []
        for chunk in chunks {
            if chunk.count <= maxVersesPerChunk {
                passages.append(Passage(chunk[0], chunk[chunk.count - 1]))
            } else {
                let parts = Int(ceil(Double(chunk.count) / Double(maxVersesPerChunk)))
                var start = 0
                for part in 0 ..< parts {
                    let remainingVerses = chunk.count - start
                    let remainingParts = parts - part
                    let size = Int(ceil(Double(remainingVerses) / Double(remainingParts)))
                    let end = min(chunk.count, start + size) - 1
                    passages.append(Passage(chunk[start], chunk[end]))
                    start = end + 1
                }
            }
        }
        return passages
    }

    public static func defaultPassages(for rangeSet: AyahRangeSet) -> [Passage] {
        rangeSet.ranges.flatMap(defaultPassages(covering:))
    }
}
