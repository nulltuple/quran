//
//  VoiceSearchViewModelTests.swift
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
@testable import SearchFeature

/// Voice search with the real model and databases; recitations come from public EveryAyah fixtures
/// instead of the microphone (the microphone is checked by hand, V1 trail). The model-backed tests
/// skip without `make recitation-model`.
@MainActor
final class VoiceSearchViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        navigatedTo = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testWithoutAModelItOffersTheDownloadInsteadOfListening() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        XCTAssertEqual(viewModel.state, .needsModel(byteCount: RecitationModelArchive.current.byteCount))
        XCTAssertNil(viewModel.failure)
    }

    func testARecitedVerseIsTheTrustedFirstCandidateInTheReadersEdition() async throws {
        try installModel()
        let viewModel = makeViewModel(quran: .hafsMadani1440)
        let prepared = await viewModel.prepare()
        XCTAssertTrue(prepared)

        await viewModel.search(try samples("Husary_112001"))

        guard case .results(let results) = viewModel.state else {
            return XCTFail("state \(viewModel.state)")
        }
        XCTAssertTrue(results.isConfident)
        let best = try XCTUnwrap(results.candidates.first)
        XCTAssertEqual(best.verses.lowerBound, AyahNumber(quran: .hafsMadani1440, sura: 112, ayah: 1))
        XCTAssertEqual(best.verses.lowerBound.quran, .hafsMadani1440, "navigation uses the reader's edition")
        XCTAssertEqual(best.text?.text.isEmpty, false, "the row shows the verse's Arabic text")
        XCTAssertLessThanOrEqual(results.candidates.count, VoiceSearchViewModel.candidateLimit)
        XCTAssertEqual(results.candidates.map(\.id), Array(results.candidates.indices))
        let firstVerses = results.candidates.map(\.verses.lowerBound)
        XCTAssertEqual(Set(firstVerses).count, firstVerses.count, "each verse is offered once")
    }

    func testSelectingACandidateOpensItsFirstVerse() async throws {
        try installModel()
        let viewModel = makeViewModel()
        _ = await viewModel.prepare()
        await viewModel.search(try samples("Ghamadi_002255"))
        guard case .results(let results) = viewModel.state, let best = results.candidates.first else {
            return XCTFail("state \(viewModel.state)")
        }

        viewModel.select(best)

        XCTAssertEqual(navigatedTo, [best.verses.lowerBound])
        XCTAssertEqual(best.verses.lowerBound, AyahNumber(quran: .hafsMadani1405, sura: 2, ayah: 255))
    }

    func testRunsStartingAtTheSameVerseAreOfferedOnce() async throws {
        try installModel()
        let viewModel = makeViewModel()
        _ = await viewModel.prepare()
        await viewModel.search(try samples("Alafasy_001002"))
        guard case .results(let results) = viewModel.state else {
            return XCTFail("state \(viewModel.state)")
        }
        let firstVerses = results.candidates.map(\.verses.lowerBound)
        XCTAssertEqual(firstVerses.first, AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 2))
        XCTAssertEqual(Set(firstVerses).count, firstVerses.count)
    }

    func testSilenceMatchesNoVerse() async throws {
        try installModel()
        let viewModel = makeViewModel()
        _ = await viewModel.prepare()

        await viewModel.search([Float](repeating: 0, count: 16000 * 3))

        XCTAssertEqual(viewModel.state, .noMatch)
        XCTAssertTrue(navigatedTo.isEmpty)
    }

    // MARK: Private

    /// `.cache/recitation-model` at the repository root (this file is Features/SearchFeature/Tests/).
    private static let cachedModel = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/recitation-model")

    private var directory: URL!
    private var navigatedTo: [AyahNumber] = []
    /// Never started: these tests don't download (`RecitationModelDownloaderTests` covers it).
    private let downloadManager = DownloadManager(
        maxSimultaneousDownloads: 1,
        configuration: .ephemeral,
        downloadsURL: FileManager.default.temporaryDirectory.appendingPathComponent("voice-search-tests-\(UUID().uuidString).db")
    )

    private func makeViewModel(quran: Quran = .hafsMadani1405) -> VoiceSearchViewModel {
        let store = RecitationModelStore(directory: directory)
        return VoiceSearchViewModel(
            loader: RecitationEngineLoader(
                store: store,
                downloader: RecitationModelDownloader(downloadManager: downloadManager, store: store),
                verseText: RecitationVerseText(
                    quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
                    wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
                )
            ),
            microphone: RecitationMicrophone(),
            quran: { quran },
            navigateTo: { [weak self] in self?.navigatedTo.append($0) }
        )
    }

    private func samples(_ fixture: String) throws -> [Float] {
        try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/\(fixture).mp3"))
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
