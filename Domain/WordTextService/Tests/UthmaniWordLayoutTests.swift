//
//  UthmaniWordLayoutTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import WordTextService
import XCTest

final class UthmaniWordLayoutTests: XCTestCase {
    func test_oneTokenPerWord() {
        let units = UthmaniWordLayout(wordCount: 3).units(tokenCount: 3)

        XCTAssertEqual(units?.map(\.words), [1 ... 1, 2 ... 2, 3 ... 3])
        XCTAssertEqual(units?.map(\.tokens), [1 ... 1, 2 ... 2, 3 ... 3])
    }

    func test_noUnitsWhenTheTokenCountDiffers() {
        XCTAssertNil(UthmaniWordLayout(wordCount: 3).units(tokenCount: 2))
        XCTAssertNil(UthmaniWordLayout(wordCount: 3).units(tokenCount: 4))
    }

    func test_noUnitsForAnEmptyText() {
        XCTAssertEqual(UthmaniWordLayout(wordCount: 0).units(tokenCount: 0), [])
    }

    func test_tokenShowingTwoWords() {
        let layout = UthmaniWordLayout(wordCount: 3, tokenWords: [1 ... 2, 3 ... 3])

        XCTAssertEqual(layout.units(tokenCount: 2)?.map(\.words), [1 ... 2, 3 ... 3])
    }

    func test_twoTokensShowingOneWord() {
        let layout = UthmaniWordLayout(wordCount: 2, tokenWords: [1 ... 1, 2 ... 2, 2 ... 2])

        XCTAssertEqual(layout.units(tokenCount: 3)?.map(\.tokens), [1 ... 1, 2 ... 3])
    }

    func test_rejectsMappingsThatSkipOrMissWords() {
        XCTAssertNil(UthmaniWordLayout(wordCount: 3, tokenWords: [1 ... 1, 3 ... 3]).units(tokenCount: 2), "Word 2 skipped")
        XCTAssertNil(UthmaniWordLayout(wordCount: 3, tokenWords: [1 ... 1, 2 ... 2]).units(tokenCount: 2), "Word 3 missing")
        XCTAssertNil(UthmaniWordLayout(wordCount: 2, tokenWords: [2 ... 2, 1 ... 1]).units(tokenCount: 2), "Out of order")
        XCTAssertNil(UthmaniWordLayout(wordCount: 2, tokenWords: [1 ... 1, 2 ... 2]).units(tokenCount: 3), "Token count differs")
    }
}
