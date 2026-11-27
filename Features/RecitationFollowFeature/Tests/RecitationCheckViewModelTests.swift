//
//  RecitationCheckViewModelTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import BatchDownloader
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

    private func makeViewModel() throws -> RecitationCheckViewModel {
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
            verses: verses
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
