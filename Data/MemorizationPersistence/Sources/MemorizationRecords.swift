//
//  MemorizationRecords.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import CoreDataModel
import Foundation

/// How well a word or ayah was recalled in practice (roadmap H1). Stored as its raw value: never
/// renumber a case, only add new ones.
public enum RecallOutcome: Int, Codable, Hashable, Sendable, CaseIterable {
    case correct = 0
    case mistake = 1
    case hint = 2
    case revealed = 3
    case skipped = 4
    case selfCorrected = 5
}

/// Who judged the recall: the person (self-grade) or the recitation model (V3b). Stored as its raw value.
public enum EvidenceProvenance: Int, Codable, Hashable, Sendable, CaseIterable {
    case manual = 0
    case model = 1
}

/// A canonical (Hafs) verse by its numbers, edition-free.
public struct MemorizationVerse: Hashable, Comparable, Codable, Sendable {
    // MARK: Lifecycle

    public init(sura: Int, ayah: Int) {
        self.sura = sura
        self.ayah = ayah
    }

    // MARK: Public

    public let sura: Int
    public let ayah: Int

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.sura, lhs.ayah) < (rhs.sura, rhs.ayah)
    }
}

/// One practice of a passage, from `first` to `last` inclusive.
public struct PracticeSessionRecord: Hashable, Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(id: UUID, first: MemorizationVerse, last: MemorizationVerse, startedOn: Date, endedOn: Date?) {
        self.id = id
        self.first = first
        self.last = last
        self.startedOn = startedOn
        self.endedOn = endedOn
    }

    // MARK: Public

    public let id: UUID
    public let first: MemorizationVerse
    public let last: MemorizationVerse
    public let startedOn: Date
    public let endedOn: Date?
}

/// One observation of recall. Append-only: a disputed or mistaken record is retracted
/// (`retractedOn`), never deleted, so sync and backups can merge it by `id`.
public struct RecallEvidenceRecord: Hashable, Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        sessionID: UUID,
        verse: MemorizationVerse,
        word: Int,
        outcome: RecallOutcome,
        assistance: Int,
        provenance: EvidenceProvenance,
        recordedOn: Date,
        retractedOn: Date? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.verse = verse
        self.word = word
        self.outcome = outcome
        self.assistance = assistance
        self.provenance = provenance
        self.recordedOn = recordedOn
        self.retractedOn = retractedOn
    }

    // MARK: Public

    public let id: UUID
    public let sessionID: UUID
    public let verse: MemorizationVerse
    /// The word number in the ayah's text (QUL numbering), or 0 for the whole ayah.
    public let word: Int
    public let outcome: RecallOutcome
    /// How much help the person had: 0 none; each hint or peek adds one.
    public let assistance: Int
    public let provenance: EvidenceProvenance
    public let recordedOn: Date
    public var retractedOn: Date?
}

/// Every stored session and evidence record.
public struct MemorizationHistory: Equatable, Sendable {
    public init(sessions: [PracticeSessionRecord], evidence: [RecallEvidenceRecord]) {
        self.sessions = sessions
        self.evidence = evidence
    }

    public let sessions: [PracticeSessionRecord]
    public let evidence: [RecallEvidenceRecord]
}

// MARK: - Core Data mapping

extension PracticeSessionRecord {
    /// `nil` for a record without an id or start date.
    public init?(_ stored: MO_PracticeSession) {
        guard let id = stored.id, let startedOn = stored.startedOn else {
            return nil
        }
        self.init(
            id: id,
            first: MemorizationVerse(sura: Int(stored.firstSura), ayah: Int(stored.firstAyah)),
            last: MemorizationVerse(sura: Int(stored.lastSura), ayah: Int(stored.lastAyah)),
            startedOn: startedOn,
            endedOn: stored.endedOn
        )
    }

    public func write(to stored: MO_PracticeSession) {
        stored.id = id
        stored.firstSura = Int32(first.sura)
        stored.firstAyah = Int32(first.ayah)
        stored.lastSura = Int32(last.sura)
        stored.lastAyah = Int32(last.ayah)
        stored.startedOn = startedOn
        stored.endedOn = endedOn
    }
}

extension RecallEvidenceRecord {
    /// `nil` for a record without ids or date, or with an outcome or provenance from a newer version.
    public init?(_ stored: MO_RecallEvidence) {
        guard let id = stored.id,
              let sessionID = stored.sessionID,
              let recordedOn = stored.recordedOn,
              let outcome = RecallOutcome(rawValue: Int(stored.outcome)),
              let provenance = EvidenceProvenance(rawValue: Int(stored.provenance))
        else {
            return nil
        }
        self.init(
            id: id,
            sessionID: sessionID,
            verse: MemorizationVerse(sura: Int(stored.sura), ayah: Int(stored.ayah)),
            word: Int(stored.word),
            outcome: outcome,
            assistance: Int(stored.assistance),
            provenance: provenance,
            recordedOn: recordedOn,
            retractedOn: stored.retractedOn
        )
    }

    public func write(to stored: MO_RecallEvidence) {
        stored.id = id
        stored.sessionID = sessionID
        stored.sura = Int32(verse.sura)
        stored.ayah = Int32(verse.ayah)
        stored.word = Int32(word)
        stored.outcome = Int16(outcome.rawValue)
        stored.assistance = Int16(clamping: assistance)
        stored.provenance = Int16(provenance.rawValue)
        stored.recordedOn = recordedOn
        stored.retractedOn = retractedOn
    }
}
