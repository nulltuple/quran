//
//  PassageSplitterTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import QuranKit
import XCTest
@testable import MemorizationService

final class PassageSplitterTests: XCTestCase {
    private let quran = Quran.hafsMadani1405

    private func v(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }

    func testShortSurasOnSamePageStaySeparatePassages() {
        // Page 604 contains Al-Ikhlas (112), Al-Falaq (113), An-Nas (114).
        let passages = PassageSplitter.defaultPassages(covering: v(112, 1) ... v(114, 6))
        XCTAssertEqual(passages, [
            Passage(v(112, 1), v(112, 4)),
            Passage(v(113, 1), v(113, 5)),
            Passage(v(114, 1), v(114, 6)),
        ])
    }

    func testMultiPageSuraSplitsByPageAndHalvesDensePages() {
        // Al-Mulk (67:1-30) spans pages 562 (1-12), 563 (13-26), 564 (27-30).
        let mulk = Sura(quran: quran, suraNumber: 67)!
        let passages = PassageSplitter.defaultPassages(covering: mulk.firstVerse ... mulk.lastVerse)
        XCTAssertEqual(passages.count, 5)
        XCTAssertEqual(passages.first?.first, v(67, 1))
        XCTAssertEqual(passages.last?.last, v(67, 30))
        XCTAssertTrue(passages.allSatisfy { $0.verses.count <= PassageSplitter.maxVersesPerChunk })
        let flattened = passages.flatMap(\.verses)
        XCTAssertEqual(flattened, mulk.verses)
    }

    func testSingleAyahProducesSingleAyahPassage() {
        let kursi = v(2, 255)
        XCTAssertEqual(PassageSplitter.defaultPassages(covering: kursi ... kursi), [Passage(kursi, kursi)])
    }
}
