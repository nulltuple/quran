//
//  EditDistanceTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import XCTest
@testable import RecitationRecognition

final class EditDistanceTests: XCTestCase {
    func testDistanceCountsEdits() {
        XCTAssertEqual(EditDistance.distance(units("kitten"), units("sitting")), 3)
        XCTAssertEqual(EditDistance.distance(units(""), units("abc")), 3)
        XCTAssertEqual(EditDistance.distance(units("abc"), units("abc")), 0)
    }

    func testRatioIsOneMinusDistanceOverLongerLength() {
        XCTAssertEqual(EditDistance.ratio(units("abcd"), units("abce")), 0.75, accuracy: 1e-9)
        XCTAssertEqual(EditDistance.ratio(units(""), units("")), 1)
    }

    func testFragmentFitFindsTheBestSubstring() {
        XCTAssertEqual(EditDistance.fragmentFit(units("cde"), in: units("abcdefg")), 1)
        // One substitution against the best substring "cde".
        XCTAssertEqual(EditDistance.fragmentFit(units("cxe"), in: units("abcdefg")), 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(EditDistance.fragmentFit(units("xyz"), in: units("abc")), 0)
        XCTAssertEqual(EditDistance.fragmentFit(units(""), in: units("abc")), 0)
    }

    private func units(_ text: String) -> [UInt16] {
        Array(text.utf16)
    }
}
