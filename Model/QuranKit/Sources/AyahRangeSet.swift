//
//  AyahRangeSet.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation

extension ClosedRange where Bound == AyahNumber {
    /// Number of verses in this inclusive range without allocating an array of every ayah.
    public var verseCount: Int {
        let quran = lowerBound.quran
        if lowerBound.sura == upperBound.sura {
            return upperBound.ayah - lowerBound.ayah + 1
        }
        var total = lowerBound.sura.numberOfVerses - lowerBound.ayah + 1
        if lowerBound.sura.suraNumber + 1 < upperBound.sura.suraNumber {
            for suraNumber in (lowerBound.sura.suraNumber + 1) ..< upperBound.sura.suraNumber {
                if let sura = Sura(quran: quran, suraNumber: suraNumber) {
                    total += sura.numberOfVerses
                }
            }
        }
        total += upperBound.ayah
        return total
    }

    /// Every verse in this range in canonical order.
    public var verses: [AyahNumber] {
        lowerBound.array(to: upperBound)
    }
}

/// Canonical, normalized set of inclusive `AyahNumber` ranges (roadmap §4).
///
/// Adjacent and overlapping ranges are merged so `ranges` is always sorted and disjoint.
/// Edition-free at the verse-coordinate level; callers operate within one `Quran` instance.
public struct AyahRangeSet: Hashable, Sendable {
    // MARK: Lifecycle

    public init(_ ranges: [ClosedRange<AyahNumber>] = []) {
        self.ranges = Self.normalize(ranges)
    }

    public init(_ range: ClosedRange<AyahNumber>) {
        ranges = [range]
    }

    // MARK: Public

    /// Sorted, disjoint, non-adjacent inclusive verse ranges.
    public let ranges: [ClosedRange<AyahNumber>]

    public var isEmpty: Bool {
        ranges.isEmpty
    }

    /// Total number of distinct verses across all ranges.
    public var verseCount: Int {
        ranges.reduce(0) { $0 + $1.verseCount }
    }

    /// Whether `verse` belongs to any range in this set.
    public func contains(_ verse: AyahNumber) -> Bool {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let mid = low + (high - low) / 2
            let range = ranges[mid]
            if verse < range.lowerBound {
                high = mid - 1
            } else if verse > range.upperBound {
                low = mid + 1
            } else {
                return true
            }
        }
        return false
    }

    /// Whether every verse in `range` belongs to this set.
    public func contains(_ range: ClosedRange<AyahNumber>) -> Bool {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let mid = low + (high - low) / 2
            let candidate = ranges[mid]
            if range.lowerBound < candidate.lowerBound {
                high = mid - 1
            } else if range.lowerBound > candidate.upperBound {
                low = mid + 1
            } else {
                return range.upperBound <= candidate.upperBound
            }
        }
        return false
    }

    /// Union of this set and `other`.
    public func union(_ other: AyahRangeSet) -> AyahRangeSet {
        AyahRangeSet(ranges + other.ranges)
    }

    /// Union with a single inclusive verse range.
    public func inserting(_ range: ClosedRange<AyahNumber>) -> AyahRangeSet {
        AyahRangeSet(ranges + [range])
    }

    /// Difference: every verse in `self` that is not in `other`.
    public func subtracting(_ other: AyahRangeSet) -> AyahRangeSet {
        guard !ranges.isEmpty, !other.ranges.isEmpty else {
            return self
        }
        var result: [ClosedRange<AyahNumber>] = []
        var j = 0
        for current in ranges {
            var remainingStart: AyahNumber? = current.lowerBound
            let remainingEnd = current.upperBound

            while j < other.ranges.count, other.ranges[j].upperBound < current.lowerBound {
                j += 1
            }

            var k = j
            while k < other.ranges.count, let start = remainingStart {
                let cut = other.ranges[k]
                if cut.lowerBound > remainingEnd {
                    break
                }
                if cut.lowerBound > start, let beforeCut = cut.lowerBound.previous {
                    result.append(start ... beforeCut)
                }
                if cut.upperBound >= remainingEnd {
                    remainingStart = nil
                } else {
                    remainingStart = cut.upperBound.next
                }
                k += 1
            }

            if let start = remainingStart, start <= remainingEnd {
                result.append(start ... remainingEnd)
            }
        }
        return AyahRangeSet(result)
    }

    /// Difference removing a single inclusive verse range.
    public func subtracting(_ range: ClosedRange<AyahNumber>) -> AyahRangeSet {
        subtracting(AyahRangeSet(range))
    }

    /// Intersection: verses present in both sets.
    public func intersection(_ other: AyahRangeSet) -> AyahRangeSet {
        guard !ranges.isEmpty, !other.ranges.isEmpty else {
            return AyahRangeSet()
        }
        var result: [ClosedRange<AyahNumber>] = []
        var i = 0
        var j = 0
        while i < ranges.count, j < other.ranges.count {
            let lhs = ranges[i]
            let rhs = other.ranges[j]
            let lower = max(lhs.lowerBound, rhs.lowerBound)
            let upper = min(lhs.upperBound, rhs.upperBound)
            if lower <= upper {
                result.append(lower ... upper)
            }
            if lhs.upperBound < rhs.upperBound {
                i += 1
            } else {
                j += 1
            }
        }
        return AyahRangeSet(result)
    }

    // MARK: Private

    private static func normalize(_ input: [ClosedRange<AyahNumber>]) -> [ClosedRange<AyahNumber>] {
        guard !input.isEmpty else { return [] }
        let sorted = input.sorted {
            if $0.lowerBound != $1.lowerBound {
                return $0.lowerBound < $1.lowerBound
            }
            return $0.upperBound < $1.upperBound
        }
        var merged: [ClosedRange<AyahNumber>] = [sorted[0]]
        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            let touchesOrOverlaps = range.lowerBound <= last.upperBound
                || last.upperBound.next == range.lowerBound
            if touchesOrOverlaps {
                merged[merged.count - 1] = last.lowerBound ... max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
