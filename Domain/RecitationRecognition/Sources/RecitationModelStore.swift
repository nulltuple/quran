//
//  RecitationModelStore.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import CoreML
import Foundation

/// The recitation model installed on this device: `TilawiFastConformerInt8.mlpackage` (from
/// `make recitation-model`) and its `vocab.json` in one directory. The package is compiled on first
/// load and the compiled model kept beside it, so later loads skip the compile. The files come from
/// the published archive (`RecitationModelDownloader`, owner decision D7) or a developer's copy.
public struct RecitationModelStore: Sendable {
    public struct LoadedModel: Sendable {
        public let acousticModel: CoreMLRecitationModel
        public let vocabulary: CTCVocabulary
    }

    // MARK: Lifecycle

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: Public

    /// Where the app installs the model: `Application Support/RecitationModel`.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("RecitationModel", isDirectory: true)
    }

    public static let packageName = "TilawiFastConformerInt8.mlpackage"
    public static let compiledName = "TilawiFastConformerInt8.mlmodelc"
    public static let vocabularyName = "vocab.json"
    /// The Tilawi model's CTC blank: the last of its 1,025 tokens.
    public static let blankID = 1024

    public let directory: URL

    /// The installed model, compiling the package the first time; nil when it is not installed.
    public func loadModel(computeUnits: MLComputeUnits = .all) async throws -> LoadedModel? {
        let fileManager = FileManager.default
        let vocabularyURL = directory.appendingPathComponent(Self.vocabularyName)
        let compiledURL = directory.appendingPathComponent(Self.compiledName)
        let packageURL = directory.appendingPathComponent(Self.packageName)
        guard fileManager.fileExists(atPath: vocabularyURL.path) else {
            return nil
        }
        if !fileManager.fileExists(atPath: compiledURL.path) {
            guard fileManager.fileExists(atPath: packageURL.path) else {
                return nil
            }
            let temporary = try await MLModel.compileModel(at: packageURL)
            try fileManager.moveItem(at: temporary, to: compiledURL)
        }
        let vocabulary = try CTCVocabulary(jsonData: Data(contentsOf: vocabularyURL), blankID: Self.blankID)
        let model = try CoreMLRecitationModel(compiledModelURL: compiledURL, computeUnits: computeUnits)
        return LoadedModel(acousticModel: model, vocabulary: vocabulary)
    }
}
