//
//  EvidenceReducer.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import MemorizationPersistence

/// Pure rules that turn recall evidence into session grades.
public enum EvidenceReducer {
    /// The evidence that counts: one record per id (a record retracted in any copy is retracted),
    /// retracted records left out. Applying it twice gives the same result.
    public static func effective(_ evidence: [RecallEvidenceRecord]) -> [RecallEvidenceRecord] {
        var byID: [UUID: RecallEvidenceRecord] = [:]
        var order: [UUID] = []
        for record in evidence {
            if var existing = byID[record.id] {
                existing.retractedOn = existing.retractedOn ?? record.retractedOn
                byID[record.id] = existing
            } else {
                byID[record.id] = record
                order.append(record.id)
            }
        }
        return order.compactMap { byID[$0] }.filter { $0.retractedOn == nil }
    }

    /// A session's grade from its effective evidence; `nil` when no verse was graded (all skipped).
    ///
    /// - again: a verse revealed, or mistakes in at least a third of the graded verses;
    /// - hard: any mistake, hint, self-correction or assistance;
    /// - good: every graded verse correct without help.
    ///
    /// "Easy" is never inferred: a hafiz's passage should not jump to long intervals from one clean recitation.
    public static func grade(of evidence: [RecallEvidenceRecord]) -> SessionGrade? {
        let graded = Dictionary(grouping: evidence.filter { $0.outcome != .skipped }, by: \.verse)
        guard !graded.isEmpty else {
            return nil
        }
        var versesWithMistakes = 0
        var needsHelp = false
        for records in graded.values {
            if records.contains(where: { $0.outcome == .revealed }) {
                return .again
            }
            if records.contains(where: { $0.outcome == .mistake }) {
                versesWithMistakes += 1
            }
            if records.contains(where: { [.hint, .selfCorrected].contains($0.outcome) || $0.assistance > 0 }) {
                needsHelp = true
            }
        }
        if versesWithMistakes * 3 >= graded.count, versesWithMistakes > 0 {
            return .again
        }
        return versesWithMistakes > 0 || needsHelp ? .hard : .good
    }
}
