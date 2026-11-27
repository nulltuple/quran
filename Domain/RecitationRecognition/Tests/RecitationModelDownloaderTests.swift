//
//  RecitationModelDownloaderTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import BatchDownloader
import BatchDownloaderFake
import NetworkSupportFake
import XCTest
import ZIPFoundation
@testable import RecitationRecognition

/// The download, check and install of the model archive, with the app's `DownloadManager` over a
/// fake network session and the real file system (a small stand-in archive, not the 84 MB model).
final class RecitationModelDownloaderTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = RecitationModelStore(directory: directory.appendingPathComponent("RecitationModel", isDirectory: true))
        archiveURL = try makeArchive()
        archive = try RecitationModelArchive(
            url: XCTUnwrap(URL(string: "https://example.com/recitation-model-1.zip")),
            sha256: RecitationModelDownloader.sha256(of: archiveURL),
            byteCount: 0
        )
        testContext = BatchDownloaderFake.makeContext()
        (downloadManager, session) = await testContext.makeDownloader()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: RecitationModelDownloader.archiveFile.url)
        testContext = nil
        try await super.tearDown()
    }

    func testTheDownloadedArchiveIsCheckedAndUnzippedIntoTheModelDirectory() async throws {
        let downloader = RecitationModelDownloader(downloadManager: downloadManager, store: store, archive: archive)
        let progress = ManagedProgress()
        let download = Task { try await downloader.download { progress.record($0) } }

        let task = try await firstDownloadTask()
        XCTAssertEqual(task.originalRequest?.url, archive.url)
        // The download manager moves the finished file to the archive's place under Documents.
        let delivered = directory.appendingPathComponent("delivered.zip")
        try FileManager.default.copyItem(at: archiveURL, to: delivered)
        await session.completeDownloadTask(task, location: delivered, totalBytes: 100, progressLoops: 1)
        try await download.value

        XCTAssertEqual(try String(contentsOf: store.directory.appendingPathComponent(RecitationModelStore.vocabularyName), encoding: .utf8), #"{"0": "<unk>"}"#)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(RecitationModelStore.packageName).appendingPathComponent("Manifest.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecitationModelDownloader.archiveFile.url.path), "the archive is deleted once installed")
        XCTAssertFalse(progress.values.isEmpty)
    }

    func testAnArchiveThatIsNotThePublishedOneIsRejectedAndDeleted() throws {
        let wrong = RecitationModelArchive(url: archive.url, sha256: String(repeating: "0", count: 64), byteCount: 0)
        let downloader = RecitationModelDownloader(downloadManager: downloadManager, store: store, archive: wrong)

        XCTAssertThrowsError(try downloader.install(archiveAt: archiveURL)) { error in
            XCTAssertEqual(error as? RecitationModelDownloadError, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(RecitationModelStore.vocabularyName).path))
    }

    func testInstallingDropsAModelCompiledFromAnOlderPackage() throws {
        let compiled = store.directory.appendingPathComponent(RecitationModelStore.compiledName)
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        let downloader = RecitationModelDownloader(downloadManager: downloadManager, store: store, archive: archive)

        try downloader.install(archiveAt: archiveURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: compiled.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(RecitationModelStore.vocabularyName).path))
    }

    func testTheSha256IsLowercaseHex() throws {
        let file = directory.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try RecitationModelDownloader.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: Private

    private final class ManagedProgress: @unchecked Sendable {
        var values: [Double] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func record(_ value: Double) {
            lock.lock()
            recorded.append(value)
            lock.unlock()
        }

        private let lock = NSLock()
        private var recorded: [Double] = []
    }

    private var directory: URL!
    private var store: RecitationModelStore!
    private var archiveURL: URL!
    private var archive: RecitationModelArchive!
    private var testContext: BatchDownloaderTestContext!
    private var downloadManager: DownloadManager!
    private var session: NetworkSessionFake!

    /// A stand-in archive laid out like the published one.
    private func makeArchive() throws -> URL {
        let content = directory.appendingPathComponent("content", isDirectory: true)
        let package = content.appendingPathComponent(RecitationModelStore.packageName, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: package.appendingPathComponent("Manifest.json"))
        try Data(#"{"0": "<unk>"}"#.utf8).write(to: content.appendingPathComponent(RecitationModelStore.vocabularyName))
        let zip = directory.appendingPathComponent("archive.zip")
        try FileManager.default.zipItem(at: content, to: zip, shouldKeepParent: false)
        return zip
    }

    private func firstDownloadTask() async throws -> SessionTask {
        for _ in 0 ..< 500 {
            if let task = session.downloads.first {
                return task
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("the download did not start within 5 s")
        throw CancellationError()
    }
}
