//
//  AyahWordTimings.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import Foundation

/// When a reciter recites one word, in seconds into the audio file.
public struct WordTiming: Hashable, Sendable {
    // MARK: Lifecycle

    public init(word: Int, start: TimeInterval, end: TimeInterval) {
        self.word = word
        self.start = start
        self.end = end
    }

    // MARK: Public

    /// The word's number in its ayah, from 1, not counting the ayah-number marker.
    public let word: Int
    public let start: TimeInterval
    public let end: TimeInterval
}

/// The recited words of one ayah, in recitation order. A reciter can go back and repeat words,
/// so a word number can appear more than once.
public struct AyahWordTimings: Hashable, Sendable {
    // MARK: Lifecycle

    public init(_ words: [WordTiming]) {
        // Recitation order is start order; sorting guards against data that isn't.
        self.words = words.sorted { $0.start < $1.start }
    }

    // MARK: Public

    public let words: [WordTiming]

    /// The word being recited at `time` seconds into the audio file: the last word to start by
    /// then, so a pause between words keeps the previous word. `nil` before the first word starts.
    public func word(at time: TimeInterval) -> Int? {
        // Binary search for the first word starting after `time`.
        var low = 0
        var high = words.count
        while low < high {
            let middle = (low + high) / 2
            if words[middle].start <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low == 0 ? nil : words[low - 1].word
    }
}
