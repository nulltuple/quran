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

/// Practice sessions and recall evidence in the app's Core Data store (model `Quran 4`).
/// Records are only inserted or retracted; inserting a record whose id is stored does nothing.
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
            return try MemorizationHistory(
                sessions: context.fetch(sessions).compactMap(PracticeSessionRecord.init),
                evidence: context.fetch(evidence).compactMap(RecallEvidenceRecord.init)
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

    // MARK: Private

    private let context: NSManagedObjectContext

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
