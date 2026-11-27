//
//  RecitationFollowViewModelTests.swift
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

/// Live follow with the real model and databases; public EveryAyah recordings are streamed in
/// windows as the microphone's would be (the microphone itself is checked by hand, V2a trail). The
/// model-backed tests skip without `make recitation-model`.
@MainActor
final class RecitationFollowViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        highlighted = []
        closeCount = 0
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testWithoutAModelItOffersTheDownloadInsteadOfListening() async {
        let viewModel = makeViewModel(pages: [Quran.hafsMadani1405.pages[0]])
        await viewModel.start()
        XCTAssertEqual(viewModel.state, .needsModel(byteCount: RecitationModelArchive.current.byteCount))
        XCTAssertTrue(highlighted.isEmpty)
    }

    func testARecitationOnThePageIsHighlightedWordByWordInTheReadersEdition() async throws {
        try installModel()
        let quran = Quran.hafsMadani1440
        let ikhlas = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 1))
        let viewModel = makeViewModel(pages: [ikhlas.page])
        let prepared = await viewModel.prepare()
        XCTAssertTrue(prepared)
        try await viewModel.beginFollowing()
        XCTAssertEqual(viewModel.state, .listening)

        try await stream(["Husary_112001", "Husary_112002", "Husary_112003", "Husary_112004"], to: viewModel)

        let words = highlighted.compactMap { $0 }
        XCTAssertEqual(words, words.sorted(), "the highlight moves forward")
        XCTAssertGreaterThanOrEqual(words.count, 8, "word by word")
        XCTAssertEqual(Set(words.map(\.verse.ayah)), [1, 2, 3, 4])
        XCTAssertTrue(words.allSatisfy { $0.verse.quran == quran }, "highlights use the reader's edition")
        XCTAssertEqual(viewModel.state, .following(try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 4))))
    }

    func testARecitationElsewhereIsFoundAgainInTheWholeQuran() async throws {
        try installModel()
        // Al-Fatihah is in view, but the reciter recites Al-Ikhlas.
        let viewModel = makeViewModel(pages: [Quran.hafsMadani1405.pages[0]])
        _ = await viewModel.prepare()
        try await viewModel.beginFollowing()

        try await stream(["Husary_112001", "Husary_112002", "Husary_112003", "Husary_112004"], to: viewModel)

        let words = highlighted.compactMap { $0 }
        XCTAssertFalse(words.isEmpty)
        XCTAssertTrue(words.allSatisfy { $0.verse.sura.suraNumber == 112 }, "\(words)")
        XCTAssertEqual(viewModel.state, .following(try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: 4))))
    }

    func testTurningThePageWhileListeningFollowsFromTheNewPage() async throws {
        try installModel()
        let quran = Quran.hafsMadani1405
        let viewModel = makeViewModel(pages: [quran.pages[0]])
        _ = await viewModel.prepare()
        try await viewModel.beginFollowing()

        let ikhlas = try XCTUnwrap(AyahNumber(quran: quran, sura: 112, ayah: 1))
        viewModel.visiblePagesChanged([ikhlas.page])
        try await waitUntil { viewModel.followedVerses?.contains(ikhlas) == true }

        try await stream(["Husary_112001"], to: viewModel)
        XCTAssertEqual(highlighted.compactMap { $0?.verse.sura.suraNumber }.first, 112)
    }

    func testStoppingClearsTheHighlightAndCloses() async throws {
        try installModel()
        let viewModel = makeViewModel(pages: [try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: 1)).page])
        _ = await viewModel.prepare()
        try await viewModel.beginFollowing()
        try await stream(["Husary_112001"], to: viewModel)
        XCTAssertNotNil(highlighted.last ?? nil)

        viewModel.stop()

        XCTAssertEqual(highlighted.last, .some(nil), "the highlight is cleared")
        XCTAssertEqual(closeCount, 1)
        // A window recognized after stopping changes nothing.
        let count = highlighted.count
        await viewModel.follow(try samples("Husary_112002"))
        XCTAssertEqual(highlighted.count, count)
    }

    func testSilenceWhileFollowingKeepsTheHighlight() async throws {
        try installModel()
        let viewModel = makeViewModel(pages: [try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: 1)).page])
        _ = await viewModel.prepare()
        try await viewModel.beginFollowing()
        try await stream(["Husary_112001"], to: viewModel)
        let last = highlighted.last

        await viewModel.follow([Float](repeating: 0, count: RecitationAudio.sampleRate * 8))

        XCTAssertEqual(highlighted.last, last)
        XCTAssertEqual(viewModel.state, .following(try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: 1))))
    }

    // MARK: Private

    /// `.cache/recitation-model` at the repository root (this file is Features/RecitationFollowFeature/Tests/).
    private static let cachedModel = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/recitation-model")

    private var directory: URL!
    private var highlighted: [Word?] = []
    private var closeCount = 0
    /// Never started: these tests don't download (`RecitationModelDownloaderTests` covers it).
    private let downloadManager = DownloadManager(
        maxSimultaneousDownloads: 1,
        configuration: .ephemeral,
        downloadsURL: FileManager.default.temporaryDirectory.appendingPathComponent("recitation-follow-tests-\(UUID().uuidString).db")
    )

    private func makeViewModel(pages: [Page]) -> RecitationFollowViewModel {
        let store = RecitationModelStore(directory: directory)
        return RecitationFollowViewModel(
            loader: RecitationEngineLoader(
                store: store,
                downloader: RecitationModelDownloader(downloadManager: downloadManager, store: store),
                verseText: RecitationVerseText(
                    quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
                    wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
                )
            ),
            microphone: RecitationMicrophone(keepingLatestSeconds: 10),
            pages: pages,
            highlight: { [weak self] in self?.highlighted.append($0) },
            close: { [weak self] in self?.closeCount += 1 }
        )
    }

    private func samples(_ fixture: String) throws -> [Float] {
        try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/\(fixture).mp3"))
    }

    /// The fixtures one after another, half a second apart, fed as the microphone loop feeds them:
    /// the latest `windowSeconds` every second, then a window after the end.
    private func stream(_ fixtures: [String], to viewModel: RecitationFollowViewModel) async throws {
        executionTimeAllowance = 300
        var audio: [Float] = []
        for fixture in fixtures {
            audio += try samples(fixture)
            audio += [Float](repeating: 0, count: RecitationAudio.sampleRate / 2)
        }
        let hop = RecitationAudio.sampleRate
        let window = Int(RecitationFollowViewModel.windowSeconds) * RecitationAudio.sampleRate
        var end = hop
        while end < audio.count + hop {
            let upper = min(end, audio.count)
            await viewModel.follow(Array(audio[max(0, upper - window) ..< upper]))
            end += hop
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }

    /// Links the locally built model into the test's model directory, as the download installs it.
    private func installModel() throws {
        let package = Self.cachedModel.appendingPathComponent(RecitationModelStore.packageName)
        let vocabulary = Self.cachedModel.appendingPathComponent("source/vocab.json")
        guard FileManager.default.fileExists(atPath: package.path), FileManager.default.fileExists(atPath: vocabulary.path) else {
            throw XCTSkip("No recitation model at \(package.path): run `make recitation-model` to build it.")
        }
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent(RecitationModelStore.packageName),
            withDestinationURL: package
        )
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent(RecitationModelStore.vocabularyName),
            withDestinationURL: vocabulary
        )
    }
}
