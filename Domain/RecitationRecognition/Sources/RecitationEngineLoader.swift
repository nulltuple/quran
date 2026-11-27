//
//  RecitationEngineLoader.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import BatchDownloader
import Foundation

/// Gets a screen that recognizes recitation its recognizer: the installed model with a matcher over
/// every verse, after downloading the model when the screen asks. A screen loads it when it opens
/// and drops it when it closes: the loaded model takes hundreds of megabytes (V0 (c) trail).
public struct RecitationEngineLoader: Sendable {
    // MARK: Lifecycle

    public init(store: RecitationModelStore, downloader: RecitationModelDownloader, verseText: RecitationVerseText) {
        self.store = store
        self.downloader = downloader
        self.verseText = verseText
    }

    /// The app's loader: the model in `RecitationModelStore.defaultDirectory`, downloaded with the
    /// app's download manager, matched against the bundled Quran text.
    public init(downloadManager: DownloadManager, quranUthmaniV2Database: URL, wordByWordDatabase: URL) {
        let store = RecitationModelStore(directory: RecitationModelStore.defaultDirectory)
        self.init(
            store: store,
            downloader: RecitationModelDownloader(downloadManager: downloadManager, store: store),
            verseText: RecitationVerseText(quranUthmaniV2Database: quranUthmaniV2Database, wordByWordDatabase: wordByWordDatabase)
        )
    }

    // MARK: Public

    public let store: RecitationModelStore
    public let downloader: RecitationModelDownloader
    public let verseText: RecitationVerseText

    /// The model archive's size, to show before downloading it.
    public var downloadByteCount: Int64 {
        downloader.archive.byteCount
    }

    /// The recognizer, compiling the model the first time; nil when the model is not installed.
    public func load() async throws -> RecitationRecognizer? {
        guard let model = try await store.loadModel() else {
            return nil
        }
        let matcher = try await verseText.makeMatcher()
        return RecitationRecognizer(model: model.acousticModel, decoder: CTCDecoder(vocabulary: model.vocabulary), matcher: matcher)
    }

    /// Downloads and installs the model, reporting progress 0–1.
    public func download(onProgress: @Sendable @escaping (Double) -> Void) async throws {
        try await downloader.download(onProgress: onProgress)
    }
}
