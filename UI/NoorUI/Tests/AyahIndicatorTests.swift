//
//  AyahIndicatorTests.swift
//
//  The translation view's ayah-number capsule shows collection and note marks in both builds.
//

import QuranAnnotations
import XCTest
@testable import NoorUI

final class AyahIndicatorTests: XCTestCase {
    func test_ordered_putsCollectionBeforeNote() {
        XCTAssertEqual(Set<AyahIndicator>([.note, .collection]).ordered, [.collection, .note])
        XCTAssertEqual(Set<AyahIndicator>([.note]).ordered, [.note])
        XCTAssertTrue(Set<AyahIndicator>().ordered.isEmpty)
    }

    func test_accessibilityLabel_namesCollectionsAndNotes() {
        XCTAssertEqual(AyahIndicator.collection.accessibilityLabel, "Collections")
        XCTAssertEqual(AyahIndicator.note.accessibilityLabel, "Notes")
    }
}
