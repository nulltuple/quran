//
//  BackupSnapshot.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Foundation
import MemorizationPersistence

/// Every user-authored record in the Core Data store, as plain values.
///
/// Records in the store have no identifiers except collections, so each record is identified by its
/// natural key: a note by its verses, a page bookmark and a recent page by mushaf and page, a collection
/// by its ID (or its name when the ID is new), and a collection verse by sura and ayah.
public struct BackupSnapshot: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        notes: [BackupNote] = [],
        pageBookmarks: [BackupPage] = [],
        recentPages: [BackupPage] = [],
        collections: [BackupCollection] = [],
        practiceSessions: [PracticeSessionRecord] = [],
        recallEvidence: [RecallEvidenceRecord] = []
    ) {
        self.notes = notes
        self.pageBookmarks = pageBookmarks
        self.recentPages = recentPages
        self.collections = collections
        self.practiceSessions = practiceSessions
        self.recallEvidence = recallEvidence
    }

    /// Schema 1 files have no learning records; they decode as empty.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notes = try container.decode([BackupNote].self, forKey: .notes)
        pageBookmarks = try container.decode([BackupPage].self, forKey: .pageBookmarks)
        recentPages = try container.decode([BackupPage].self, forKey: .recentPages)
        collections = try container.decode([BackupCollection].self, forKey: .collections)
        practiceSessions = try container.decodeIfPresent([PracticeSessionRecord].self, forKey: .practiceSessions) ?? []
        recallEvidence = try container.decodeIfPresent([RecallEvidenceRecord].self, forKey: .recallEvidence) ?? []
    }

    // MARK: Public

    /// Notes and highlights. A highlight is a note without text.
    public var notes: [BackupNote]
    public var pageBookmarks: [BackupPage]
    /// Recently read pages, newest first.
    public var recentPages: [BackupPage]
    public var collections: [BackupCollection]
    /// Hifz practice (schema 2). Their field names are part of the format, as `MemorizationPersistence` declares
    /// them: rename only with a new schema version.
    public var practiceSessions: [PracticeSessionRecord]
    /// Append-only; retracted records are kept so a merge can retract them elsewhere.
    public var recallEvidence: [RecallEvidenceRecord]

    public var isEmpty: Bool {
        notes.isEmpty && pageBookmarks.isEmpty && recentPages.isEmpty && collections.isEmpty
            && practiceSessions.isEmpty && recallEvidence.isEmpty
    }
}

public struct BackupVerse: Codable, Hashable, Comparable, Sendable {
    // MARK: Lifecycle

    public init(sura: Int, ayah: Int) {
        self.sura = sura
        self.ayah = ayah
    }

    // MARK: Public

    public let sura: Int
    public let ayah: Int

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.sura, lhs.ayah) < (rhs.sura, rhs.ayah)
    }
}

public struct BackupNote: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(verses: [BackupVerse], text: String?, color: Int, createdOn: Date, modifiedOn: Date) {
        self.verses = verses
        self.text = text
        self.color = color
        self.createdOn = createdOn
        self.modifiedOn = modifiedOn
    }

    // MARK: Public

    /// Sorted, without duplicates.
    public let verses: [BackupVerse]
    /// `nil` or blank for a highlight.
    public let text: String?
    /// A `HighlightColor` raw value.
    public let color: Int
    public let createdOn: Date
    public let modifiedOn: Date

    public var hasText: Bool {
        !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct BackupPage: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(mushafID: Int, page: Int, createdOn: Date, modifiedOn: Date) {
        self.mushafID = mushafID
        self.page = page
        self.createdOn = createdOn
        self.modifiedOn = modifiedOn
    }

    // MARK: Public

    /// A `QuranPageMushaf` raw value.
    public let mushafID: Int
    public let page: Int
    public let createdOn: Date
    public let modifiedOn: Date
}

public struct BackupCollection: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        name: String,
        isDefault: Bool,
        createdOn: Date,
        modifiedOn: Date,
        verses: [BackupCollectionVerse]
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.createdOn = createdOn
        self.modifiedOn = modifiedOn
        self.verses = verses
    }

    // MARK: Public

    public let id: UUID
    public let name: String
    /// Favorites.
    public let isDefault: Bool
    public let createdOn: Date
    public let modifiedOn: Date
    /// Oldest first.
    public let verses: [BackupCollectionVerse]
}

public struct BackupCollectionVerse: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(verse: BackupVerse, createdOn: Date) {
        sura = verse.sura
        ayah = verse.ayah
        self.createdOn = createdOn
    }

    // MARK: Public

    public let sura: Int
    public let ayah: Int
    public let createdOn: Date

    public var verse: BackupVerse {
        BackupVerse(sura: sura, ayah: ayah)
    }
}

public enum BackupRestoreMode: Sendable {
    /// Adds the backup's records to the existing ones. Restoring the same backup twice changes nothing.
    case merge
    /// Deletes every existing record, then adds the backup's, in one save.
    case replace
}
