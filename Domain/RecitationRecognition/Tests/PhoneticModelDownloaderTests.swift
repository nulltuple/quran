//
//  PhoneticModelDownloaderTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import BatchDownloader
import BatchDownloaderFake
import XCTest
import ZIPFoundation
@testable import RecitationRecognition

final class PhoneticModelDownloaderTests: XCTestCase {
    private var directory: URL!
    private var archiveURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phonetic-dl-\(UUID().uuidString)", isDirectory: true)
        directory = base.appendingPathComponent("store", isDirectory: true)
        archiveURL = base.appendingPathComponent("pack.zip")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        try super.tearDownWithError()
    }

    func testInstallVerifiesSha256AndUnzipsPack() throws {
        let zip = try Archive(url: archiveURL, accessMode: .create)
        let vocabData = Data("{\"phonemes\":[\"ق\"]}".utf8)
        try zip.addEntry(with: PhoneticModelStore.vocabularyName, type: .file, uncompressedSize: Int64(vocabData.count)) { position, size in
            vocabData.subdata(in: Int(position) ..< Int(position) + size)
        }
        let digest = try RecitationModelDownloader.sha256(of: archiveURL)

        let store = PhoneticModelStore(directory: directory)
        let dm = DownloadManager(
            maxSimultaneousDownloads: 1,
            configuration: .ephemeral,
            downloadsURL: directory.deletingLastPathComponent().appendingPathComponent("dm.db")
        )
        let downloader = PhoneticModelDownloader(
            downloadManager: dm,
            store: store,
            archive: PhoneticModelArchive(url: URL(string: "https://example.com/pack.zip")!, sha256: digest, byteCount: 100)
        )

        try downloader.install(archiveAt: archiveURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(PhoneticModelStore.vocabularyName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testInstallRejectsChecksumMismatchAndDeletesCorruptArchive() throws {
        try Data("corrupt".utf8).write(to: archiveURL)
        let store = PhoneticModelStore(directory: directory)
        let dm = DownloadManager(
            maxSimultaneousDownloads: 1,
            configuration: .ephemeral,
            downloadsURL: directory.deletingLastPathComponent().appendingPathComponent("dm.db")
        )
        let downloader = PhoneticModelDownloader(
            downloadManager: dm,
            store: store,
            archive: PhoneticModelArchive(url: URL(string: "https://example.com/pack.zip")!, sha256: "0000", byteCount: 7)
        )

        XCTAssertThrowsError(try downloader.install(archiveAt: archiveURL)) { error in
            XCTAssertEqual(error as? RecitationModelDownloadError, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertFalse(store.isInstalled)
    }
}
