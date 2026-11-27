//
//  PracticeStateStoreTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import QuranKit
import XCTest
@testable import MemorizationService

final class PracticeStateStoreTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        suiteName = "PracticeStateStoreTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        store = PracticeStateStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        store = nil
        userDefaults = nil
        super.tearDown()
    }

    func testDefaultsHideEverythingInStraightOrderWithNoDraft() {
        XCTAssertEqual(store.cueLevel, .none)
        XCTAssertEqual(store.order, .straight)
        XCTAssertNil(store.draft)
    }

    func testChoicesAreKept() {
        store.cueLevel = .alternateWords
        store.order = .cumulative

        let reopened = PracticeStateStore(userDefaults: userDefaults)
        XCTAssertEqual(reopened.cueLevel, .alternateWords)
        XCTAssertEqual(reopened.order, .cumulative)
    }

    func testDraftRoundTripsAndClears() throws {
        let draft = PracticeDraft(
            passage: Passage(verse(1), verse(4)),
            order: .cumulative,
            position: 3,
            startedOn: Date(timeIntervalSince1970: 1_800_000_000),
            recalls: [
                VerseRecall(verse: verse(1), outcome: .hint, assistance: 2),
                VerseRecall(verse: verse(2), outcome: .mistake, mistakenWords: [1, 3]),
            ]
        )

        try store.saveDraft(draft)

        XCTAssertEqual(PracticeStateStore(userDefaults: userDefaults).draft, draft)
        store.clearDraft()
        XCTAssertNil(store.draft)
    }

    func testDraftOfANewerFormatOrUnreadableIsIgnored() {
        let newer = """
        {"version":2,"first":{"sura":112,"ayah":1},"last":{"sura":112,"ayah":4},"order":"straight",\
        "position":0,"startedOn":0,"recalls":[]}
        """
        userDefaults.set(Data(newer.utf8), forKey: "hifzPractice.draft")
        XCTAssertNil(store.draft)

        userDefaults.set(Data("not json".utf8), forKey: "hifzPractice.draft")
        XCTAssertNil(store.draft)

        let impossibleVerse = """
        {"version":1,"first":{"sura":112,"ayah":9},"last":{"sura":112,"ayah":4},"order":"straight",\
        "position":0,"startedOn":0,"recalls":[]}
        """
        userDefaults.set(Data(impossibleVerse.utf8), forKey: "hifzPractice.draft")
        XCTAssertNil(store.draft)
    }

    func testStoredFormatIsStable() throws {
        // The draft's field names are a persisted format (a draft written by this version must resume after an update).
        let stored = """
        {"version":1,"first":{"sura":112,"ayah":1},"last":{"sura":112,"ayah":4},"order":"straight",\
        "position":1,"startedOn":0,"recalls":[{"verse":{"sura":112,"ayah":1},"outcome":1,"assistance":0,\
        "mistakenWords":[2]}]}
        """
        userDefaults.set(Data(stored.utf8), forKey: "hifzPractice.draft")

        let draft = try XCTUnwrap(store.draft)
        XCTAssertEqual(draft.passage, Passage(verse(1), verse(4)))
        XCTAssertEqual(draft.position, 1)
        XCTAssertEqual(draft.recalls, [VerseRecall(verse: verse(1), outcome: .mistake, mistakenWords: [2])])
    }

    // MARK: Private

    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var store: PracticeStateStore!

    private func verse(_ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: ayah)!
    }
}
