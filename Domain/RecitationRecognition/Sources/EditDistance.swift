//
//  EditDistance.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Foundation

/// Levenshtein distances over letter sequences (normalized UTF-16 code units). The loops use
/// unsafe buffers: the matcher runs them for every shortlisted verse of every query.
enum EditDistance {
    /// Insertions, deletions and substitutions that turn `a` into `b`.
    static func distance(_ a: [UInt16], _ b: [UInt16]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        return lastRow(a, b, freeStart: false) { row in row[b.count] }
    }

    /// 1 − distance / the longer length; 1 for two empty sequences.
    static func ratio(_ a: [UInt16], _ b: [UInt16]) -> Double {
        let longest = max(a.count, b.count)
        return longest == 0 ? 1 : 1 - Double(distance(a, b)) / Double(longest)
    }

    /// How well `query` fits as a contiguous part of `text`: 1 − (the smallest distance between
    /// `query` and any substring of `text`) / `query`'s length. 1 when `text` contains `query`.
    static func fragmentFit(_ query: [UInt16], in text: [UInt16]) -> Double {
        guard !query.isEmpty, !text.isEmpty else { return 0 }
        let best = lastRow(query, text, freeStart: true) { row in row.min() ?? query.count }
        return max(0, 1 - Double(best) / Double(query.count))
    }

    /// Runs the dynamic program with rows over `a` and columns over `b`, and passes its last row to
    /// `result`. With `freeStart`, a match may start at any column of `b` at no cost.
    private static func lastRow(
        _ a: [UInt16],
        _ b: [UInt16],
        freeStart: Bool,
        result: (UnsafeMutableBufferPointer<Int>) -> Int
    ) -> Int {
        let width = b.count + 1
        let storage = UnsafeMutableBufferPointer<Int>.allocate(capacity: width * 2)
        defer { storage.deallocate() }
        var previous = UnsafeMutableBufferPointer(rebasing: storage[0 ..< width])
        var current = UnsafeMutableBufferPointer(rebasing: storage[width ..< width * 2])
        for j in 0 ..< width {
            previous[j] = freeStart ? 0 : j
        }
        a.withUnsafeBufferPointer { a in
            b.withUnsafeBufferPointer { b in
                for i in 1 ... a.count {
                    current[0] = i
                    let x = a[i - 1]
                    var left = i
                    for j in 1 ..< width {
                        let substitution = previous[j - 1] + (x == b[j - 1] ? 0 : 1)
                        let value = min(substitution, previous[j] + 1, left + 1)
                        current[j] = value
                        left = value
                    }
                    swap(&previous, &current)
                }
            }
        }
        return result(previous)
    }
}
