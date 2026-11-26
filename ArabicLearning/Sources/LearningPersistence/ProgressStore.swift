//
//  ProgressStore.swift
//  ArabicLearning (Arabican app)
//

import Foundation
import FSRS
import GRDB
import LearningEngine
import LearningModel

/// One profile's progress: skill evidence, FSRS review cards and the attempt log. Every attempt is
/// one transaction, so a kill mid-session never leaves evidence and the log out of step.
public final class ProgressStore: Sendable {
    // MARK: Lifecycle

    public init(fileURL: URL) throws {
        queue = try DatabaseQueue(path: fileURL.path)
        try Self.migrator.migrate(queue)
    }

    // MARK: Public

    public func evidence() async throws -> [SkillID: SkillEvidence] {
        try await queue.read { db in
            var result: [SkillID: SkillEvidence] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM evidence") {
                guard let skill = SkillID(row["skill"]) else { throw StoreError.malformedRow }
                result[skill] = SkillEvidence(
                    successes: row["successes"], scoredAttempts: row["scored_attempts"],
                    unscorableAttempts: row["unscorable_attempts"], lastAttempt: row["last_attempt"]
                )
            }
            return result
        }
    }

    /// When each scheduled skill is next due.
    public func dueDates() async throws -> [SkillID: Date] {
        try await queue.read { db in
            var result: [SkillID: Date] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT skill, due FROM review_card") {
                guard let skill = SkillID(row["skill"]) else { throw StoreError.malformedRow }
                result[skill] = row["due"]
            }
            return result
        }
    }

    public func attemptCount() async throws -> Int {
        try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM attempt") ?? 0 }
    }

    /// Records one attempt: the log row, the decayed evidence and, for scheduled skills, the FSRS card.
    public func record(_ outcome: AttemptOutcome, for skill: SkillID, at date: Date, scheduler: ReviewScheduler) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO attempt(skill, outcome, at) VALUES(?, ?, ?)",
                arguments: [skill.rawValue, outcome.rawValue, date]
            )
            var evidence = try Self.evidence(for: skill, db) ?? SkillEvidence()
            evidence.record(outcome, at: date)
            try db.execute(sql: """
            INSERT OR REPLACE INTO evidence(skill, successes, scored_attempts, unscorable_attempts, last_attempt)
            VALUES(?, ?, ?, ?, ?)
            """, arguments: [skill.rawValue, evidence.successes, evidence.scoredAttempts, evidence.unscorableAttempts, evidence.lastAttempt])
            guard ReviewScheduler.isScheduled(skill) else { return }
            let stored = try String.fetchOne(db, sql: "SELECT card FROM review_card WHERE skill = ?", arguments: [skill.rawValue])
            let card = try stored.map { try JSONDecoder().decode(Card.self, from: Data($0.utf8)) } ?? scheduler.newCard(now: date)
            let next = try scheduler.review(card, outcome: outcome, at: date)
            let json = try String(decoding: JSONEncoder().encode(next), as: UTF8.self)
            try db.execute(
                sql: "INSERT OR REPLACE INTO review_card(skill, card, due) VALUES(?, ?, ?)",
                arguments: [skill.rawValue, json, next.due]
            )
        }
    }

    // MARK: Private

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1 progress") { db in
            try db.execute(sql: """
            CREATE TABLE evidence(skill TEXT PRIMARY KEY, successes DOUBLE NOT NULL, scored_attempts DOUBLE NOT NULL,
                unscorable_attempts INTEGER NOT NULL, last_attempt DATETIME);
            CREATE TABLE review_card(skill TEXT PRIMARY KEY, card TEXT NOT NULL, due DATETIME NOT NULL);
            CREATE TABLE attempt(id INTEGER PRIMARY KEY AUTOINCREMENT, skill TEXT NOT NULL,
                outcome TEXT NOT NULL CHECK(outcome IN ('correct', 'incorrect', 'unscorable')), at DATETIME NOT NULL);
            """)
        }
        return migrator
    }

    private let queue: DatabaseQueue

    private static func evidence(for skill: SkillID, _ db: Database) throws -> SkillEvidence? {
        try Row.fetchOne(db, sql: "SELECT * FROM evidence WHERE skill = ?", arguments: [skill.rawValue]).map { row in
            SkillEvidence(
                successes: row["successes"],
                scoredAttempts: row["scored_attempts"],
                unscorableAttempts: row["unscorable_attempts"],
                lastAttempt: row["last_attempt"]
            )
        }
    }
}
