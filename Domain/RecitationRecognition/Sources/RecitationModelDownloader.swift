//
//  RecitationModelDownloader.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import BatchDownloader
import CryptoKit
import Foundation
import SystemDependencies
import Utilities

/// The published model archive. Owner decision D7 (2026-11-27): a GitHub release asset of this
/// repository, like the tafsir packs. The zip holds `TilawiFastConformerInt8.mlpackage`,
/// `vocab.json` and `ATTRIBUTION.txt` (the weights are CC-BY-4.0).
public struct RecitationModelArchive: Equatable, Sendable {
    // MARK: Lifecycle

    public init(url: URL, sha256: String, byteCount: Int64) {
        self.url = url
        self.sha256 = sha256
        self.byteCount = byteCount
    }

    // MARK: Public

    /// `recitation-model-1`, published 2026-11-27 from `make recitation-model` (V0 model-download trail).
    public static let current = RecitationModelArchive(
        url: URL(string: "https://github.com/nulltuple/quran/releases/download/recitation-model-1/recitation-model-1.zip")!,
        sha256: "a6c3ee79f6b848ddd303146bc2b873889e5711c770169ea33dc2697d05ebc7e3",
        byteCount: 84_288_886
    )

    public let url: URL
    /// Lowercase hex.
    public let sha256: String
    public let byteCount: Int64
}

public enum RecitationModelDownloadError: Error, Equatable {
    /// The downloaded file is not the published archive (corrupt, truncated or replaced).
    case checksumMismatch
}

/// Downloads the model archive with the app's `DownloadManager` (background session, resumable),
/// checks its sha256, and unzips it into the store's directory.
public struct RecitationModelDownloader: Sendable {
    // MARK: Lifecycle

    public init(
        downloadManager: DownloadManager,
        store: RecitationModelStore,
        archive: RecitationModelArchive = .current
    ) {
        self.downloadManager = downloadManager
        self.store = store
        self.archive = archive
    }

    // MARK: Public

    public let archive: RecitationModelArchive

    /// Downloads and installs the model, reporting progress 0–1. Joins a download that is already
    /// running (one the app started before it was relaunched).
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
        // A download that finishes before the loop subscribes delivers no progress values.
        onProgress(1)
        try install(archiveAt: Self.archiveFile.url)
    }

    // MARK: Internal

    /// Where the archive downloads to, under Documents; deleted once installed.
    static let archiveFile = RelativeFilePath("recitation-model/recitation-model-1.zip", isDirectory: false)

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Checks the archive at `url`, unzips it into the store's directory (dropping a model compiled
    /// from an older package) and deletes the archive, whether or not it was valid.
    func install(archiveAt url: URL) throws {
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: url) }
        guard try Self.sha256(of: url) == archive.sha256 else {
            throw RecitationModelDownloadError.checksumMismatch
        }
        try fileManager.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: store.directory.appendingPathComponent(RecitationModelStore.compiledName))
        try DefaultZipper().unzipFile(url, destination: store.directory, overwrite: true)
    }

    // MARK: Private

    private let downloadManager: DownloadManager
    private let store: RecitationModelStore

    private func runningDownload() async -> DownloadBatchResponse? {
        await downloadManager.getOnGoingDownloads().first { response in
            response.requests.count == 1 && response.requests.first?.destination == Self.archiveFile
        }
    }
}
