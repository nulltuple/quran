//
//  PhoneticModelStore.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import BatchDownloader
import CoreML
import CryptoKit
import Foundation
import SystemDependencies
import Utilities

/// The published phonetic assessment pack (`phonetic-model-1`, owner decision D7 pattern).
/// Holds `HisnLabsTajweedV2Int8.mlpackage`, `vocab.json`, `quran_phonetics.db` (6,236 ayahs)
/// and `ATTRIBUTION.txt` (Apache-2.0 / MIT).
public struct PhoneticModelArchive: Equatable, Sendable {
    // MARK: Lifecycle

    public init(url: URL, sha256: String, byteCount: Int64) {
        self.url = url
        self.sha256 = sha256
        self.byteCount = byteCount
    }

    // MARK: Public

    public static let current = PhoneticModelArchive(
        url: URL(string: "https://github.com/nulltuple/quran/releases/download/phonetic-model-1/phonetic-model-1.zip")!,
        sha256: "0e62540c9f3c3d1d435210792d483ba9ee84a41e8ba4ed166a14f5129d8f23ac",
        byteCount: 21_857_882
    )

    public let url: URL
    public let sha256: String
    public let byteCount: Int64
}

/// Manages the installed phonetic assessment model and reference database in one directory
/// (`Application Support/PhoneticModel`). Compiles the `.mlpackage` once on first load.
public struct PhoneticModelStore: Sendable {
    public struct LoadedPack: Sendable {
        public let acousticModel: CoreMLPhoneticModel
        public let vocabulary: PhoneticVocabulary
        public let referenceStore: PhoneticReferenceStore
    }

    // MARK: Lifecycle

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: Public

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("PhoneticModel", isDirectory: true)
    }

    public static let packageName = "HisnLabsTajweedV2Int8.mlpackage"
    public static let compiledName = "HisnLabsTajweedV2Int8.mlmodelc"
    public static let vocabularyName = "vocab.json"
    public static let referenceDatabaseName = "quran_phonetics.db"

    public let directory: URL

    public var isInstalled: Bool {
        let fm = FileManager.default
        let vocabExists = fm.fileExists(atPath: directory.appendingPathComponent(Self.vocabularyName).path)
        let dbExists = fm.fileExists(atPath: directory.appendingPathComponent(Self.referenceDatabaseName).path)
        let modelExists = fm.fileExists(atPath: directory.appendingPathComponent(Self.compiledName).path)
            || fm.fileExists(atPath: directory.appendingPathComponent(Self.packageName).path)
        return vocabExists && dbExists && modelExists
    }

    /// Loads the installed phonetic model and reference store, compiling the `.mlpackage` on first
    /// load; returns `nil` when not installed.
    public func loadPack(computeUnits: MLComputeUnits = .cpuOnly) async throws -> LoadedPack? {
        let fm = FileManager.default
        let vocabURL = directory.appendingPathComponent(Self.vocabularyName)
        let dbURL = directory.appendingPathComponent(Self.referenceDatabaseName)
        let compiledURL = directory.appendingPathComponent(Self.compiledName)
        let packageURL = directory.appendingPathComponent(Self.packageName)

        guard fm.fileExists(atPath: vocabURL.path), fm.fileExists(atPath: dbURL.path) else {
            return nil
        }
        if !fm.fileExists(atPath: compiledURL.path) {
            guard fm.fileExists(atPath: packageURL.path) else {
                return nil
            }
            let temporary = try await MLModel.compileModel(at: packageURL)
            try fm.moveItem(at: temporary, to: compiledURL)
        }
        let vocabulary = try PhoneticVocabulary(jsonData: Data(contentsOf: vocabURL))
        let model = try CoreMLPhoneticModel(
            compiledModelURL: compiledURL,
            vocabulary: vocabulary,
            computeUnits: computeUnits
        )
        return LoadedPack(
            acousticModel: model,
            vocabulary: vocabulary,
            referenceStore: PhoneticReferenceStore(databaseURL: dbURL)
        )
    }
}

/// Downloads the phonetic assessment pack via `DownloadManager`, verifies sha256, and unzips it
/// into `PhoneticModelStore.directory`.
public struct PhoneticModelDownloader: Sendable {
    // MARK: Lifecycle

    public init(
        downloadManager: DownloadManager,
        store: PhoneticModelStore,
        archive: PhoneticModelArchive = .current
    ) {
        self.downloadManager = downloadManager
        self.store = store
        self.archive = archive
    }

    // MARK: Public

    public let archive: PhoneticModelArchive

    public func download(onProgress: @Sendable @escaping (Double) -> Void) async throws {
        let response: DownloadBatchResponse
        if let running = await runningDownload() {
            response = running
        } else {
            let request = DownloadRequest(url: archive.url, destination: Self.archiveFile)
            response = try await downloadManager.download(DownloadBatchRequest(requests: [request]))
        }
        for try await progress in response.progress {
            onProgress(progress.progress)
        }
        try Task.checkCancellation()
        onProgress(1)
        try install(archiveAt: Self.archiveFile.url)
    }

    // MARK: Internal

    static let archiveFile = RelativeFilePath("phonetic-model/phonetic-model-1.zip", isDirectory: false)

    func install(archiveAt url: URL) throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: url) }
        guard try RecitationModelDownloader.sha256(of: url) == archive.sha256 else {
            throw RecitationModelDownloadError.checksumMismatch
        }
        try fm.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try? fm.removeItem(at: store.directory.appendingPathComponent(PhoneticModelStore.compiledName))
        try DefaultZipper().unzipFile(url, destination: store.directory, overwrite: true)
    }

    // MARK: Private

    private let downloadManager: DownloadManager
    private let store: PhoneticModelStore

    private func runningDownload() async -> DownloadBatchResponse? {
        await downloadManager.getOnGoingDownloads().first { response in
            response.requests.count == 1 && response.requests.first?.destination == Self.archiveFile
        }
    }
}

/// On-demand loader for the phonetic pronunciation assessment engine (V4/V5), reusable by both
/// Quran and Arabican. Loads the model when a screen needs it and releases it when the screen closes.
public struct PhoneticEngineLoader: Sendable {
    // MARK: Lifecycle

    public init(store: PhoneticModelStore, downloader: PhoneticModelDownloader) {
        self.store = store
        self.downloader = downloader
    }

    public init(downloadManager: DownloadManager) {
        let store = PhoneticModelStore(directory: PhoneticModelStore.defaultDirectory)
        self.init(
            store: store,
            downloader: PhoneticModelDownloader(downloadManager: downloadManager, store: store)
        )
    }

    // MARK: Public

    public let store: PhoneticModelStore
    public let downloader: PhoneticModelDownloader

    public var downloadByteCount: Int64 {
        downloader.archive.byteCount
    }

    public func load(computeUnits: MLComputeUnits = .cpuOnly) async throws -> PhoneticModelStore.LoadedPack? {
        try await store.loadPack(computeUnits: computeUnits)
    }

    public func download(onProgress: @Sendable @escaping (Double) -> Void) async throws {
        try await downloader.download(onProgress: onProgress)
    }
}
