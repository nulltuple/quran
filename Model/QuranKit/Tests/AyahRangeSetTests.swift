//
//  AyahRangeSetTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import QuranKit
import XCTest

final class AyahRangeSetTests: XCTestCase {
    private let quran = Quran.hafsMadani1405

    private func v(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }

    func testNormalizesOverlappingAndAdjacentRangesAcrossSuraBoundaries() {
        let fatiha = v(1, 1) ... v(1, 7)
        let baqarahStart = v(2, 1) ... v(2, 5)
        let baqarahOverlap = v(2, 3) ... v(2, 10)

        let set = AyahRangeSet([baqarahOverlap, fatiha, baqarahStart])
        XCTAssertEqual(set.ranges, [v(1, 1) ... v(2, 10)])
        XCTAssertEqual(set.verseCount, 17)
        XCTAssertTrue(set.contains(v(1, 7)))
        XCTAssertTrue(set.contains(v(2, 1)))
        XCTAssertTrue(set.contains(v(1, 5) ... v(2, 4)))
        XCTAssertFalse(set.contains(v(2, 11)))
        XCTAssertFalse(set.contains(v(2, 9) ... v(2, 11)))
    }

    func testUnionIntersectionAndSubtraction() {
        let a = AyahRangeSet([v(112, 1) ... v(114, 6)]) // Ikhlas (4) + Falaq (5) + Nas (6) = 15
        let b = AyahRangeSet([v(113, 1) ... v(113, 5)]) // Falaq (5)

        let diff = a.subtracting(b)
        XCTAssertEqual(diff.ranges, [v(112, 1) ... v(112, 4), v(114, 1) ... v(114, 6)])
        XCTAssertEqual(diff.verseCount, 10)

        let inter = a.intersection(AyahRangeSet([v(112, 3) ... v(113, 2)]))
        XCTAssertEqual(inter.ranges, [v(112, 3) ... v(113, 2)])
        XCTAssertEqual(inter.verseCount, 4)

        let rejoined = diff.union(b)
        XCTAssertEqual(rejoined, a)
    }

    func testWholeQuranVerseCountMatchesVersesArray() {
        let whole = AyahRangeSet(quran.firstVerse ... quran.lastVerse)
        XCTAssertEqual(whole.verseCount, 6236)
        XCTAssertEqual(whole.verseCount, quran.verses.count)
    }

    func testSubtractingEdgesAndDisjointRanges() {
        let set = AyahRangeSet(v(1, 1) ... v(1, 7))
        XCTAssertEqual(set.subtracting(v(1, 1) ... v(1, 2)).ranges, [v(1, 3) ... v(1, 7)])
        XCTAssertEqual(set.subtracting(v(1, 6) ... v(1, 7)).ranges, [v(1, 1) ... v(1, 5)])
        XCTAssertEqual(set.subtracting(v(1, 1) ... v(1, 7)), AyahRangeSet())
        XCTAssertEqual(set.subtracting(v(2, 1) ... v(2, 5)), set)
    }
}
