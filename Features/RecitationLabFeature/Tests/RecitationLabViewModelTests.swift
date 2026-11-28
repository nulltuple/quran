//
//  RecitationLabViewModelTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import BatchDownloader
import QuranResources
import RecitationRecognition
import TestResources
import XCTest
@testable import RecitationLabFeature

/// The developer screen with the real models and databases: recorded audio comes from a public
/// EveryAyah fixture instead of the microphone. The model-backed tests skip without
/// `make recitation-model` / `make phonetic-model`.
@MainActor
final class RecitationLabViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        phoneticDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: phoneticDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: phoneticDirectory)
        try super.tearDownWithError()
    }

    func testWithoutAModelTheScreenSaysWhereToInstallIt() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        XCTAssertEqual(viewModel.modelState, .notInstalled(directory: directory.path))
        XCTAssertEqual(viewModel.phoneticModelState, .notInstalled(directory: phoneticDirectory.path))
        XCTAssertFalse(viewModel.canRecord)
    }

    func testARecitationShowsItsVerseWordsAndMeasurements() async throws {
        try installModel()
        try? installPhoneticModel()
        let viewModel = makeViewModel()
        await viewModel.load()
        guard case .ready = viewModel.modelState else {
            return XCTFail("model state \(viewModel.modelState)")
        }
        XCTAssertTrue(viewModel.canRecord)

        let samples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Husary_112001.mp3"))
        await viewModel.analyze(samples)

        let result = try XCTUnwrap(viewModel.result)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(result.candidates.first?.range, "112:1")
        XCTAssertTrue(result.isConfident)
        XCTAssertEqual(result.words.map(\.kind), [.matched, .matched, .matched, .matched])
        XCTAssertEqual(result.words.first?.expected, "112:1:1 قُلۡ")
        XCTAssertNotNil(result.words.first?.seconds)
        XCTAssertEqual(result.audioSeconds, Double(samples.count) / 16000, accuracy: 0.001)
        XCTAssertGreaterThan(result.recognitionMilliseconds, 0)
        XCTAssertGreaterThan(result.peakDecibels, -20, "a studio recording peaks near full scale")
        XCTAssertNotNil(result.footprintMegabytes)

        if case .ready = viewModel.phoneticModelState {
            let pronunciation = try XCTUnwrap(result.pronunciation)
            XCTAssertEqual(pronunciation.targetRange, "112:1")
            XCTAssertEqual(pronunciation.confirmedMistakeCount, 0)
            XCTAssertEqual(pronunciation.phonemeMatchRate, 1.0, accuracy: 0.001)
            XCTAssertEqual(pronunciation.words.count, 4)

            let tajweed = try XCTUnwrap(result.tajweed)
            XCTAssertEqual(tajweed.targetRange, "112:1")
            XCTAssertEqual(tajweed.confirmedRemarkCount, 0)
        }
    }

    func testParseVerseValidatesSuraAndAyah() {
        XCTAssertEqual(RecitationLabViewModel.parseVerse("112:1")?.sura.suraNumber, 112)
        XCTAssertEqual(RecitationLabViewModel.parseVerse("112:1")?.ayah, 1)
        XCTAssertNil(RecitationLabViewModel.parseVerse(""))
        XCTAssertNil(RecitationLabViewModel.parseVerse("999:1"))
        XCTAssertNil(RecitationLabViewModel.parseVerse("invalid"))
    }

    // MARK: Private

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let cachedModel = repoRoot.appendingPathComponent(".cache/recitation-model")
    private static let cachedPhoneticModel = repoRoot.appendingPathComponent(".cache/phonetic-model/out")

    private var directory: URL!
    private var phoneticDirectory: URL!
    private let downloadManager = DownloadManager(
        maxSimultaneousDownloads: 1,
        configuration: .ephemeral,
        downloadsURL: FileManager.default.temporaryDirectory.appendingPathComponent("lab-tests-\(UUID().uuidString).db")
    )

    private func makeViewModel() -> RecitationLabViewModel {
        let store = RecitationModelStore(directory: directory)
        let phoneticStore = PhoneticModelStore(directory: phoneticDirectory)
        return RecitationLabViewModel(
            loader: RecitationEngineLoader(
                store: store,
                downloader: RecitationModelDownloader(downloadManager: downloadManager, store: store),
                verseText: RecitationVerseText(
                    quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
                    wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
                )
            ),
            phoneticLoader: PhoneticEngineLoader(
                store: phoneticStore,
                downloader: PhoneticModelDownloader(downloadManager: downloadManager, store: phoneticStore)
            ),
            microphone: RecitationMicrophone()
        )
    }

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

    private func installPhoneticModel() throws {
        let package = Self.cachedPhoneticModel.appendingPathComponent(PhoneticModelStore.packageName)
        let vocab = Self.cachedPhoneticModel.appendingPathComponent(PhoneticModelStore.vocabularyName)
        let db = Self.cachedPhoneticModel.appendingPathComponent(PhoneticModelStore.referenceDatabaseName)
        guard FileManager.default.fileExists(atPath: package.path),
              FileManager.default.fileExists(atPath: vocab.path),
              FileManager.default.fileExists(atPath: db.path)
        else {
            throw XCTSkip("No phonetic model at \(package.path): run `make phonetic-model` to build it.")
        }
        try FileManager.default.createSymbolicLink(at: phoneticDirectory.appendingPathComponent(PhoneticModelStore.packageName), withDestinationURL: package)
        try FileManager.default.createSymbolicLink(at: phoneticDirectory.appendingPathComponent(PhoneticModelStore.vocabularyName), withDestinationURL: vocab)
        try FileManager.default.createSymbolicLink(at: phoneticDirectory.appendingPathComponent(PhoneticModelStore.referenceDatabaseName), withDestinationURL: db)
    }
}
