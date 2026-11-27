//
//  BackupViewModelTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import BackupPersistence
import BackupService
import CoreDataPersistence
import CoreDataPersistenceTestSupport
import XCTest
@testable import SettingsFeature

@MainActor
final class BackupViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        store = TemporaryCoreDataStore()
        persistence = CoreDataBackupPersistence(stack: store.stack())
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sharedURLs = []
        shareCompletions = []
        viewModel = BackupViewModel(
            service: BackupService(persistence: persistence, appVersion: "1.0 (1)", now: { Date(timeIntervalSince1970: 1_800_000_000) }),
            temporaryDirectory: directory
        ) { [unowned self] url, completion in
            sharedURLs.append(url)
            shareCompletions.append(completion)
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        viewModel = nil
        persistence = nil
        store = nil
        try await super.tearDown()
    }

    func testExportSharesAJSONFileAndRemovesItWhenTheSheetCloses() async throws {
        try await persistence.restore(sample, mode: .replace)

        await viewModel.exportBackup()

        let url = try XCTUnwrap(sharedURLs.first)
        XCTAssertEqual(url.lastPathComponent, "Quran Backup 2027-01-15.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, BackupService.format)
        XCTAssertEqual(viewModel.state, .idle)

        shareCompletions.first?()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testReadingABackupShowsItsCountsWithoutWriting() async throws {
        let url = try await exportedFile(of: sample)

        await viewModel.readBackup(at: url)

        guard case .preview(let summary) = viewModel.state else {
            return XCTFail("Expected a preview, got \(viewModel.state)")
        }
        XCTAssertEqual(summary.notes, 1)
        XCTAssertEqual(summary.pageBookmarks, 1)
        let stored = try await persistence.snapshot()
        XCTAssertTrue(stored.isEmpty)
    }

    func testMergingAddsTheBackupAndReportsIt() async throws {
        let existing = BackupSnapshot(pageBookmarks: [BackupPage(mushafID: 0, page: 300, createdOn: date(1), modifiedOn: date(1))])
        try await persistence.restore(existing, mode: .replace)
        await viewModel.readBackup(at: try await exportedFile(of: sample))

        await viewModel.restore(.merge)

        let stored = try await persistence.snapshot()
        XCTAssertEqual(stored.pageBookmarks.map(\.page), [5, 300])
        XCTAssertEqual(stored.notes, sample.notes)
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(viewModel.isRestoredAlertPresented)
    }

    func testReplacingDeletesRecordsTheBackupDoesNotHave() async throws {
        let existing = BackupSnapshot(pageBookmarks: [BackupPage(mushafID: 0, page: 300, createdOn: date(1), modifiedOn: date(1))])
        try await persistence.restore(existing, mode: .replace)
        await viewModel.readBackup(at: try await exportedFile(of: sample))

        viewModel.confirmReplace()
        XCTAssertTrue(viewModel.isReplaceConfirmationPresented)
        await viewModel.restore(.replace)

        let stored = try await persistence.snapshot()
        XCTAssertEqual(stored, sample)
    }

    func testAFileThatIsNotABackupShowsAnErrorAndChangesNothing() async throws {
        try await persistence.restore(sample, mode: .replace)
        let url = directory.appendingPathComponent("notes.json")
        try Data(#"{"hello": "world"}"#.utf8).write(to: url)

        await viewModel.readBackup(at: url)
        await viewModel.restore(.replace)

        XCTAssertEqual(viewModel.error as? BackupError, .notABackup)
        XCTAssertEqual(viewModel.error?.localizedDescription, "This file isn't a Quran backup.")
        XCTAssertEqual(viewModel.state, .idle)
        let stored = try await persistence.snapshot()
        XCTAssertEqual(stored, sample)
    }

    func testCancellingThePreviewForgetsTheBackup() async throws {
        await viewModel.readBackup(at: try await exportedFile(of: sample))

        viewModel.cancelPreview()
        await viewModel.restore(.merge)

        XCTAssertEqual(viewModel.state, .idle)
        let stored = try await persistence.snapshot()
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: Private

    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataBackupPersistence!
    private var directory: URL!
    private var viewModel: BackupViewModel!
    private var sharedURLs: [URL] = []
    private var shareCompletions: [() -> Void] = []

    private var sample: BackupSnapshot {
        BackupSnapshot(
            notes: [BackupNote(verses: [BackupVerse(sura: 1, ayah: 1)], text: "Opening", color: 0, createdOn: date(10), modifiedOn: date(10))],
            pageBookmarks: [BackupPage(mushafID: 0, page: 5, createdOn: date(20), modifiedOn: date(20))]
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    /// Exports `snapshot` from another store, as a backup made on another device.
    private func exportedFile(of snapshot: BackupSnapshot) async throws -> URL {
        let otherStore = TemporaryCoreDataStore()
        let other = CoreDataBackupPersistence(stack: otherStore.stack())
        try await other.restore(snapshot, mode: .replace)
        let backup = try await BackupService(persistence: other, appVersion: "1.0 (1)").exportBackup()
        let url = directory.appendingPathComponent("\(UUID().uuidString).json")
        try backup.data.write(to: url)
        return url
    }
}
