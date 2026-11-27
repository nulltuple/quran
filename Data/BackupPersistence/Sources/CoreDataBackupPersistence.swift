//
//  CoreDataBackupPersistence.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import CoreData
import CoreDataModel
import CoreDataPersistence
import Foundation
import MemorizationPersistence

/// Reads every user-authored record in the Core Data store, and restores a snapshot into it.
///
/// A restore runs in one background context and ends in a single save, so the store either gets the whole
/// restore or, if anything throws, none of it. Restores never go through the note, bookmark and collection
/// persistences, whose writes each save on their own.
///
/// `CoreDataStack` is not `Sendable`, but this type only loads the store through its lock and uses a new
/// background context per call, touched only inside `perform`.
public struct CoreDataBackupPersistence: @unchecked Sendable {
    // MARK: Lifecycle

    public init(stack: CoreDataStack) {
        self.stack = stack
    }

    // MARK: Public

    /// Dates within this interval count as equal: the backup file keeps milliseconds, the store more.
    public static let dateTolerance: TimeInterval = 0.001

    /// Every note, page bookmark, recent page and collection, in a stable order.
    public func snapshot() async throws -> BackupSnapshot {
        let context = try stack.openBackgroundContext()
        return try await context.perform { context in
            try context.setQueryGenerationFrom(.current)
            defer { context.reset() }
            return try BackupSnapshot(
                notes: fetchAll(MO_Note.self, in: context).compactMap(BackupNote.init).sorted { $0.verses.lexicographicallyPrecedes($1.verses) },
                pageBookmarks: newestPerPage(fetchAll(MO_PageBookmark.self, in: context).compactMap(BackupPage.init(bookmark:)))
                    .sorted { ($0.mushafID, $0.page) < ($1.mushafID, $1.page) },
                recentPages: newestPerPage(fetchAll(MO_LastPage.self, in: context).compactMap(BackupPage.init(lastPage:)))
                    .sorted { $0.modifiedOn > $1.modifiedOn },
                collections: fetchAll(MO_Collection.self, in: context).compactMap(BackupCollection.init)
                    .sorted { ($0.createdOn, $0.id.uuidString) < ($1.createdOn, $1.id.uuidString) },
                practiceSessions: fetchAll(MO_PracticeSession.self, in: context).compactMap(PracticeSessionRecord.init)
                    .sorted { ($0.startedOn, $0.id.uuidString) < ($1.startedOn, $1.id.uuidString) },
                recallEvidence: fetchAll(MO_RecallEvidence.self, in: context).compactMap(RecallEvidenceRecord.init)
                    .sorted { ($0.recordedOn, $0.id.uuidString) < ($1.recordedOn, $1.id.uuidString) },
                memorizedRanges: fetchAll(MO_MemorizedRange.self, in: context).compactMap(MemorizedRangeRecord.init)
                    .sorted { ($0.declaredOn, $0.id.uuidString) < ($1.declaredOn, $1.id.uuidString) },
                passages: fetchAll(MO_Passage.self, in: context).compactMap(PassageRecord.init)
                    .sorted { ($0.createdOn, $0.id.uuidString) < ($1.createdOn, $1.id.uuidString) }
            )
        }
    }

    /// Restores `snapshot`; see ``BackupRestoreMode``. Throws, leaving the store unchanged, if the save fails.
    public func restore(_ snapshot: BackupSnapshot, mode: BackupRestoreMode) async throws {
        let context = try stack.openBackgroundContext()
        try await context.perform { context in
            do {
                if mode == .replace {
                    try deleteAll(in: context)
                }
                var restorer = try Restorer(context: context)
                snapshot.notes.forEach { restorer.merge($0) }
                snapshot.pageBookmarks.forEach { restorer.mergePageBookmark($0) }
                snapshot.recentPages.forEach { restorer.mergeRecentPage($0) }
                snapshot.collections.forEach { restorer.merge($0) }
                snapshot.practiceSessions.forEach { restorer.merge($0) }
                snapshot.recallEvidence.forEach { restorer.merge($0) }
                snapshot.memorizedRanges.forEach { restorer.merge($0) }
                snapshot.passages.forEach { restorer.merge($0) }
                try context.save(with: "restoreBackup")
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    // MARK: Private

    private let stack: CoreDataStack
}

// MARK: - Restoring

/// Applies backup records to the objects in one context, keeping indexes of what is there.
private struct Restorer {
    // MARK: Lifecycle

    init(context: NSManagedObjectContext) throws {
        self.context = context
        for note in try fetchAll(MO_Note.self, in: context) {
            for verse in note.backupVerses {
                notesByVerse[verse] = note
            }
        }
        for bookmark in try fetchAll(MO_PageBookmark.self, in: context) {
            pageBookmarks[PageKey(mushafID: Int(bookmark.mushafID), page: Int(bookmark.page))] = bookmark
        }
        for lastPage in try fetchAll(MO_LastPage.self, in: context) {
            lastPages[PageKey(mushafID: Int(lastPage.mushafID), page: Int(lastPage.page))] = lastPage
        }
        for collection in try fetchAll(MO_Collection.self, in: context) {
            collections.append(collection)
        }
        for session in try fetchAll(MO_PracticeSession.self, in: context) {
            if let id = session.id {
                practiceSessionIDs.insert(id)
            }
        }
        for evidence in try fetchAll(MO_RecallEvidence.self, in: context) {
            if let id = evidence.id {
                recallEvidence[id] = evidence
            }
        }
        for range in try fetchAll(MO_MemorizedRange.self, in: context) {
            if let id = range.id {
                memorizedRanges[id] = range
            }
        }
        for passage in try fetchAll(MO_Passage.self, in: context) {
            if let id = passage.id {
                passages[id] = passage
            }
        }
    }

    // MARK: Learning records

    /// A session is added unless its id is stored; sessions never change.
    mutating func merge(_ session: PracticeSessionRecord) {
        guard practiceSessionIDs.insert(session.id).inserted else {
            return
        }
        session.write(to: MO_PracticeSession(context: context))
    }

    /// Evidence is added unless its id is stored; a retraction in the backup retracts the stored record.
    mutating func merge(_ evidence: RecallEvidenceRecord) {
        if let stored = recallEvidence[evidence.id] {
            if stored.retractedOn == nil, let retractedOn = evidence.retractedOn {
                stored.retractedOn = retractedOn
            }
            return
        }
        let stored = MO_RecallEvidence(context: context)
        evidence.write(to: stored)
        recallEvidence[evidence.id] = stored
    }

    /// A declared range is added unless its id is stored; a removal tombstone carries over.
    mutating func merge(_ range: MemorizedRangeRecord) {
        if let stored = memorizedRanges[range.id] {
            if stored.removedOn == nil, let removedOn = range.removedOn {
                stored.removedOn = removedOn
            }
            return
        }
        let stored = MO_MemorizedRange(context: context)
        range.write(to: stored)
        memorizedRanges[range.id] = stored
    }

    /// A passage is added unless its id is stored; newer edits update bounds/snooze and removals carry over.
    mutating func merge(_ passage: PassageRecord) {
        if let stored = passages[passage.id] {
            let storedModified = stored.modifiedOn ?? stored.createdOn ?? .distantPast
            if isLater(passage.modifiedOn, than: storedModified) {
                assign(\.firstSura, Int32(passage.first.sura), to: stored)
                assign(\.firstAyah, Int32(passage.first.ayah), to: stored)
                assign(\.lastSura, Int32(passage.last.sura), to: stored)
                assign(\.lastAyah, Int32(passage.last.ayah), to: stored)
                if let snoozed = passage.snoozedUntil {
                    assignDate(\.snoozedUntil, snoozed, to: stored)
                } else if stored.snoozedUntil != nil {
                    stored.snoozedUntil = nil
                }
                assignDate(\.modifiedOn, passage.modifiedOn, to: stored)
            }
            if stored.removedOn == nil, let removedOn = passage.removedOn {
                stored.removedOn = removedOn
            }
            return
        }
        let stored = MO_Passage(context: context)
        passage.write(to: stored)
        passages[passage.id] = stored
    }

    // MARK: Internal

    // MARK: Notes

    /// A note whose verses are free is added. A note with the same verses as a stored one updates it if
    /// it is newer. A note overlapping stored notes joins them into one note, as the note editor does,
    /// keeping each distinct text once.
    mutating func merge(_ note: BackupNote) {
        let existing = Set(note.verses.compactMap { notesByVerse[$0] })
            .sorted { ($0.createdOn ?? .distantPast) < ($1.createdOn ?? .distantPast) }
        guard let kept = existing.first else {
            insert(note)
            return
        }

        let existingVerses = Set(existing.flatMap(\.backupVerses))
        let allVerses = existingVerses.union(note.verses)
        let storedModified = existing.compactMap(\.modifiedOn).max() ?? .distantPast
        let backupIsNewer = isLater(note.modifiedOn, than: storedModified)

        let text: String
        if existing.count == 1, existingVerses == Set(note.verses) {
            // The same note: the newer text wins, unless it is blank.
            let storedText = kept.note ?? ""
            let newerText = backupIsNewer ? note.text ?? "" : storedText
            let olderText = backupIsNewer ? storedText : note.text ?? ""
            text = isBlank(newerText) ? olderText : newerText
        } else {
            text = joinedDistinctTexts(existing.map { $0.note ?? "" } + [note.text ?? ""])
        }

        for other in existing.dropFirst() {
            for verse in other.typedVerses {
                context.delete(verse)
            }
            context.delete(other)
        }
        if existingVerses != allVerses || existing.count > 1 {
            for verse in kept.typedVerses {
                context.delete(verse)
            }
            for verse in allVerses {
                let stored = MO_Verse(context: context)
                stored.sura = Int32(verse.sura)
                stored.ayah = Int32(verse.ayah)
                stored.note = kept
            }
        }
        for verse in allVerses {
            notesByVerse[verse] = kept
        }

        assignText(\.note, text, to: kept)
        if backupIsNewer {
            assign(\.color, Int32(note.color), to: kept)
        }
        assignDate(\.modifiedOn, latest(storedModified, note.modifiedOn), to: kept)
        assignDate(\.createdOn, earliest(kept.createdOn, note.createdOn), to: kept)
    }

    // MARK: Pages

    mutating func mergePageBookmark(_ page: BackupPage) {
        let key = PageKey(mushafID: page.mushafID, page: page.page)
        if let stored = pageBookmarks[key] {
            assignDate(\.modifiedOn, latest(stored.modifiedOn ?? .distantPast, page.modifiedOn), to: stored)
            assignDate(\.createdOn, earliest(stored.createdOn, page.createdOn), to: stored)
        } else {
            let stored = MO_PageBookmark(context: context)
            stored.mushafID = Int16(page.mushafID)
            stored.page = Int32(page.page)
            stored.createdOn = page.createdOn
            stored.modifiedOn = page.modifiedOn
            pageBookmarks[key] = stored
        }
    }

    /// The store keeps the 10 newest recent pages; its uniquifier trims the rest after the save.
    mutating func mergeRecentPage(_ page: BackupPage) {
        let key = PageKey(mushafID: page.mushafID, page: page.page)
        if let stored = lastPages[key] {
            assignDate(\.modifiedOn, latest(stored.modifiedOn ?? .distantPast, page.modifiedOn), to: stored)
            assignDate(\.createdOn, earliest(stored.createdOn, page.createdOn), to: stored)
        } else {
            let stored = MO_LastPage(context: context)
            stored.mushafID = Int16(page.mushafID)
            stored.page = Int32(page.page)
            stored.createdOn = page.createdOn
            stored.modifiedOn = page.modifiedOn
            lastPages[key] = stored
        }
    }

    // MARK: Collections

    /// A collection matches a stored one by ID, then by name (trimmed, case-insensitive), so a backup from
    /// another device does not create a second collection with the same name. Verses are added, never
    /// removed. A newer backup renames a stored collection if the name is free; Favorites keeps its name.
    mutating func merge(_ collection: BackupCollection) {
        let stored = collections.first { $0.id == collection.id }
            ?? collections.first { collectionNameKey($0.name ?? "") == collectionNameKey(collection.name) }
        guard let stored else {
            insert(collection)
            return
        }

        let storedModified = stored.modifiedOn ?? .distantPast
        if isLater(collection.modifiedOn, than: storedModified), !stored.isDefault, stored.name != collection.name {
            let nameIsFree = !collections.contains {
                $0 !== stored && collectionNameKey($0.name ?? "") == collectionNameKey(collection.name)
            }
            if nameIsFree {
                stored.name = collection.name
            }
        }

        var storedVerses = Set(stored.typedVerses.map(\.backupVerse))
        for verse in collection.verses where storedVerses.insert(verse.verse).inserted {
            insertVerse(verse, into: stored)
        }
        assignDate(\.modifiedOn, latest(storedModified, collection.modifiedOn), to: stored)
        assignDate(\.createdOn, earliest(stored.createdOn, collection.createdOn), to: stored)
    }

    // MARK: Private

    private struct PageKey: Hashable {
        let mushafID: Int
        let page: Int
    }

    private let context: NSManagedObjectContext
    private var notesByVerse: [BackupVerse: MO_Note] = [:]
    private var pageBookmarks: [PageKey: MO_PageBookmark] = [:]
    private var lastPages: [PageKey: MO_LastPage] = [:]
    private var collections: [MO_Collection] = []
    private var practiceSessionIDs: Set<UUID> = []
    private var recallEvidence: [UUID: MO_RecallEvidence] = [:]
    private var memorizedRanges: [UUID: MO_MemorizedRange] = [:]
    private var passages: [UUID: MO_Passage] = [:]

    private mutating func insert(_ note: BackupNote) {
        let stored = MO_Note(context: context)
        stored.note = note.text
        stored.color = Int32(note.color)
        stored.createdOn = note.createdOn
        stored.modifiedOn = note.modifiedOn
        for verse in Set(note.verses) {
            let storedVerse = MO_Verse(context: context)
            storedVerse.sura = Int32(verse.sura)
            storedVerse.ayah = Int32(verse.ayah)
            storedVerse.note = stored
            notesByVerse[verse] = stored
        }
    }

    private mutating func insert(_ collection: BackupCollection) {
        let stored = MO_Collection(context: context)
        stored.id = collection.id
        stored.name = collection.name
        stored.isDefault = collection.isDefault
        stored.createdOn = collection.createdOn
        stored.modifiedOn = collection.modifiedOn
        var verses = Set<BackupVerse>()
        for verse in collection.verses where verses.insert(verse.verse).inserted {
            insertVerse(verse, into: stored)
        }
        collections.append(stored)
    }

    private func insertVerse(_ verse: BackupCollectionVerse, into collection: MO_Collection) {
        let stored = MO_CollectionVerse(context: context)
        stored.id = UUID()
        stored.sura = Int32(verse.sura)
        stored.ayah = Int32(verse.ayah)
        stored.createdOn = verse.createdOn
        stored.collection = collection
    }

    /// Assigns only a different value, so restoring the same backup again leaves nothing to save.
    private func assign<Object: NSManagedObject, Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<Object, Value>,
        _ value: Value,
        to object: Object
    ) {
        if object[keyPath: keyPath] != value {
            object[keyPath: keyPath] = value
        }
    }

    private func assignDate<Object: NSManagedObject>(
        _ keyPath: ReferenceWritableKeyPath<Object, Date?>,
        _ value: Date,
        to object: Object
    ) {
        if let current = object[keyPath: keyPath], abs(current.timeIntervalSince(value)) <= CoreDataBackupPersistence.dateTolerance {
            return
        }
        object[keyPath: keyPath] = value
    }

    private func assignText<Object: NSManagedObject>(
        _ keyPath: ReferenceWritableKeyPath<Object, String?>,
        _ value: String,
        to object: Object
    ) {
        if (object[keyPath: keyPath] ?? "") != value {
            object[keyPath: keyPath] = value
        }
    }
}

/// Every distinct, non-blank text once, in order; a text already contained in an earlier one is skipped,
/// so joining the same backup note into a joined note again changes nothing.
func joinedDistinctTexts(_ texts: [String]) -> String {
    var kept: [String] = []
    for text in texts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !text.isEmpty {
        if !kept.contains(where: { $0.contains(text) }) {
            kept.append(text)
        }
    }
    return kept.joined(separator: "\n\n")
}

/// The key two collection names collide on: trimmed and case-insensitive, as the collection service checks.
func collectionNameKey(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func isBlank(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func isLater(_ date: Date, than other: Date) -> Bool {
    date.timeIntervalSince(other) > CoreDataBackupPersistence.dateTolerance
}

private func latest(_ lhs: Date, _ rhs: Date) -> Date {
    isLater(rhs, than: lhs) ? rhs : lhs
}

private func earliest(_ stored: Date?, _ backup: Date) -> Date {
    guard let stored else {
        return backup
    }
    return isLater(stored, than: backup) ? backup : stored
}

// MARK: - Fetching

private func fetchAll<Object: NSManagedObject>(_ type: Object.Type, in context: NSManagedObjectContext) throws -> [Object] {
    let request = NSFetchRequest<Object>(entityName: String(describing: type))
    return try context.fetch(request)
}

private func deleteAll(in context: NSManagedObjectContext) throws {
    // Notes nullify their verses, so verses are deleted explicitly; collections cascade to theirs.
    let objects: [NSManagedObject] = try fetchAll(MO_Verse.self, in: context)
        + fetchAll(MO_Note.self, in: context)
        + fetchAll(MO_PageBookmark.self, in: context)
        + fetchAll(MO_LastPage.self, in: context)
        + fetchAll(MO_Collection.self, in: context)
        + fetchAll(MO_PracticeSession.self, in: context)
        + fetchAll(MO_RecallEvidence.self, in: context)
        + fetchAll(MO_MemorizedRange.self, in: context)
        + fetchAll(MO_Passage.self, in: context)
    objects.forEach(context.delete)
}

private func newestPerPage(_ pages: [BackupPage]) -> [BackupPage] {
    var newest: [String: BackupPage] = [:]
    for page in pages {
        let key = "\(page.mushafID)-\(page.page)"
        if let current = newest[key], current.modifiedOn >= page.modifiedOn {
            continue
        }
        newest[key] = page
    }
    return Array(newest.values)
}

// MARK: - Mapping

/// Stable dates for a record: modification falls back to creation, then to the Unix epoch; creation to modification.
private func recordDates(created: Date?, modified: Date?) -> (created: Date, modified: Date) {
    let modified = modified ?? created ?? Date(timeIntervalSince1970: 0)
    return (created ?? modified, modified)
}

private extension BackupNote {
    init?(_ note: MO_Note) {
        let verses = note.backupVerses
        // A note without verses is not shown anywhere.
        guard !verses.isEmpty else {
            return nil
        }
        let dates = recordDates(created: note.createdOn, modified: note.modifiedOn)
        self.init(
            verses: verses.sorted(),
            text: note.note,
            color: Int(note.color),
            createdOn: dates.created,
            modifiedOn: dates.modified
        )
    }
}

private extension BackupPage {
    init(bookmark: MO_PageBookmark) {
        let dates = recordDates(created: bookmark.createdOn, modified: bookmark.modifiedOn)
        self.init(mushafID: Int(bookmark.mushafID), page: Int(bookmark.page), createdOn: dates.created, modifiedOn: dates.modified)
    }

    init(lastPage: MO_LastPage) {
        let dates = recordDates(created: lastPage.createdOn, modified: lastPage.modifiedOn)
        self.init(mushafID: Int(lastPage.mushafID), page: Int(lastPage.page), createdOn: dates.created, modifiedOn: dates.modified)
    }
}

private extension BackupCollection {
    init?(_ collection: MO_Collection) {
        guard let id = collection.id else {
            return nil
        }
        let dates = recordDates(created: collection.createdOn, modified: collection.modifiedOn)
        var seen = Set<BackupVerse>()
        let verses = collection.typedVerses
            .sorted { ($0.createdOn ?? .distantPast, $0.sura, $0.ayah) < ($1.createdOn ?? .distantPast, $1.sura, $1.ayah) }
            .filter { seen.insert($0.backupVerse).inserted }
            .map { BackupCollectionVerse(verse: $0.backupVerse, createdOn: $0.createdOn ?? dates.created) }
        self.init(
            id: id,
            name: collection.name ?? "",
            isDefault: collection.isDefault,
            createdOn: dates.created,
            modifiedOn: dates.modified,
            verses: verses
        )
    }
}

private extension MO_Note {
    var typedVerses: Set<MO_Verse> {
        verses as? Set<MO_Verse> ?? []
    }

    var backupVerses: Set<BackupVerse> {
        Set(typedVerses.map { BackupVerse(sura: Int($0.sura), ayah: Int($0.ayah)) })
    }
}

private extension MO_Collection {
    var typedVerses: Set<MO_CollectionVerse> {
        verses as? Set<MO_CollectionVerse> ?? []
    }
}

private extension MO_CollectionVerse {
    var backupVerse: BackupVerse {
        BackupVerse(sura: Int(sura), ayah: Int(ayah))
    }
}
