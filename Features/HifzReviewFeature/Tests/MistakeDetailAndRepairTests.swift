//
//  MistakeDetailAndRepairTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import Foundation
import MemorizationPersistence
import MemorizationService
import QuranKit
import QuranResources
import TestResources
import XCTest
@testable import HifzReviewFeature

@MainActor
final class MistakeDetailAndRepairTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        try super.setUpWithError()
        let fixedNow = Date(timeIntervalSince1970: 1_764_250_000)
        now = fixedNow
        store = TemporaryCoreDataStore()
        service = MemorizationService(
            persistence: CoreDataMemorizationPersistence(stack: store.stack()),
            quran: quran,
            now: { fixedNow }
        )
        textLoader = SpotTestTextLoader(
            uthmaniDatabase: QuranResources.quranUthmaniV2Database,
            wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
        )
    }

    override func tearDownWithError() throws {
        service = nil
        store = nil
        try super.tearDownWithError()
    }

    func testDetailViewModelLoadsWordsConfirmsAndDisputesAndLaunchesPassage() async throws {
        let v1 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 1))
        let v4 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 4))
        try await service.recordSession(Passage(v1, v4), startedOn: now, recalls: [
            VerseRecall(verse: v1, outcome: .mistake, mistakenWords: [2], provenance: .model),
        ])

        var changedCount = 0
        var practiced: Passage?
        var openedNote = false

        let vm = MistakeDetailViewModel(
            verse: v1,
            service: service,
            textLoader: textLoader,
            practicePassage: { practiced = $0 },
            openNote: { openedNote = true },
            onHistoryChanged: { changedCount += 1 }
        )

        await vm.load()
        XCTAssertFalse(vm.loadFailed)
        XCTAssertEqual(vm.wordUnits.count, 4, "112:1 has 4 words")
        XCTAssertNotNil(vm.arabicText(forWord: 2))
        XCTAssertEqual(vm.summary?.activeEvents.count, 1)
        XCTAssertEqual(vm.summary?.activeEvents[0].provenance, .model)

        // Confirm model event -> upgrades to manual
        let modelEvent = try XCTUnwrap(vm.summary?.activeEvents.first)
        await vm.confirm(modelEvent)
        XCTAssertEqual(changedCount, 1)
        XCTAssertEqual(vm.summary?.activeEvents.count, 1)
        XCTAssertEqual(vm.summary?.activeEvents[0].provenance, .manual)

        // Remove manual event -> clears active mistakes
        let manualEvent = try XCTUnwrap(vm.summary?.activeEvents.first)
        await vm.retract(manualEvent)
        XCTAssertEqual(changedCount, 2)
        XCTAssertTrue(vm.summary?.activeEvents.isEmpty == true)
        let heatmapAfterRemove = try await service.mistakeHeatmap(for: quran)
        XCTAssertTrue(heatmapAfterRemove.isEmpty)

        // Practice launches full passage, note opens editor
        vm.practiceRepairPassage()
        XCTAssertEqual(practiced, Passage(v1, v4))
        vm.editNote()
        XCTAssertTrue(openedNote)
    }

    func testReviewViewModelLoadsRepairQueueAndPracticesPassage() async throws {
        let v1 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 1))
        let v4 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 4))
        try await service.recordSession(Passage(v1, v4), startedOn: now, recalls: [
            VerseRecall(verse: v1, outcome: .mistake, mistakenWords: [3], provenance: .manual),
        ])

        var practiced: Passage?
        let vm = HifzReviewViewModel(
            service: service,
            textLoader: textLoader,
            initialTab: .repair,
            practicePassage: { practiced = $0 },
            openAyah: { _ in }
        )

        XCTAssertEqual(vm.selectedTab, .repair)
        await vm.reload()
        XCTAssertEqual(vm.repairItems.count, 1)
        XCTAssertEqual(vm.repairItems[0].passage, Passage(v1, v4))

        vm.startRepairPractice(vm.repairItems[0])
        XCTAssertEqual(practiced, Passage(v1, v4))
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405
    private var now: Date!
    private var store: TemporaryCoreDataStore!
    private var service: MemorizationService!
    private var textLoader: SpotTestTextLoader!
}
