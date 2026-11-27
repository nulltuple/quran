//
//  RecitationEngineLoaderTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import BatchDownloader
import QuranKit
import QuranResources
import TestResources
import XCTest
@testable import RecitationRecognition

final class RecitationEngineLoaderTests: XCTestCase {
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

    func testWithoutAModelThereIsNoRecognizer() async throws {
        let recognizer = try await makeLoader().load()
        XCTAssertNil(recognizer)
    }

    func testTheDownloadSizeIsThePublishedArchives() {
        XCTAssertEqual(makeLoader().downloadByteCount, 84_288_886)
    }

    func testTheAppLoaderUsesTheDefaultDirectory() {
        let loader = RecitationEngineLoader(
            downloadManager: downloadManager,
            quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
            wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
        )
        XCTAssertEqual(loader.store.directory, RecitationModelStore.defaultDirectory)
        XCTAssertEqual(RecitationModelStore.defaultDirectory.lastPathComponent, "RecitationModel")
    }

    func testVerseTextForDisplay() async throws {
        let quran = Quran.hafsMadani1405
        let verse = AyahNumber(quran: quran, sura: 112, ayah: 1)!
        let texts = try await makeLoader().verseText.text(of: [verse])
        XCTAssertEqual(texts[verse]?.text.isEmpty, false)
    }

    // MARK: Private

    private var directory: URL!
    /// Never started: these tests don't download (`RecitationModelDownloaderTests` covers it).
    private let downloadManager = DownloadManager(
        maxSimultaneousDownloads: 1,
        configuration: .ephemeral,
        downloadsURL: FileManager.default.temporaryDirectory.appendingPathComponent("loader-tests-\(UUID().uuidString).db")
    )

    private func makeLoader() -> RecitationEngineLoader {
        let store = RecitationModelStore(directory: directory)
        return RecitationEngineLoader(
            store: store,
            downloader: RecitationModelDownloader(downloadManager: downloadManager, store: store),
            verseText: RecitationVerseText(
                quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
                wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
            )
        )
    }
}
