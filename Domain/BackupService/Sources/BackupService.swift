//
//  BackupService.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import BackupPersistence
import Foundation
import QuranAnnotations
import QuranKit

/// Exports the user's notes, highlights, bookmarks, collections and recent pages as a versioned JSON file,
/// and restores one after validating all of it.
///
/// Nothing here touches the network. A backup is checked completely before ``restore(_:mode:)`` can be
/// called with it, and the restore itself is one Core Data save, so an invalid or interrupted import leaves
/// the store as it was.
public struct BackupService: Sendable {
    // MARK: Lifecycle

    public init(persistence: CoreDataBackupPersistence, appVersion: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.persistence = persistence
        self.appVersion = appVersion
        self.now = now
    }

    // MARK: Public

    /// Identifies the file as a backup of this app.
    public static let format = "com.nulltup.memquran.backup"
    /// The schema this build writes and the newest it reads.
    public static let schemaVersion = 1
    /// Larger files are refused before decoding; a real backup is a few hundred kilobytes.
    public static let maximumFileSize = 20 * 1024 * 1024

    /// The JSON of every record, and the counts it holds.
    public func exportBackup() async throws -> (data: Data, summary: BackupSummary) {
        let document = BackupDocument(
            format: Self.format,
            schemaVersion: Self.schemaVersion,
            appVersion: appVersion,
            exportedAt: now(),
            data: try await persistence.snapshot()
        )
        let data = try Self.encoder().encode(document)
        return (data, BackupSummary(document))
    }

    /// A file name such as `Quran Backup 2026-11-26.json`.
    public func exportFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Quran Backup \(formatter.string(from: now())).json"
    }

    /// Decodes and validates a backup file without writing anything.
    public func readBackup(_ data: Data) throws -> ValidatedBackup {
        guard data.count <= Self.maximumFileSize else {
            throw BackupError.tooLarge
        }
        let decoder = Self.decoder()
        // The header first, so a newer schema is reported as newer rather than unreadable.
        guard let header = try? decoder.decode(BackupHeader.self, from: data), header.format == Self.format else {
            throw BackupError.notABackup
        }
        guard header.schemaVersion <= Self.schemaVersion else {
            throw BackupError.newerVersion
        }
        guard header.schemaVersion >= 1 else {
            throw BackupError.notABackup
        }
        let document: BackupDocument
        do {
            document = try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.damaged
        }
        try Self.validate(document.data)
        return ValidatedBackup(snapshot: document.data, summary: BackupSummary(document))
    }

    /// Writes a validated backup: merged with the existing records, or replacing them.
    public func restore(_ backup: ValidatedBackup, mode: BackupRestoreMode) async throws {
        try await persistence.restore(backup.snapshot, mode: mode)
    }

    // MARK: Internal

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalSecondsFormatter().string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = fractionalSecondsFormatter().date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
            }
            return date
        }
        return decoder
    }

    // MARK: Private

    private let persistence: CoreDataBackupPersistence
    private let appVersion: String
    private let now: @Sendable () -> Date

    private static func fractionalSecondsFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    /// Every record must name a real verse, page, color and collection name; nothing is written otherwise.
    private static func validate(_ snapshot: BackupSnapshot) throws {
        func check(_ verse: BackupVerse) throws {
            guard AyahNumber(quran: .hafsMadani1405, sura: verse.sura, ayah: verse.ayah) != nil else {
                throw BackupError.invalidRecord
            }
        }
        func check(_ page: BackupPage) throws {
            guard let mushafID = Int16(exactly: page.mushafID),
                  let mushaf = QuranPageMushaf(rawValue: mushafID),
                  Page(quran: mushaf.quran, pageNumber: page.page) != nil
            else {
                throw BackupError.invalidRecord
            }
        }

        for note in snapshot.notes {
            guard !note.verses.isEmpty, HighlightColor(rawValue: note.color) != nil else {
                throw BackupError.invalidRecord
            }
            try note.verses.forEach(check)
        }
        try snapshot.pageBookmarks.forEach(check)
        try snapshot.recentPages.forEach(check)
        for collection in snapshot.collections {
            let name = collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard AyahBookmarkCollection.nameLengthLimit.contains(name.count) else {
                throw BackupError.invalidRecord
            }
            try collection.verses.map(\.verse).forEach(check)
        }
    }
}

/// A backup that decoded and passed every check, ready to restore.
public struct ValidatedBackup: Sendable {
    public let snapshot: BackupSnapshot
    public let summary: BackupSummary
}

/// What a backup holds, for the preview before restoring.
public struct BackupSummary: Equatable, Sendable {
    // MARK: Lifecycle

    init(_ document: BackupDocument) {
        let snapshot = document.data
        notes = snapshot.notes.filter(\.hasText).count
        highlights = snapshot.notes.count - notes
        pageBookmarks = snapshot.pageBookmarks.count
        recentPages = snapshot.recentPages.count
        collections = snapshot.collections.count
        collectionVerses = snapshot.collections.reduce(0) { $0 + $1.verses.count }
        exportedAt = document.exportedAt
        appVersion = document.appVersion
    }

    // MARK: Public

    public let notes: Int
    public let highlights: Int
    public let pageBookmarks: Int
    public let recentPages: Int
    public let collections: Int
    /// Verses across all collections, Favorites included.
    public let collectionVerses: Int
    public let exportedAt: Date
    public let appVersion: String

    public var isEmpty: Bool {
        notes + highlights + pageBookmarks + recentPages + collections == 0
    }
}

public enum BackupError: Error, Equatable, Sendable {
    /// Not JSON, or not this app's backup format.
    case notABackup
    /// Written by a newer version of the app.
    case newerVersion
    /// The right format, but fields are missing or of the wrong type.
    case damaged
    /// A verse, page, color or collection name that cannot exist.
    case invalidRecord
    case tooLarge
}

/// The file's top level. Field names are part of the format: rename only with a new schema version.
struct BackupDocument: Codable {
    let format: String
    let schemaVersion: Int
    let appVersion: String
    let exportedAt: Date
    let data: BackupSnapshot
}

private struct BackupHeader: Decodable {
    let format: String
    let schemaVersion: Int
}
