//
//  RecitationLabViewModelTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranResources
import RecitationRecognition
import TestResources
import XCTest
@testable import RecitationLabFeature

/// The developer screen with the real model and databases: recorded audio comes from a public
/// EveryAyah fixture instead of the microphone (the microphone itself is checked by hand, V0 (c)
/// trail). The model-backed test skips without `make recitation-model`.
@MainActor
final class RecitationLabViewModelTests: XCTestCase {
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

    func testWithoutAModelTheScreenSaysWhereToInstallIt() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        XCTAssertEqual(viewModel.modelState, .notInstalled(directory: directory.path))
        XCTAssertFalse(viewModel.canRecord)
    }

    func testARecitationShowsItsVerseWordsAndMeasurements() async throws {
        try installModel()
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
    }

    // MARK: Private

    /// `.cache/recitation-model` at the repository root (this file is Features/RecitationLabFeature/Tests/).
    private static let cachedModel = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/recitation-model")

    private var directory: URL!

    private func makeViewModel() -> RecitationLabViewModel {
        RecitationLabViewModel(
            modelStore: RecitationModelStore(directory: directory),
            verseText: RecitationVerseText(
                quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
                wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
            ),
            microphone: RecitationMicrophone()
        )
    }

    /// Links the locally built model into the test's model directory, as a developer copies it.
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
