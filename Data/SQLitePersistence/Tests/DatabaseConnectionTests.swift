//
//  DatabaseConnectionTests.swift
//
//
//  Created by Mohamed Afifi on 2023-05-27.
//

import AsyncUtilitiesForTesting
import Combine
import GRDB
import XCTest
@testable import SQLitePersistence

class DatabaseConnectionTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        // Create a temporary file for the test database.
        testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testURL)
        super.tearDown()
    }

    func test_creation() {
        let connection = DatabaseConnection(url: testURL)
        XCTAssertNotNil(connection)
        // Initially database file is not created.
        XCTAssertFalse(testURL.isReachable)
    }

    func test_readAndWrite() async throws {
        let connection = DatabaseConnection(url: testURL, readonly: false)
        try await connection.insertNames()

        XCTAssertTrue(testURL.isReachable)

        let names = try await connection.readNames()
        XCTAssertEqual(names, ["Alice"])
    }

    func test_readPublisher() async throws {
        let connection = DatabaseConnection(url: testURL, readonly: false)
        try await connection.createNamesTable()
        let publisher = try connection.namesPublisher()
        var cancellable: AnyCancellable?
        let values = AsyncThrowingStream<[String], Error> { continuation in
            cancellable = publisher.sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        continuation.finish()
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                },
                receiveValue: { continuation.yield($0) }
            )
        }
        defer { cancellable?.cancel() }
        var iterator = values.makeAsyncIterator()

        try await assertNextNames([], from: &iterator)

        try await connection.insert(name: "Alice")
        try await assertNextNames(["Alice"], from: &iterator)

        try await connection.insert(name: "Bob")
        try await connection.insert(name: "Derek")
        try await assertNextNames(["Alice", "Bob", "Derek"], from: &iterator)

        try await connection.remove(name: "Bob")
        try await assertNextNames(["Alice", "Derek"], from: &iterator)
    }

    private func assertNextNames(
        _ expectedNames: [String],
        from iterator: inout AsyncThrowingStream<[String], Error>.Iterator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        while let names = try await iterator.next() {
            if Set(expectedNames) == Set(names) {
                return
            }
        }
        XCTFail(
            "Publisher completed before delivering \(expectedNames)",
            file: file,
            line: line
        )
    }

    func test_sharing() async throws {
        let connection1 = DatabaseConnection(url: testURL, readonly: false)
        let connection2 = DatabaseConnection(url: testURL)
        try await connection1.insertNames()
        let names = try await connection2.readNames()
        XCTAssertEqual(names, ["Alice"])
    }

    func test_release() {
        var connection: DatabaseConnection? = DatabaseConnection(url: testURL)
        weak var weakConnection = connection
        connection = nil // should call deinit
        XCTAssertNil(weakConnection)
    }

    func test_corruption() async throws {
        // Simulate a database corruption manually.
        try "corrupted data".write(to: testURL, atomically: true, encoding: .utf8)

        let connection = DatabaseConnection(url: testURL)
        await AsyncAssertThrows(try await {
            _ = try await connection.readNames()
        }(), nil)

        // Database should be deleted because the error is SQLITE_NOTADB.
        XCTAssertFalse(testURL.isReachable)
    }

    // MARK: Bad-file errors

    func test_corruption_reportsBadFile() async throws {
        try "corrupted data".write(to: testURL, atomically: true, encoding: .utf8)
        let connection = DatabaseConnection(url: testURL)

        let error = await persistenceError { _ = try await connection.readNames() }

        // Regression: the error used to be overwritten with `.query` after `.badFile` was assigned.
        assertBadFile(error, code: .SQLITE_NOTADB)
    }

    func test_corruption_keepsFileWhenDeletionIsOff() async throws {
        try "user data".write(to: testURL, atomically: true, encoding: .utf8)
        let connection = DatabaseConnection(url: testURL, readonly: false, deletesBadFile: false)

        let error = await persistenceError { _ = try await connection.readNames() }

        assertBadFile(error, code: .SQLITE_NOTADB)
        XCTAssertEqual(try String(contentsOf: testURL, encoding: .utf8), "user data")
    }

    func test_migrationOfCorruptFile_keepsFileWhenDeletionIsOff() throws {
        try "user data".write(to: testURL, atomically: true, encoding: .utf8)
        let connection = DatabaseConnection(url: testURL, readonly: false, deletesBadFile: false)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("names") { db in
            try db.create(table: "test") { t in t.column("name", .text) }
        }

        XCTAssertThrowsError(try migrator.migrate(connection)) { error in
            assertBadFile(error as? SQLitePersistence.PersistenceError, code: .SQLITE_NOTADB)
        }
        XCTAssertEqual(try String(contentsOf: testURL, encoding: .utf8), "user data")
    }

    func test_badFileErrorWhileReading_keepsDataWhenDeletionIsOff() async throws {
        let connection = DatabaseConnection(url: testURL, readonly: false, deletesBadFile: false)
        try await connection.insertNames()

        for code in [ResultCode.SQLITE_CANTOPEN, .SQLITE_CORRUPT, .SQLITE_PERM, .SQLITE_NOTADB] {
            let error = await persistenceError {
                _ = try await connection.read { _ in throw DatabaseError(resultCode: code) }
            }
            assertBadFile(error, code: code)
        }

        XCTAssertTrue(testURL.isReachable)
        let names = try await connection.readNames()
        XCTAssertEqual(names, ["Alice"])
    }

    func test_badFileErrorWhileWriting_keepsDataWhenDeletionIsOff() async throws {
        let connection = DatabaseConnection(url: testURL, readonly: false, deletesBadFile: false)
        try await connection.insertNames()

        let error = await persistenceError {
            _ = try await connection.write { _ in throw DatabaseError(resultCode: .SQLITE_CANTOPEN) }
        }

        assertBadFile(error, code: .SQLITE_CANTOPEN)
        let names = try await connection.readNames()
        XCTAssertEqual(names, ["Alice"])
    }

    func test_badFileErrorWhileReading_deletesFileByDefault() async throws {
        let writer = DatabaseConnection(url: testURL, readonly: false)
        try await writer.insertNames()

        let error = await persistenceError {
            _ = try await writer.read { _ in throw DatabaseError(resultCode: .SQLITE_CORRUPT) }
        }

        assertBadFile(error, code: .SQLITE_CORRUPT)
        XCTAssertFalse(testURL.isReachable)
    }

    func test_otherDatabaseError_isQueryErrorAndKeepsFile() async throws {
        let connection = DatabaseConnection(url: testURL, readonly: false)
        try await connection.insertNames()

        let error = await persistenceError {
            _ = try await connection.read { db in try String.fetchAll(db, sql: "SELECT missing FROM test") }
        }

        guard case .query = error else {
            return XCTFail("Expected .query, got \(String(describing: error))")
        }
        XCTAssertTrue(testURL.isReachable)
    }

    func test_persistenceErrorFromBlock_isPassedThrough() async throws {
        let connection = DatabaseConnection(url: testURL, readonly: false)
        try await connection.insertNames()

        let error = await persistenceError {
            _ = try await connection.read { _ in throw SQLitePersistence.PersistenceError.general("from block") }
        }

        // Regression: the error used to be overwritten with `.query`.
        guard case .general(let message) = error else {
            return XCTFail("Expected .general, got \(String(describing: error))")
        }
        XCTAssertEqual(message, "from block")
    }

    // MARK: Private

    private var testURL: URL!

    private func persistenceError(
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SQLitePersistence.PersistenceError? {
        do {
            try await body()
            XCTFail("Expected an error", file: file, line: line)
            return nil
        } catch {
            guard let error = error as? SQLitePersistence.PersistenceError else {
                XCTFail("Expected PersistenceError, got \(error)", file: file, line: line)
                return nil
            }
            return error
        }
    }

    private func assertBadFile(
        _ error: SQLitePersistence.PersistenceError?,
        code: ResultCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .badFile(let underlying) = error else {
            return XCTFail("Expected .badFile, got \(String(describing: error))", file: file, line: line)
        }
        XCTAssertEqual((underlying as? DatabaseError)?.resultCode, code, file: file, line: line)
    }
}

private extension DatabaseConnection {
    func createNamesTable() async throws {
        try await write { db in
            try db.create(table: "test") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text)
            }
        }
    }

    func insertNames() async throws {
        try await createNamesTable()
        try await insert(name: "Alice")
    }

    func insert(name: String) async throws {
        try await write { db in
            try db.execute(sql: "INSERT INTO test (name) VALUES (?)", arguments: StatementArguments([name]))
        }
    }

    func remove(name: String) async throws {
        try await write { db in
            try db.execute(sql: "DELETE FROM test WHERE name = ?", arguments: [name])
        }
    }

    func namesPublisher() throws -> AnyPublisher<[String], Error> {
        try readPublisher { db in
            try String.fetchAll(db, sql: "SELECT name FROM test")
        }
    }

    func readNames() async throws -> [String] {
        try await read { db in
            try String.fetchAll(db, sql: "SELECT name FROM test")
        }
    }

    private func createNamesTable(in db: Database) throws {
        try db.create(table: "test", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text)
        }
    }
}
