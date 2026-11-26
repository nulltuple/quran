//
//  DatabaseConnection.swift
//
//
//  Created by Mohamed Afifi on 2023-05-25.
//

import Combine
import Foundation
import GRDB
import Utilities
import VLogging

private struct DatabaseConnectionPool: Sendable {
    private struct Connection {
        let database: DatabaseWriter
        var references: Int
    }

    private struct State {
        var connections: [URL: Connection] = [:]
    }

    // MARK: Internal

    func database(for url: URL, readonly: Bool, deletesBadFile: Bool) throws -> DatabaseWriter {
        try state.withCriticalRegion { state in
            if var connection = state.connections[url] {
                connection.references += 1
                state.connections[url] = connection
                return connection.database
            }

            // Create the database folder if needed.
            try? FileManager.default.createDirectory(
                atPath: url.path.stringByDeletingLastPathComponent,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let database = try newDatabase(url: url, readonly: readonly, deletesBadFile: deletesBadFile)
            let newConnection = Connection(database: database, references: 1)
            state.connections[url] = newConnection
            return newConnection.database
        }
    }

    func releaseDatabase(for url: URL) {
        state.withCriticalRegion { state in
            if var connection = state.connections[url] {
                connection.references -= 1
                if connection.references == 0 {
                    state.connections[url] = nil
                } else {
                    state.connections[url] = connection
                }
            }
        }
    }

    // MARK: Private

    private let state = ManagedCriticalState(State())

    private func newDatabase(url: URL, readonly: Bool, deletesBadFile: Bool) throws -> DatabaseWriter {
        do {
            return try attempt(times: 3) {
                var configuration = Configuration()
                configuration.readonly = readonly
                // TODO: Remove and use singletons instead.
                configuration.busyMode = .timeout(5)
                return try DatabasePool(path: url.path, configuration: configuration)
            }
        } catch {
            logger.error("Cannot open sqlite file \(url). Error: \(error)")
            throw PersistenceError(error, databaseURL: url, deletesBadFile: deletesBadFile)
        }
    }
}

public final class DatabaseConnection: Sendable {
    private struct State {
        var database: DatabaseWriter?
    }

    // MARK: Lifecycle

    /// - Parameters:
    ///   - url: The SQLite file.
    ///   - readonly: Opens the file read-only.
    ///   - deletesBadFile: Deletes the file when SQLite reports it unusable (`SQLITE_PERM`,
    ///     `SQLITE_NOTADB`, `SQLITE_CORRUPT`, `SQLITE_CANTOPEN`), so a broken download is fetched
    ///     again. Keep the default only for files the app can re-download or rebuild. Pass `false`
    ///     for any file that holds user data: `SQLITE_CANTOPEN` can be transient (for example file
    ///     protection while the device is locked), and deleting the file would erase that data.
    public init(url: URL, readonly: Bool = true, deletesBadFile: Bool = true) {
        databaseURL = url
        self.readonly = readonly
        self.deletesBadFile = deletesBadFile
    }

    deinit {
        state.withCriticalRegion { state in
            if state.database != nil {
                Self.connectionPool.releaseDatabase(for: databaseURL)
            }
        }
    }

    // MARK: Public

    public func read<T>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        let database = try getDatabase()
        do {
            return try await database.read(block)
        } catch {
            logger.error("General error while executing query. Error: \(error).")
            throw PersistenceError(error, databaseURL: databaseURL, deletesBadFile: deletesBadFile)
        }
    }

    /// Creates a publisher that tracks changes in the results of database requests,
    /// and notifies fresh values whenever the database changes
    ///
    /// The first value is notified when the publisher is created. Subsequent changes *may* get coalesced in notifications.
    public func readPublisher<T>(_ block: @Sendable @escaping (Database) throws -> T) throws -> AnyPublisher<T, Error> {
        // - ValueObservation may coalesce subsequent changes into a single notification
        // - ValueObservation fetches a fresh value immediately after a change *is committed in the database*.
        // - By default, delivers on the main thread.
        ValueObservation
            .tracking(block)
            .publisher(in: try getDatabase())
            .eraseToAnyPublisher()
    }

    public func write<T>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        let database = try getDatabase()
        do {
            return try await database.write(block)
        } catch {
            logger.error("General error while executing query. Error: \(error).")
            throw PersistenceError(error, databaseURL: databaseURL, deletesBadFile: deletesBadFile)
        }
    }

    // MARK: Internal

    let databaseURL: URL
    let readonly: Bool
    let deletesBadFile: Bool

    func getDatabase() throws -> DatabaseWriter {
        try state.withCriticalRegion { state in
            if let database = state.database {
                return database
            }

            let database = try Self.connectionPool.database(
                for: databaseURL,
                readonly: readonly,
                deletesBadFile: deletesBadFile
            )
            state.database = database
            return database
        }
    }

    // MARK: Private

    private static let connectionPool = DatabaseConnectionPool()

    private let state = ManagedCriticalState(State())
}

extension PersistenceError {
    private static let badFileCodes: [ResultCode] = [
        .SQLITE_PERM,
        .SQLITE_NOTADB,
        .SQLITE_CORRUPT,
        .SQLITE_CANTOPEN,
    ]

    /// Maps an error from GRDB. Each branch returns, so a later branch never overwrites an
    /// earlier one.
    init(_ error: Error, databaseURL: URL, deletesBadFile: Bool) {
        if let error = error as? PersistenceError {
            self = error
            return
        }
        if let error = error as? DatabaseError, Self.badFileCodes.contains(error.extendedResultCode) {
            if deletesBadFile {
                // Remove the file: sometimes a download completes with an error, and it is fetched again.
                try? FileManager.default.removeItem(at: databaseURL)
                logger.error("Bad file error; removed the database file. Error: \(error).")
            } else {
                logger.error("Bad file error; kept the database file. Error: \(error).")
            }
            self = .badFile(error)
            return
        }
        self = .query(error)
    }
}

extension DatabaseMigrator {
    public func migrate(_ connection: DatabaseConnection) throws {
        let database = try connection.getDatabase()
        do {
            try migrate(database)
        } catch {
            throw PersistenceError(error, databaseURL: connection.databaseURL, deletesBadFile: connection.deletesBadFile)
        }
    }
}
