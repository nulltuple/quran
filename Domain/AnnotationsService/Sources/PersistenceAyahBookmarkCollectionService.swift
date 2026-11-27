//
//  PersistenceAyahBookmarkCollectionService.swift
//
//
//  Created by Claude Code on 2026-11-25.
//

#if !QURAN_SYNC
import CollectionPersistence
import Combine
import Foundation
import QuranAnnotations
import QuranKit
import Utilities

/// Verse collections on this device, without an account.
///
/// Builds without `QURAN_SYNC` get this type instead of the MobileSync one in
/// `AyahBookmarkCollectionService.swift`. Both have the same API and errors, so features use either one
/// unchanged.
public struct AyahBookmarkCollectionService {
    // MARK: Lifecycle

    public init(persistence: CollectionPersistence) {
        self.persistence = persistence
    }

    // MARK: Public

    /// Favorites. Every device uses this ID, so a later sync can match the copies.
    public static let defaultCollectionID = UUID(uuidString: "4D1F7A52-6E0B-4E43-9A0C-0F2B5A3C8E01")!
    /// The stored name of Favorites, the same in every locale. The app shows a localized name.
    public static let defaultCollectionName = "Favorites"
    public static let nameLengthLimit = AyahBookmarkCollection.nameLengthLimit

    /// - Throws: `ReservedCollectionNameError` when the name is reserved, `DuplicateCollectionNameError` when
    ///   another collection has the name, and `TextLengthLimitError` when the name is too short or too long.
    public func createCollection(named name: String) async throws {
        let name = try Self.validatedName(name)
        try await mapNameTaken {
            try await persistence.createCollection(id: UUID(), name: name, isDefault: false)
        }
    }

    public func addAyahBookmarkToCollection(collectionId: String, ayah: AyahNumber) async throws {
        try await addAyahs([ayah], toCollectionWithID: collectionId)
    }

    /// - Throws: `ReadOnlyCollectionError` when the collection can't be deleted.
    public func removeCollection(id: String) async throws {
        guard let uuid = try Self.editableCollectionID(id) else {
            return
        }
        try await persistence.removeCollection(id: uuid)
    }

    /// - Throws: `ReadOnlyCollectionError` when the collection can't be renamed, `ReservedCollectionNameError` when
    ///   the name is reserved, `DuplicateCollectionNameError` when another collection has the name, and
    ///   `TextLengthLimitError` when the name is too short or too long.
    public func renameCollection(id: String, to name: String) async throws {
        guard let uuid = try Self.editableCollectionID(id) else {
            return
        }
        let name = try Self.validatedName(name)
        try await mapNameTaken {
            try await persistence.renameCollection(id: uuid, to: name)
        }
    }

    public func removeBookmarkFromCollection(_ bookmark: AyahCollectionBookmark) async throws {
        try await removeAyahs([bookmark.ayah], fromCollectionWithID: bookmark.collectionID)
    }

    /// Adds the ayahs the collection doesn't have yet. Favorites is stored the first time it gets an ayah.
    public func addAyahs(_ ayahs: [AyahNumber], toCollectionWithID collectionID: String) async throws {
        guard !ayahs.isEmpty, let uuid = UUID(uuidString: collectionID) else {
            return
        }
        if uuid == Self.defaultCollectionID {
            try await storeDefaultCollectionIfNeeded()
        }
        try await persistence.addVerses(ayahs.map(CollectionVerseID.init), toCollectionWithID: uuid)
    }

    public func removeAyahs(_ ayahs: [AyahNumber], fromCollectionWithID collectionID: String) async throws {
        guard let uuid = UUID(uuidString: collectionID) else {
            return
        }
        try await persistence.removeVerses(Set(ayahs.map(CollectionVerseID.init)), fromCollectionWithID: uuid)
    }

    /// Removes every ayah from the collection, in one write, and keeps the collection, even Favorites.
    public func removeAllAyahs(fromCollectionWithID collectionID: String) async throws {
        guard let uuid = UUID(uuidString: collectionID) else {
            return
        }
        try await persistence.removeAllVerses(fromCollectionWithID: uuid)
    }

    /// Every collection, Favorites first even before it's stored, then the others oldest first. Ayahs that
    /// don't exist in `quran` are left out.
    public func collectionsSequence(quran: Quran) -> AnyAsyncSequence<[AyahBookmarkCollection]> {
        let sequence = persistence.collections()
            .map { collections in Self.collections(from: collections, quran: quran) }
            .values()
        return .init(sequence)
    }

    // MARK: Internal

    static func collections(from stored: [CollectionPersistenceModel], quran: Quran) -> [AyahBookmarkCollection] {
        let storedDefault = stored.first { $0.id == defaultCollectionID }
        let others = stored.filter { $0.id != defaultCollectionID }
        let favorites = AyahBookmarkCollection(
            id: defaultCollectionID.uuidString,
            name: defaultCollectionName,
            isDefault: true,
            isReadOnly: true,
            bookmarks: storedDefault.map { bookmarks(in: $0, quran: quran) } ?? []
        )
        return [favorites] + others.map { collection in
            AyahBookmarkCollection(
                id: collection.id.uuidString,
                name: collection.name,
                isDefault: false,
                isReadOnly: false,
                bookmarks: bookmarks(in: collection, quran: quran)
            )
        }
    }

    /// The trimmed name.
    static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < nameLengthLimit.lowerBound {
            throw TextLengthLimitError(field: .collectionName, bound: .tooShort, limit: nameLengthLimit.lowerBound)
        }
        if trimmed.count > nameLengthLimit.upperBound {
            throw TextLengthLimitError(field: .collectionName, bound: .tooLong, limit: nameLengthLimit.upperBound)
        }
        let isReserved = trimmed.caseInsensitiveCompare(defaultCollectionName) == .orderedSame
            || trimmed.lowercased().hasPrefix(reservedNamePrefix)
        if isReserved {
            throw ReservedCollectionNameError(name: trimmed)
        }
        return trimmed
    }

    // MARK: Private

    /// Quran.com reserves `system:` names, so a later import into a Quran.com account never conflicts.
    private static let reservedNamePrefix = "system:"

    private let persistence: CollectionPersistence

    /// - Returns: `nil` when the ID isn't a collection ID.
    /// - Throws: `ReadOnlyCollectionError` for Favorites.
    private static func editableCollectionID(_ id: String) throws -> UUID? {
        guard let uuid = UUID(uuidString: id) else {
            return nil
        }
        guard uuid != defaultCollectionID else {
            throw ReadOnlyCollectionError(collectionID: id)
        }
        return uuid
    }

    private static func bookmarks(in collection: CollectionPersistenceModel, quran: Quran) -> [AyahCollectionBookmark] {
        collection.verses.compactMap { stored in
            AyahNumber(quran: quran, sura: stored.verse.sura, ayah: stored.verse.ayah).map { ayah in
                AyahCollectionBookmark(id: stored.id.uuidString, collectionID: collection.id.uuidString, ayah: ayah)
            }
        }
    }

    private func storeDefaultCollectionIfNeeded() async throws {
        var iterator = persistence.collections().values().makeAsyncIterator()
        let stored = await iterator.next() ?? []
        guard !stored.contains(where: { $0.id == Self.defaultCollectionID }) else {
            return
        }
        do {
            try await persistence.createCollection(
                id: Self.defaultCollectionID,
                name: Self.defaultCollectionName,
                isDefault: true
            )
        } catch is CollectionNameTakenError {
            // Another add stored it first. Users can't take the name: it's reserved.
        }
    }

    private func mapNameTaken(_ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch let error as CollectionNameTakenError {
            throw DuplicateCollectionNameError(name: error.existingName)
        }
    }
}

private extension CollectionVerseID {
    init(_ ayah: AyahNumber) {
        self.init(sura: ayah.sura.suraNumber, ayah: ayah.ayah)
    }
}
#endif
