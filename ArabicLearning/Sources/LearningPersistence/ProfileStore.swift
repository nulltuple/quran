//
//  ProfileStore.swift
//  ArabicLearning (Arabican app)
//
//  Learner state is user data: these stores use GRDB directly, not QuranEngine's
//  DatabaseConnection, which deletes a database file on SQLITE_CANTOPEN/NOTADB/CORRUPT
//  (Data/SQLitePersistence/Sources/DatabaseConnection.swift). A locked or damaged file must
//  surface an error, never erase progress.
//

import Foundation
import GRDB
import LearningModel

/// The list of local profiles and which one is active, in `<directory>/profiles.sqlite`. Each
/// profile's progress is a separate `ProgressStore` file in the same directory.
public final class ProfileStore: Sendable {
    // MARK: Lifecycle

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        queue = try DatabaseQueue(path: directory.appendingPathComponent("profiles.sqlite").path)
        try Self.migrator.migrate(queue)
    }

    // MARK: Public

    /// `Application Support/Arabican`, excluded from nothing (backed up like other app data).
    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Arabican", isDirectory: true)
    }

    public let directory: URL

    public func profiles() async throws -> [LearnerProfile] {
        try await queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM profile ORDER BY created_at, id").map(Self.profile)
        }
    }

    public func create(name: String, presentation: PresentationProfile, now: Date = Date()) async throws -> LearnerProfile {
        let profile = LearnerProfile(id: UUID(), name: name, presentation: presentation, createdAt: now)
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO profile(id, name, presentation, created_at) VALUES(?, ?, ?, ?)",
                arguments: [profile.id.uuidString, profile.name, profile.presentation.rawValue, profile.createdAt]
            )
            try Self.setActive(profile.id, db)
        }
        return profile
    }

    public func activeProfile() async throws -> LearnerProfile? {
        try await queue.read { db in
            try Row.fetchOne(db, sql: """
            SELECT profile.* FROM profile JOIN meta ON meta.key = 'active_profile' AND meta.value = profile.id
            """).map(Self.profile)
        }
    }

    public func setActive(_ id: UUID) async throws {
        try await queue.write { try Self.setActive(id, $0) }
    }

    /// Deletes the profile and its progress file.
    public func delete(_ id: UUID) async throws {
        try await queue.write { db in
            try db.execute(sql: "DELETE FROM profile WHERE id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM meta WHERE key = 'active_profile' AND value = ?", arguments: [id.uuidString])
        }
        let file = progressURL(for: id)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// The progress store of `id`; created on first use.
    public func progress(for id: UUID) throws -> ProgressStore {
        try ProgressStore(fileURL: progressURL(for: id))
    }

    public func progressURL(for id: UUID) -> URL {
        directory.appendingPathComponent("progress-\(id.uuidString).sqlite")
    }

    // MARK: Private

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1 profiles") { db in
            try db.execute(sql: """
            CREATE TABLE profile(id TEXT PRIMARY KEY, name TEXT NOT NULL, presentation TEXT NOT NULL, created_at DATETIME NOT NULL);
            CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
        }
        return migrator
    }

    private let queue: DatabaseQueue

    private static func setActive(_ id: UUID, _ db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO meta(key, value) VALUES('active_profile', ?)", arguments: [id.uuidString])
    }

    private static func profile(_ row: Row) throws -> LearnerProfile {
        guard let id = UUID(uuidString: row["id"]), let presentation = PresentationProfile(rawValue: row["presentation"]) else {
            throw StoreError.malformedRow
        }
        return LearnerProfile(id: id, name: row["name"], presentation: presentation, createdAt: row["created_at"])
    }
}

public enum StoreError: Error, Equatable {
    case malformedRow
}
