//
//  RecitationCheckViewModelTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import BatchDownloader
import CoreDataPersistence
import CoreDataPersistenceTestSupport
import MemorizationPersistence
import MemorizationService
import QuranAnnotations
import QuranKit
import QuranResources
import RecitationRecognition
import TestResources
import XCTest
@testable import RecitationFollowFeature

@MainActor
final class RecitationCheckViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testOneSelectedVerseChecksToTheEndOfItsPage() throws {
        let verse = try XCTUnwrap(AyahNumber(quran: quran, sura: 2, ayah: 6))
        let passage = RecitationCheckViewModel.passage(for: [verse])
        XCTAssertEqual(passage.first, verse)
        XCTAssertEqual(passage.last, verse.page.verses.last)
        XCTAssertTrue(passage.allSatisfy { $0.page == verse.page })
    }

    func testTheEndOfThePageStopsAtTheEndOfTheSura() throws {
        let verse = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 1))
        XCTAssertEqual(RecitationCheckViewModel.passage(for: [verse]).map(\.ayah), [1, 2, 3, 4], "page 604 also holds suras 113 and 114")
    }

    func testSeveralSelectedVersesAreThePassage() throws {
        let verses = try [3, 1, 2].map { try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: $0)) }
        XCTAssertEqual(RecitationCheckViewModel.passage(for: verses), verses.sorted())
    }

    func testWithoutAModelItOffersTheDownload() async throws {
        let viewModel = try makeViewModel()
        await viewModel.start()
        XCTAssertEqual(viewModel.state, .needsModel(byteCount: RecitationModelArchive.current.byteCount))
    }

    func testARecitationThatSkipsAVerseIsCheckedAndMarked() async throws {
        executionTimeAllowance = 300
        try installModel()
        let viewModel = try makeViewModel()
        await viewModel.start()
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.checkedTexts.count, 15, "the 15 words of al-Ikhlas")
        XCTAssertEqual(viewModel.checkedTexts.compactMap(\.endsVerse).map(\.ayah), [1, 2, 3, 4], "a marker after each verse")

        let samples = try ["Husary_112001", "Husary_112003", "Husary_112004"].flatMap {
            try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/\($0).mp3"))
        }
        await viewModel.check(samples)

        guard case .checked(let check) = viewModel.state else {
            return XCTFail("\(viewModel.state)")
        }
        XCTAssertEqual(check.skippedVerses.map(\.ayah), [2])
        let marks = viewModel.checkedTexts.map(\.mark)
        XCTAssertEqual(marks[4 ..< 6], [.omitted, .omitted], "verse 2's two words")
        XCTAssertTrue((marks[0 ..< 4] + marks[6...]).allSatisfy { $0 == .correct }, "\(marks)")
    }

    func testRecallsMapperRecordsConfirmedMistakesExcludesUncertainAndUnreached() throws {
        let v1 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 1))
        let v2 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 2))
        let v3 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 3))
        let v4 = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 4))

        let check = RecitationCheck(
            words: [
                CheckedWord(word: Word(verse: v1, wordNumber: 1), mark: .correct, frames: 0 ... 1),
                CheckedWord(word: Word(verse: v1, wordNumber: 2), mark: .substituted(recited: "غير"), frames: 2 ... 3),
                CheckedWord(word: Word(verse: v2, wordNumber: 1), mark: .omitted, frames: nil),
                CheckedWord(word: Word(verse: v2, wordNumber: 2), mark: .omitted, frames: nil),
                CheckedWord(word: Word(verse: v3, wordNumber: 1), mark: .correct, frames: 4 ... 5),
                CheckedWord(word: Word(verse: v3, wordNumber: 2), mark: .uncertain, frames: 6 ... 7),
                CheckedWord(word: Word(verse: v4, wordNumber: 1), mark: .notReached, frames: nil),
            ],
            skippedVerses: [v2]
        )

        let recalls = RecitationCheckViewModel.recalls(from: check)
        XCTAssertEqual(recalls.count, 3, "unreached v4 must not be recorded")
        XCTAssertEqual(recalls[0], VerseRecall(verse: v1, outcome: .mistake, assistance: 0, mistakenWords: [2], provenance: .model))
        XCTAssertEqual(recalls[1], VerseRecall(verse: v2, outcome: .mistake, assistance: 0, mistakenWords: [], provenance: .model))
        XCTAssertEqual(recalls[2], VerseRecall(verse: v3, outcome: .skipped, assistance: 0, mistakenWords: [], provenance: .model))
    }

    func testReciteCheckRecordsModelEvidenceFeedsHeatmapAndDisputeRecomputes() async throws {
        executionTimeAllowance = 300
        try installModel()

        let store = TemporaryCoreDataStore()
        let service = MemorizationService(
            persistence: CoreDataMemorizationPersistence(stack: store.stack()),
            quran: .hafsMadani1405
        )
        var historyChangedCount = 0
        let viewModel = try makeViewModel(
            memorizationService: service,
            policy: .silent,
            onHistoryChanged: { historyChangedCount += 1 }
        )
        await viewModel.start()

        let samples = try ["Husary_112001", "Husary_112003", "Husary_112004"].flatMap {
            try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/\($0).mp3"))
        }
        await viewModel.check(samples)

        XCTAssertEqual(viewModel.policy, .silent)
        XCTAssertNotNil(viewModel.recordedSessionID)
        XCTAssertEqual(historyChangedCount, 1)
        XCTAssertEqual(viewModel.recordedMistakes.count, 1)
        XCTAssertEqual(viewModel.recordedMistakes[0].kind, .skippedVerse)
        XCTAssertEqual(viewModel.recordedMistakes[0].verse.ayah, 2)

        // Confirmed skipped verse feeds H7's heatmap and repair queue with `.model` provenance.
        let v2 = try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: 2))
        let beforeHeatmap = try await service.mistakeHeatmap(for: .hafsMadani1405)
        XCTAssertEqual(beforeHeatmap.verseLevels[v2], .medium)
        let loadedBeforeSummary = try await service.mistakeSummary(for: v2)
        let beforeSummary = try XCTUnwrap(loadedBeforeSummary)
        XCTAssertEqual(beforeSummary.activeEvents.first?.provenance, .model)
        let beforeRepair = try await service.repairQueue()
        XCTAssertEqual(beforeRepair.count, 1)

        // Disputing retracts the `.model` evidence and immediately clears H7's heatmap and repair queue.
        await viewModel.dispute(viewModel.recordedMistakes[0])
        XCTAssertTrue(viewModel.recordedMistakes[0].isDisputed)
        XCTAssertEqual(historyChangedCount, 2)
        let afterHeatmap = try await service.mistakeHeatmap(for: .hafsMadani1405)
        XCTAssertTrue(afterHeatmap.isEmpty)
        let afterRepair = try await service.repairQueue()
        XCTAssertTrue(afterRepair.isEmpty)
    }

    // MARK: Private

    private static let cachedModel = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/recitation-model")

    private let quran = Quran.hafsMadani1440
    private var directory: URL!
    /// Never started: these tests don't download (`RecitationModelDownloaderTests` covers it).
    private let downloadManager = DownloadManager(
        maxSimultaneousDownloads: 1,
        configuration: .ephemeral,
        downloadsURL: FileManager.default.temporaryDirectory.appendingPathComponent("recitation-check-tests-\(UUID().uuidString).db")
    )

    private func makeViewModel(
        memorizationService: MemorizationService? = nil,
        policy: RecitationCheckPolicy = .showMistakes,
        onHistoryChanged: (() -> Void)? = nil
    ) throws -> RecitationCheckViewModel {
        let store = RecitationModelStore(directory: directory)
        let verses = try (1 ... 4).map { try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: $0)) }
        return RecitationCheckViewModel(
            loader: RecitationEngineLoader(
                store: store,
                downloader: RecitationModelDownloader(downloadManager: downloadManager, store: store),
                verseText: RecitationVerseText(
                    quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
                    wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
                )
            ),
            microphone: RecitationMicrophone(maximumSeconds: 10),
            verses: verses,
            memorizationService: memorizationService,
            policy: policy,
            onHistoryChanged: onHistoryChanged
        )
    }

    /// Links the locally built model into the test's model directory, as the download installs it.
    private func installModel() throws {
        let package = Self.cachedModel.appendingPathComponent(RecitationModelStore.packageName)
        let vocabulary = Self.cachedModel.appendingPathComponent("source/vocab.json")
        guard FileManager.default.fileExists(atPath: package.path), FileManager.default.fileExists(atPath: vocabulary.path) else {
            throw XCTSkip("No recitation model at \(package.path): run `make recitation-model` to build it.")
        }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(RecitationModelStore.packageName), withDestinationURL: package)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(RecitationModelStore.vocabularyName), withDestinationURL: vocabulary)
    }
}
