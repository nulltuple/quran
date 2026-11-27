//
//  RecitationModelStoreTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import XCTest
@testable import RecitationRecognition

final class RecitationModelStoreTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testAnEmptyDirectoryHasNoModel() async throws {
        let model = try await RecitationModelStore(directory: directory).loadModel()
        XCTAssertNil(model)
    }

    func testAVocabularyWithoutTheModelIsNoModel() async throws {
        try Data(#"{"0": "<unk>"}"#.utf8).write(to: directory.appendingPathComponent(RecitationModelStore.vocabularyName))
        let model = try await RecitationModelStore(directory: directory).loadModel()
        XCTAssertNil(model)
    }

    func testThePackageIsCompiledOnceAndKept() async throws {
        let package = Self.cachedModel.appendingPathComponent(RecitationModelStore.packageName)
        let vocabulary = Self.cachedModel.appendingPathComponent("source/vocab.json")
        guard FileManager.default.fileExists(atPath: package.path), FileManager.default.fileExists(atPath: vocabulary.path) else {
            throw XCTSkip("No recitation model at \(package.path): run `make recitation-model` to build it.")
        }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(RecitationModelStore.packageName), withDestinationURL: package)
        try FileManager.default.copyItem(at: vocabulary, to: directory.appendingPathComponent(RecitationModelStore.vocabularyName))
        let store = RecitationModelStore(directory: directory)

        let first = try await store.loadModel()
        XCTAssertEqual(first?.vocabulary.pieces.count, 1025)
        XCTAssertEqual(first?.vocabulary.blankID, 1024)
        let compiled = directory.appendingPathComponent(RecitationModelStore.compiledName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: compiled.path))

        // Without the package, the kept compiled model still loads.
        try FileManager.default.removeItem(at: directory.appendingPathComponent(RecitationModelStore.packageName))
        let second = try await store.loadModel()
        XCTAssertNotNil(second)
    }

    // MARK: Private

    /// `.cache/recitation-model` at the repository root (this file is Domain/RecitationRecognition/Tests/).
    private static let cachedModel = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/recitation-model")

    private var directory: URL!
}
