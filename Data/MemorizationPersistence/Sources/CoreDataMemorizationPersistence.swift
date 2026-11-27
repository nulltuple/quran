//
//  CoreDataMemorizationPersistence.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import CoreData
import CoreDataModel
import CoreDataPersistence
import Foundation

/// Practice sessions, recall evidence, declared ranges, and passages in the app's Core Data store (model `Quran 5`).
/// Records are only inserted, updated monotonically, or tombstoned; inserting a session/evidence/range whose id is stored does nothing.
public struct CoreDataMemorizationPersistence {
    // MARK: Lifecycle

    public init(stack: CoreDataStack) {
        context = stack.newBackgroundContext()
    }

    // MARK: Public

    public func history() async throws -> MemorizationHistory {
        try await context.perform { context in
            let sessions: NSFetchRequest<MO_PracticeSession> = MO_PracticeSession.fetchRequest()
            sessions.sortDescriptors = [NSSortDescriptor(key: Schema.PracticeSession.startedOn, ascending: true)]
            let evidence: NSFetchRequest<MO_RecallEvidence> = MO_RecallEvidence.fetchRequest()
            evidence.sortDescriptors = [NSSortDescriptor(key: Schema.RecallEvidence.recordedOn, ascending: true)]
            let ranges: NSFetchRequest<MO_MemorizedRange> = MO_MemorizedRange.fetchRequest()
            ranges.sortDescriptors = [NSSortDescriptor(key: Schema.MemorizedRange.declaredOn, ascending: true)]
            let passages: NSFetchRequest<MO_Passage> = MO_Passage.fetchRequest()
            passages.sortDescriptors = [NSSortDescriptor(key: Schema.Passage.createdOn, ascending: true)]
            return try MemorizationHistory(
                sessions: context.fetch(sessions).compactMap(PracticeSessionRecord.init),
                evidence: context.fetch(evidence).compactMap(RecallEvidenceRecord.init),
                declaredRanges: context.fetch(ranges).compactMap(MemorizedRangeRecord.init),
                passages: context.fetch(passages).compactMap(PassageRecord.init)
            )
        }
    }

    /// Stores a finished session with its evidence in one save.
    public func record(_ session: PracticeSessionRecord, evidence: [RecallEvidenceRecord]) async throws {
        try await context.perform { context in
            if try Self.storedIDs(MO_PracticeSession.fetchRequest(), ids: [session.id], in: context).isEmpty {
                session.write(to: MO_PracticeSession(context: context))
            }
            let stored = try Self.storedIDs(MO_RecallEvidence.fetchRequest(), ids: evidence.map(\.id), in: context)
            for record in evidence where !stored.contains(record.id) {
                record.write(to: MO_RecallEvidence(context: context))
            }
            if context.hasChanges {
                try context.save(with: "recordPracticeSession")
            }
        }
    }

    /// Marks evidence as disputed or mistaken; it stays stored but no longer counts.
    public func retractEvidence(withIDs ids: Set<UUID>, on date: Date) async throws {
        guard !ids.isEmpty else { return }
        try await context.perform { context in
            let request: NSFetchRequest<MO_RecallEvidence> = MO_RecallEvidence.fetchRequest()
            request.predicate = NSPredicate(format: "%K IN %@", Schema.RecallEvidence.id.rawValue, ids.map { $0 as NSUUID })
            for record in try context.fetch(request) where record.retractedOn == nil {
                record.retractedOn = date
            }
            if context.hasChanges {
                try context.save(with: "retractRecallEvidence")
            }
        }
    }

    /// Stores a declared memorized range and any generated passages in one save.
    public func saveDeclaredRange(_ range: MemorizedRangeRecord, passages: [PassageRecord] = []) async throws {
        try await context.perform { context in
            if try Self.storedIDs(MO_MemorizedRange.fetchRequest(), ids: [range.id], in: context).isEmpty {
                range.write(to: MO_MemorizedRange(context: context))
            }
            try Self.upsert(passages: passages, in: context)
            if context.hasChanges {
                try context.save(with: "saveMemorizedRange")
            }
        }
    }

    /// Tombstones declared ranges and optionally tombstones associated passages in one save.
    public func removeDeclaredRanges(withIDs rangeIDs: Set<UUID>, removingPassageIDs passageIDs: Set<UUID> = [], on date: Date) async throws {
        guard !rangeIDs.isEmpty || !passageIDs.isEmpty else { return }
        try await context.perform { context in
            if !rangeIDs.isEmpty {
                let request: NSFetchRequest<MO_MemorizedRange> = MO_MemorizedRange.fetchRequest()
                request.predicate = NSPredicate(format: "%K IN %@", Schema.MemorizedRange.id.rawValue, rangeIDs.map { $0 as NSUUID })
                for record in try context.fetch(request) where record.removedOn == nil {
                    record.removedOn = date
                }
            }
            if !passageIDs.isEmpty {
                let request: NSFetchRequest<MO_Passage> = MO_Passage.fetchRequest()
                request.predicate = NSPredicate(format: "%K IN %@", Schema.Passage.id.rawValue, passageIDs.map { $0 as NSUUID })
                for record in try context.fetch(request) where record.removedOn == nil {
                    record.removedOn = date
                    record.modifiedOn = date
                }
            }
            if context.hasChanges {
                try context.save(with: "removeMemorizedRanges")
            }
        }
    }

    /// Inserts or updates passages in one save.
    public func savePassages(_ passages: [PassageRecord]) async throws {
        guard !passages.isEmpty else { return }
        try await context.perform { context in
            try Self.upsert(passages: passages, in: context)
            if context.hasChanges {
                try context.save(with: "savePassages")
            }
        }
    }

    // MARK: Private

    private let context: NSManagedObjectContext

    private static func upsert(passages: [PassageRecord], in context: NSManagedObjectContext) throws {
        guard !passages.isEmpty else { return }
        let request: NSFetchRequest<MO_Passage> = MO_Passage.fetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@", Schema.Passage.id.rawValue, passages.map { $0.id as NSUUID })
        var existingByID: [UUID: MO_Passage] = [:]
        for stored in try context.fetch(request) {
            if let id = stored.id {
                existingByID[id] = stored
            }
        }
        for passage in passages {
            if let stored = existingByID[passage.id] {
                passage.write(to: stored)
            } else {
                let stored = MO_Passage(context: context)
                passage.write(to: stored)
                existingByID[passage.id] = stored
            }
        }
    }

    private static func storedIDs(
        _ request: NSFetchRequest<some NSManagedObject>,
        ids: [UUID],
        in context: NSManagedObjectContext
    ) throws -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        request.predicate = NSPredicate(format: "id IN %@", ids.map { $0 as NSUUID })
        return Set(try context.fetch(request).compactMap { $0.value(forKey: "id") as? UUID })
    }
}
