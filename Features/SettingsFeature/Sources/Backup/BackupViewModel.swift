//
//  BackupViewModel.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import BackupPersistence
import BackupService
import Combine
import Foundation
import Localization
import VLogging

@MainActor
final class BackupViewModel: ObservableObject {
    // MARK: Lifecycle

    /// - Parameter share: presents the share sheet for a file and calls its completion when the sheet closes.
    init(
        service: BackupService,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        share: @escaping @MainActor (URL, @escaping () -> Void) -> Void
    ) {
        self.service = service
        self.temporaryDirectory = temporaryDirectory
        self.share = share
    }

    // MARK: Internal

    enum State: Equatable {
        case idle
        case working
        /// A backup was read and checked; nothing is written until the user picks merge or replace.
        case preview(BackupSummary)
    }

    @Published private(set) var state: State = .idle
    @Published var error: Error?
    @Published var isImporterPresented = false
    @Published var isReplaceConfirmationPresented = false
    @Published var isRestoredAlertPresented = false

    var isWorking: Bool {
        state == .working
    }

    func exportBackup() async {
        logger.info("Backup: export")
        state = .working
        defer { state = .idle }
        do {
            let directory = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let url = directory.appendingPathComponent(service.exportFileName())
            let backup = try await service.exportBackup()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try backup.data.write(to: url, options: .atomic)
            share(url) {
                try? FileManager.default.removeItem(at: directory)
            }
        } catch {
            logger.error("Backup: export failed \(error)")
            self.error = error
        }
    }

    func presentImporter() {
        isImporterPresented = true
    }

    func importFile(_ result: Result<URL, Error>) async {
        switch result {
        case .success(let url):
            await readBackup(at: url)
        case .failure(let error):
            self.error = error
        }
    }

    func readBackup(at url: URL) async {
        logger.info("Backup: read")
        state = .working
        do {
            let backup = try await Self.readBackup(at: url, service: service)
            pendingBackup = backup
            state = .preview(backup.summary)
        } catch {
            logger.error("Backup: read failed \(error)")
            pendingBackup = nil
            state = .idle
            self.error = error
        }
    }

    func confirmReplace() {
        isReplaceConfirmationPresented = true
    }

    func restore(_ mode: BackupRestoreMode) async {
        guard let pendingBackup else {
            return
        }
        logger.info("Backup: restore \(mode)")
        state = .working
        do {
            try await service.restore(pendingBackup, mode: mode)
            self.pendingBackup = nil
            state = .idle
            isRestoredAlertPresented = true
        } catch {
            logger.error("Backup: restore failed \(error)")
            // The restore is one save, so the backup can be tried again.
            state = .preview(pendingBackup.summary)
            self.error = error
        }
    }

    func cancelPreview() {
        pendingBackup = nil
        state = .idle
    }

    // MARK: Private

    private let service: BackupService
    private let temporaryDirectory: URL
    private let share: @MainActor (URL, @escaping () -> Void) -> Void
    private var pendingBackup: ValidatedBackup?

    /// Reads and decodes off the main actor. Files from the document picker need security-scoped access.
    private nonisolated static func readBackup(at url: URL, service: BackupService) async throws -> ValidatedBackup {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= BackupService.maximumFileSize else {
            throw BackupError.tooLarge
        }
        let data = try Data(contentsOf: url)
        return try service.readBackup(data)
    }
}

/// The error alert shows these messages.
extension BackupError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notABackup: l("backup.error.not-a-backup")
        case .newerVersion: l("backup.error.newer-version")
        case .damaged: l("backup.error.damaged")
        case .invalidRecord: l("backup.error.invalid-record")
        case .tooLarge: l("backup.error.too-large")
        }
    }
}
