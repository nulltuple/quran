//
//  CollectionPersistenceModel.swift
//
//
//  Created by Claude Code on 2026-11-25.
//

import Foundation

public struct CollectionPersistenceModel: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        name: String,
        isDefault: Bool,
        createdOn: Date,
        modifiedOn: Date,
        verses: [CollectionVersePersistenceModel]
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
    public let isDefault: Bool
    public let createdOn: Date
    /// Changes when the collection is renamed or its verses change.
    public let modifiedOn: Date
    public let verses: [CollectionVersePersistenceModel]
}

public struct CollectionVersePersistenceModel: Equatable, Sendable {
    // MARK: Lifecycle

    public init(id: UUID, verse: CollectionVerseID, createdOn: Date) {
        self.id = id
        self.verse = verse
        self.createdOn = createdOn
    }

    // MARK: Public

    public let id: UUID
    public let verse: CollectionVerseID
    public let createdOn: Date
}

/// A verse by sura and ayah number, independent of any mushaf layout.
public struct CollectionVerseID: Hashable, Sendable {
    // MARK: Lifecycle

    public init(sura: Int, ayah: Int) {
        self.sura = sura
        self.ayah = ayah
    }

    // MARK: Public

    public let sura: Int
    public let ayah: Int
}
