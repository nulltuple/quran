//
//  CoreDataCollectionPersistence.swift
//
//
//  Created by Claude Code on 2026-11-25.
//

import Combine
import CoreData
import CoreDataModel
import CoreDataPersistence
import Foundation

public struct CoreDataCollectionPersistence: CollectionPersistence {
    // MARK: Lifecycle

    public init(stack: CoreDataStack, now: @escaping @Sendable () -> Date = Date.init) {
        context = stack.newBackgroundContext()
        self.now = now
    }

    // MARK: Public

    public func collections() -> AnyPublisher<[CollectionPersistenceModel], Never> {
        let request: NSFetchRequest<MO_Collection> = MO_Collection.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: Schema.Collection.createdOn, ascending: true)]
        // Every verse change also changes its collection's `modifiedOn`, so the fetch sees it.
        request.relationshipKeyPathsForPrefetching = [Schema.Collection.verses.rawValue]
        return CoreDataPublisher(request: request, context: context)
            .map { collections in collections.compactMap(CollectionPersistenceModel.init) }
            .eraseToAnyPublisher()
    }

    public func createCollection(id: UUID, name: String, isDefault: Bool) async throws {
        try await context.perform { [now] context in
            try Self.checkNameIsFree(name, exceptCollectionWithID: nil, in: context)
            let collection = MO_Collection(context: context)
            let date = now()
            collection.id = id
            collection.name = name
            collection.isDefault = isDefault
            collection.createdOn = date
            collection.modifiedOn = date
            try context.save(with: "createCollection")
        }
    }

    public func renameCollection(id: UUID, to name: String) async throws {
        try await context.perform { [now] context in
            guard let collection = try Self.collection(withID: id, in: context) else {
                return
            }
            try Self.checkNameIsFree(name, exceptCollectionWithID: id, in: context)
            collection.name = name
            collection.modifiedOn = now()
            try context.save(with: "renameCollection")
        }
    }

    public func removeCollection(id: UUID) async throws {
        try await context.perform { context in
            guard let collection = try Self.collection(withID: id, in: context) else {
                return
            }
            context.delete(collection)
            try context.save(with: "removeCollection")
        }
    }

    public func addVerses(_ verses: [CollectionVerseID], toCollectionWithID id: UUID) async throws {
        guard !verses.isEmpty else { return }
        try await context.perform { [now] context in
            guard let collection = try Self.collection(withID: id, in: context) else {
                return
            }
            var existingVerses = Set(collection.storedVerses.compactMap(\.verseID))
            let date = now()
            for verse in verses where existingVerses.insert(verse).inserted {
                let stored = MO_CollectionVerse(context: context)
                stored.id = UUID()
                stored.sura = Int32(verse.sura)
                stored.ayah = Int32(verse.ayah)
                stored.createdOn = date
                stored.collection = collection
            }
            if context.hasChanges {
                collection.modifiedOn = date
            }
            try context.save(with: "addVersesToCollection")
        }
    }

    public func removeVerses(_ verses: Set<CollectionVerseID>, fromCollectionWithID id: UUID) async throws {
        guard !verses.isEmpty else { return }
        try await removeVerses(fromCollectionWithID: id, operation: "removeVersesFromCollection") { stored in
            stored.verseID.map(verses.contains) ?? false
        }
    }

    public func removeAllVerses(fromCollectionWithID id: UUID) async throws {
        try await removeVerses(fromCollectionWithID: id, operation: "removeAllVersesFromCollection") { _ in true }
    }

    // MARK: Private

    private let context: NSManagedObjectContext
    private let now: @Sendable () -> Date

    private static func collection(withID id: UUID, in context: NSManagedObjectContext) throws -> MO_Collection? {
        let request: NSFetchRequest<MO_Collection> = MO_Collection.fetchRequest()
        request.predicate = NSPredicate(equals: (Schema.Collection.id, id as NSUUID))
        request.sortDescriptors = [NSSortDescriptor(key: Schema.Collection.createdOn, ascending: true)]
        return try context.fetch(request).first
    }

    private static func checkNameIsFree(
        _ name: String,
        exceptCollectionWithID id: UUID?,
        in context: NSManagedObjectContext
    ) throws {
        let request: NSFetchRequest<MO_Collection> = MO_Collection.fetchRequest()
        let key = normalizedName(name)
        let taken = try context.fetch(request).first { collection in
            collection.id != id && normalizedName(collection.name ?? "") == key
        }
        if let taken {
            throw CollectionNameTakenError(existingName: taken.name ?? "")
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func removeVerses(
        fromCollectionWithID id: UUID,
        operation: String,
        where shouldRemove: @escaping @Sendable (MO_CollectionVerse) -> Bool
    ) async throws {
        try await context.perform { [now] context in
            guard let collection = try Self.collection(withID: id, in: context) else {
                return
            }
            for stored in collection.storedVerses where shouldRemove(stored) {
                context.delete(stored)
            }
            if context.hasChanges {
                collection.modifiedOn = now()
            }
            try context.save(with: operation)
        }
    }
}

private extension MO_Collection {
    var storedVerses: [MO_CollectionVerse] {
        (verses as? Set<MO_CollectionVerse>).map(Array.init) ?? []
    }
}

private extension MO_CollectionVerse {
    var verseID: CollectionVerseID? {
        guard sura > 0, ayah > 0 else {
            return nil
        }
        return CollectionVerseID(sura: Int(sura), ayah: Int(ayah))
    }
}

private extension CollectionPersistenceModel {
    init?(_ other: MO_Collection) {
        guard let id = other.id else {
            return nil
        }
        let verses = other.storedVerses
            .compactMap { stored -> CollectionVersePersistenceModel? in
                guard let verseID = stored.id, let verse = stored.verseID else {
                    return nil
                }
                return CollectionVersePersistenceModel(
                    id: verseID,
                    verse: verse,
                    createdOn: stored.createdOn ?? .distantPast
                )
            }
            .sorted { ($0.createdOn, $0.verse.sura, $0.verse.ayah) < ($1.createdOn, $1.verse.sura, $1.verse.ayah) }
        self.init(
            id: id,
            name: other.name ?? "",
            isDefault: other.isDefault,
            createdOn: other.createdOn ?? .distantPast,
            modifiedOn: other.modifiedOn ?? other.createdOn ?? .distantPast,
            verses: verses
        )
    }
}
