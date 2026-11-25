//
//  CollectionPersistence.swift
//
//
//  Created by Claude Code on 2026-11-25.
//

import Combine
import Foundation

/// Verse collections stored on this device, such as Favorites or a user's "Duas" collection.
///
/// Verses are identified by sura and ayah only, so a collection is the same in every mushaf layout.
public protocol CollectionPersistence {
    /// Every collection with its verses, collections oldest first and verses in the order they were added.
    func collections() -> AnyPublisher<[CollectionPersistenceModel], Never>

    /// - Throws: `CollectionNameTakenError` when another collection has the name, compared trimmed and
    ///   case-insensitively.
    func createCollection(id: UUID, name: String, isDefault: Bool) async throws

    /// Does nothing when no collection has the ID.
    ///
    /// - Throws: `CollectionNameTakenError` when another collection has the name.
    func renameCollection(id: UUID, to name: String) async throws

    /// Removes the collection and its verses. Does nothing when no collection has the ID.
    func removeCollection(id: UUID) async throws

    /// Adds the verses the collection doesn't have yet, once each. Does nothing when no collection has the ID.
    func addVerses(_ verses: [CollectionVerseID], toCollectionWithID id: UUID) async throws

    func removeVerses(_ verses: Set<CollectionVerseID>, fromCollectionWithID id: UUID) async throws

    func removeAllVerses(fromCollectionWithID id: UUID) async throws
}

/// Creating or renaming a collection with a name another collection has.
public struct CollectionNameTakenError: Error, Equatable, Sendable {
    // MARK: Lifecycle

    public init(existingName: String) {
        self.existingName = existingName
    }

    // MARK: Public

    /// The other collection's name, which can differ from the requested name in case or surrounding spaces.
    public let existingName: String
}
