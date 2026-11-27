//
//  MemorizationService.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import QuranKit

/// Records practice and computes each passage's review state (roadmap H1). No UI; the clock and
/// ids are injected so every rule is testable.
public struct MemorizationService {
    // MARK: Lifecycle

    public init(
        persistence: CoreDataMemorizationPersistence,
        quran: Quran = .hafsMadani1405,
        scheduler: PassageScheduler = PassageScheduler(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.persistence = persistence
        self.quran = quran
        self.scheduler = scheduler
        self.now = now
        self.makeID = makeID
    }

    // MARK: Public

    /// Stores a finished session: one evidence record per verse, plus one per mistaken word, all manual.
    @discardableResult
    public func recordSession(
        _ passage: Passage,
        startedOn: Date,
        recalls: [VerseRecall]
    ) async throws -> UUID {
        let endedOn = now()
        let session = PracticeSessionRecord(
            id: makeID(),
            first: Self.verse(passage.first),
            last: Self.verse(passage.last),
            startedOn: startedOn,
            endedOn: endedOn
        )
        let evidence = recalls.flatMap { recall in
            let ayah = evidenceRecord(session: session.id, verse: recall.verse, word: 0, recall.outcome, recall.assistance, endedOn)
            let words = Set(recall.mistakenWords).sorted().map {
                evidenceRecord(session: session.id, verse: recall.verse, word: $0, .mistake, 0, endedOn)
            }
            return [ayah] + words
        }
        try await persistence.record(session, evidence: evidence)
        return session.id
    }

    /// Takes back evidence (a disputed model judgment, a mis-tap); it stops counting but stays stored.
    public func retractEvidence(withIDs ids: Set<UUID>) async throws {
        try await persistence.retractEvidence(withIDs: ids, on: now())
    }

    /// Every practiced passage, soonest due first.
    public func progress() async throws -> [PassageProgress] {
        let history = try await persistence.history()
        let evidenceBySession = Dictionary(grouping: EvidenceReducer.effective(history.evidence), by: \.sessionID)
        var sessionsByPassage: [Passage: [PracticeSessionRecord]] = [:]
        for session in history.sessions {
            guard let first = ayah(session.first), let last = ayah(session.last) else { continue }
            sessionsByPassage[Passage(first, last), default: []].append(session)
        }
        return sessionsByPassage.map { passage, sessions in
            let reviews = sessions.compactMap { session in
                EvidenceReducer.grade(of: evidenceBySession[session.id] ?? []).map {
                    PassageScheduler.Review(date: session.endedOn ?? session.startedOn, grade: $0)
                }
            }
            let (strength, due) = scheduler.schedule(reviews)
            let last = reviews.max { $0.date < $1.date }
            return PassageProgress(
                passage: passage,
                strength: strength,
                due: due,
                gradedSessions: reviews.count,
                lastPracticed: sessions.map { $0.endedOn ?? $0.startedOn }.max(),
                lastGrade: last?.grade
            )
        }
        .sorted { ($0.due ?? .distantFuture, $0.passage.first) < ($1.due ?? .distantFuture, $1.passage.first) }
    }

    /// `passage`'s state; unassessed when it was never practiced as this exact range.
    public func progress(of passage: Passage) async throws -> PassageProgress {
        try await progress().first { $0.passage == passage }
            ?? PassageProgress(passage: passage, strength: .unassessed, due: nil, gradedSessions: 0, lastPracticed: nil, lastGrade: nil)
    }

    // MARK: Private

    private let persistence: CoreDataMemorizationPersistence
    private let quran: Quran
    private let scheduler: PassageScheduler
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    private static func verse(_ ayah: AyahNumber) -> MemorizationVerse {
        MemorizationVerse(sura: ayah.sura.suraNumber, ayah: ayah.ayah)
    }

    private func ayah(_ verse: MemorizationVerse) -> AyahNumber? {
        AyahNumber(quran: quran, sura: verse.sura, ayah: verse.ayah)
    }

    private func evidenceRecord(
        session: UUID,
        verse: AyahNumber,
        word: Int,
        _ outcome: RecallOutcome,
        _ assistance: Int,
        _ date: Date
    ) -> RecallEvidenceRecord {
        RecallEvidenceRecord(
            id: makeID(),
            sessionID: session,
            verse: Self.verse(verse),
            word: word,
            outcome: outcome,
            assistance: assistance,
            provenance: .manual,
            recordedOn: date
        )
    }
}
