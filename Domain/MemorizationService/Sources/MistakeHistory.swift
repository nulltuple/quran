//
//  MistakeHistory.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import QuranAnnotations
import QuranKit

/// Explicit, deterministic decay policy for H7 mistake history and heatmaps.
///
/// Each mistake starts with weight `1.0` (counted at most once per word per session).
/// Weight decays by:
/// - `cleanRecallRetention` (`0.5` by default) for each subsequent clean unassisted recall of that ayah;
/// - exponential time decay with `halfLifeDays` (`60` days by default).
/// Scores below `minimumHeat` (`0.25`) clear from the heatmap and repair queue while remaining in history.
public struct MistakeDecayPolicy: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        cleanRecallRetention: Double = 0.5,
        halfLifeDays: Double = 60.0,
        minimumHeat: Double = 0.25,
        mediumThreshold: Double = 0.75,
        highThreshold: Double = 1.75
    ) {
        self.cleanRecallRetention = cleanRecallRetention
        self.halfLifeDays = halfLifeDays
        self.minimumHeat = minimumHeat
        self.mediumThreshold = mediumThreshold
        self.highThreshold = highThreshold
    }

    // MARK: Public

    public static let `default` = MistakeDecayPolicy()

    public let cleanRecallRetention: Double
    public let halfLifeDays: Double
    public let minimumHeat: Double
    public let mediumThreshold: Double
    public let highThreshold: Double

    /// Decayed weight of a single mistake observed `ageDays` ago with `cleanRecallsAfter`
    /// subsequent clean unassisted recalls of the same ayah.
    public func weight(ageDays: Double, cleanRecallsAfter: Int) -> Double {
        let clampedAge = max(0, ageDays)
        let timeFactor = halfLifeDays > 0 ? pow(0.5, clampedAge / halfLifeDays) : 1.0
        let recallFactor = pow(cleanRecallRetention, Double(max(0, cleanRecallsAfter)))
        return timeFactor * recallFactor
    }

    /// Maps a decayed score to a discrete heat tier, or `nil` when below `minimumHeat`.
    public func heatLevel(for score: Double) -> MistakeHeatLevel? {
        guard score >= minimumHeat else { return nil }
        if score >= highThreshold {
            return .high
        }
        if score >= mediumThreshold {
            return .medium
        }
        return .low
    }
}

/// One mistake occurrence for a word (or whole ayah when `word == 0`) within a single session.
///
/// Enforces the H7 rule: at most one count per word per session. If duplicate evidence records
/// exist for the same `(sessionID, verse, word)`, all of their IDs are carried in `evidenceIDs`
/// so confirming, disputing, or removing operates on the whole entry cleanly.
public struct MistakeEvent: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        evidenceIDs: [UUID],
        sessionID: UUID,
        sessionPassage: Passage?,
        verse: AyahNumber,
        word: Int,
        outcome: RecallOutcome,
        provenance: EvidenceProvenance,
        recordedOn: Date,
        retractedOn: Date? = nil,
        decayedWeight: Double
    ) {
        self.id = id
        self.evidenceIDs = evidenceIDs
        self.sessionID = sessionID
        self.sessionPassage = sessionPassage
        self.verse = verse
        self.word = word
        self.outcome = outcome
        self.provenance = provenance
        self.recordedOn = recordedOn
        self.retractedOn = retractedOn
        self.decayedWeight = decayedWeight
    }

    // MARK: Public

    public let id: UUID
    public let evidenceIDs: [UUID]
    public let sessionID: UUID
    public let sessionPassage: Passage?
    public let verse: AyahNumber
    /// Canonical QUL word number (1-based), or `0` for a whole-ayah mistake / forget.
    public let word: Int
    public let outcome: RecallOutcome
    public let provenance: EvidenceProvenance
    public let recordedOn: Date
    public let retractedOn: Date?
    public let decayedWeight: Double

    public var isRetracted: Bool {
        retractedOn != nil
    }
}

/// Aggregated mistake history for a single canonical word across sessions.
public struct WordMistakeSummary: Identifiable, Hashable, Sendable {
    public let word: Word
    public let score: Double
    public let level: MistakeHeatLevel?
    public let sessionCount: Int
    public let lastMistakeOn: Date
    public let events: [MistakeEvent]

    public var id: Word { word }
}

/// Aggregated mistake history for a single canonical ayah across sessions.
public struct VerseMistakeSummary: Identifiable, Hashable, Sendable {
    public let verse: AyahNumber
    public let score: Double
    public let level: MistakeHeatLevel?
    public let sessionCount: Int
    public let lastMistakeOn: Date?
    public let cleanRecallsSinceLastMistake: Int
    public let wordSummaries: [WordMistakeSummary]
    /// Active mistake events shown in the detail sheet, newest first.
    public let activeEvents: [MistakeEvent]
    /// Disputed or removed mistake events, newest first.
    public let retractedEvents: [MistakeEvent]

    public var id: AyahNumber { verse }

    public var activeHeatWordCount: Int {
        wordSummaries.count { $0.level != nil }
    }
}

/// Whole-Quran mistake history computed purely from `MemorizationHistory` (never persisted).
public struct MistakeHistorySnapshot: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        policy: MistakeDecayPolicy = .default,
        verseSummaries: [AyahNumber: VerseMistakeSummary] = [:]
    ) {
        self.policy = policy
        self.verseSummaries = verseSummaries
    }

    // MARK: Public

    public let policy: MistakeDecayPolicy
    /// Summaries for every verse that has active or retracted mistake history.
    public let verseSummaries: [AyahNumber: VerseMistakeSummary]

    /// Verses currently above `policy.minimumHeat`.
    public var hotVerses: [VerseMistakeSummary] {
        verseSummaries.values
            .filter { $0.level != nil }
            .sorted { ($0.score, $0.verse) > ($1.score, $1.verse) }
    }

    /// Builds a `MistakeHeatmapOverlay` mapped onto `quran` (the reader's active edition).
    public func heatmapOverlay(for quran: Quran) -> MistakeHeatmapOverlay {
        var verseLevels: [AyahNumber: MistakeHeatLevel] = [:]
        var wordLevels: [Word: MistakeHeatLevel] = [:]

        for (canonicalVerse, summary) in verseSummaries {
            guard let targetVerse = AyahNumber(quran: quran, sura: canonicalVerse.sura.suraNumber, ayah: canonicalVerse.ayah) else {
                continue
            }
            if let level = summary.level {
                verseLevels[targetVerse] = level
            }
            for wordSummary in summary.wordSummaries {
                if let level = wordSummary.level {
                    wordLevels[Word(verse: targetVerse, wordNumber: wordSummary.word.wordNumber)] = level
                }
            }
        }
        return MistakeHeatmapOverlay(verseLevels: verseLevels, wordLevels: wordLevels)
    }
}

/// One passage in the H7 Repair Queue: always a full hafiz-sized passage, never isolated words.
public struct RepairQueueItem: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        passage: Passage,
        totalHeat: Double,
        maxHeatLevel: MistakeHeatLevel,
        mistakenVerseCount: Int,
        mistakenWordCount: Int,
        hotVerses: [VerseMistakeSummary],
        lastMistakeOn: Date
    ) {
        self.passage = passage
        self.totalHeat = totalHeat
        self.maxHeatLevel = maxHeatLevel
        self.mistakenVerseCount = mistakenVerseCount
        self.mistakenWordCount = mistakenWordCount
        self.hotVerses = hotVerses
        self.lastMistakeOn = lastMistakeOn
    }

    // MARK: Public

    public let passage: Passage
    public let totalHeat: Double
    public let maxHeatLevel: MistakeHeatLevel
    public let mistakenVerseCount: Int
    public let mistakenWordCount: Int
    public let hotVerses: [VerseMistakeSummary]
    public let lastMistakeOn: Date

    public var id: String {
        "\(passage.first.sura.suraNumber):\(passage.first.ayah)-\(passage.last.sura.suraNumber):\(passage.last.ayah)"
    }
}

/// Pure reducer turning append-only `MemorizationHistory` into decayed mistake heatmaps and repair queues.
public enum MistakeHistoryReducer {
    // MARK: Public

    /// Computes decayed word and ayah mistake summaries from `history` at timestamp `now`.
    public static func reduce(
        history: MemorizationHistory,
        quran: Quran = .hafsMadani1405,
        now: Date,
        policy: MistakeDecayPolicy = .default
    ) -> MistakeHistorySnapshot {
        let deduped = dedupeAll(history.evidence)
        let sessionsByID = Dictionary(uniqueKeysWithValues: history.sessions.map { ($0.id, $0) })

        // Separate active vs retracted records.
        let activeRecords = deduped.filter { $0.retractedOn == nil }
        let retractedMistakes = deduped.filter { $0.retractedOn != nil && isMistakeOutcome($0.outcome) }

        // Group active records by verse and session to evaluate clean recalls and one-per-word-per-session mistakes.
        struct SessionVerseKey: Hashable {
            let sessionID: UUID
            let verse: MemorizationVerse
        }

        let activeBySessionVerse = Dictionary(grouping: activeRecords) {
            SessionVerseKey(sessionID: $0.sessionID, verse: $0.verse)
        }

        // Collect chronological clean-recall timestamps per verse (one per session).
        var cleanRecallDatesByVerse: [MemorizationVerse: [Date]] = [:]
        // Collect per-session mistake entries per verse.
        struct RawSessionMistakes {
            let sessionID: UUID
            let sessionDate: Date
            let sessionPassage: Passage?
            let ayahRecords: [RecallEvidenceRecord]
            let wordRecords: [Int: [RecallEvidenceRecord]]
        }
        var mistakesByVerse: [MemorizationVerse: [RawSessionMistakes]] = [:]

        for (key, records) in activeBySessionVerse {
            let session = sessionsByID[key.sessionID]
            let sessionDate = session.map { $0.endedOn ?? $0.startedOn }
                ?? records.map(\.recordedOn).max()
                ?? now
            let passage: Passage? = session.flatMap { s in
                guard let first = AyahNumber(quran: quran, sura: s.first.sura, ayah: s.first.ayah),
                      let last = AyahNumber(quran: quran, sura: s.last.sura, ayah: s.last.ayah)
                else {
                    return nil
                }
                return Passage(first, last)
            }

            let mistakeRecords = records.filter { isMistakeOutcome($0.outcome) }
            if mistakeRecords.isEmpty {
                // Clean unassisted recall: every active record for this verse in this session is `.correct` with 0 assistance.
                let isClean = !records.isEmpty && records.allSatisfy { $0.outcome == .correct && $0.assistance == 0 }
                if isClean {
                    cleanRecallDatesByVerse[key.verse, default: []].append(sessionDate)
                }
            } else {
                let ayahMistakes = mistakeRecords.filter { $0.word == 0 }
                let wordMistakes = Dictionary(grouping: mistakeRecords.filter { $0.word > 0 }, by: \.word)
                mistakesByVerse[key.verse, default: []].append(
                    RawSessionMistakes(
                        sessionID: key.sessionID,
                        sessionDate: sessionDate,
                        sessionPassage: passage,
                        ayahRecords: ayahMistakes,
                        wordRecords: wordMistakes
                    )
                )
            }
        }

        let retractedByVerse = Dictionary(grouping: retractedMistakes, by: \.verse)
        let allRelevantVerses = Set(mistakesByVerse.keys).union(retractedByVerse.keys)

        var summaries: [AyahNumber: VerseMistakeSummary] = [:]

        for verseKey in allRelevantVerses {
            guard let ayah = AyahNumber(quran: quran, sura: verseKey.sura, ayah: verseKey.ayah) else {
                continue
            }

            let cleanDates = (cleanRecallDatesByVerse[verseKey] ?? []).sorted()
            let sessionMistakes = (mistakesByVerse[verseKey] ?? []).sorted { $0.sessionDate < $1.sessionDate }

            var ayahSessionScore = 0.0
            var wordEventsByWord: [Int: [MistakeEvent]] = [:]
            var displayActiveEvents: [MistakeEvent] = []
            var lastMistakeOn: Date?

            for entry in sessionMistakes {
                let ageDays = now.timeIntervalSince(entry.sessionDate) / 86400.0
                let cleanAfter = cleanDates.count { $0 > entry.sessionDate }
                let weight = policy.weight(ageDays: ageDays, cleanRecallsAfter: cleanAfter)

                // Each session with any mistake contributes at most once to ayah-level session score.
                ayahSessionScore += weight
                if lastMistakeOn.map({ entry.sessionDate > $0 }) ?? true {
                    lastMistakeOn = entry.sessionDate
                }

                // Word-level mistakes: one count per word per session.
                for (wordNumber, wordRecs) in entry.wordRecords.sorted(by: { $0.key < $1.key }) {
                    guard let rep = representative(from: wordRecs) else { continue }
                    let event = MistakeEvent(
                        id: rep.id,
                        evidenceIDs: wordRecs.map(\.id),
                        sessionID: entry.sessionID,
                        sessionPassage: entry.sessionPassage,
                        verse: ayah,
                        word: wordNumber,
                        outcome: rep.outcome,
                        provenance: mergedProvenance(wordRecs),
                        recordedOn: rep.recordedOn,
                        retractedOn: nil,
                        decayedWeight: weight
                    )
                    wordEventsByWord[wordNumber, default: []].append(event)
                    displayActiveEvents.append(event)
                }

                // Standalone ayah-level mistake (Forgot / skipped verse / confusion drill / ayah-only mistake):
                // shown in the detail list only when the session has no word-level mistakes for this verse.
                if entry.wordRecords.isEmpty, let rep = representative(from: entry.ayahRecords) {
                    let event = MistakeEvent(
                        id: rep.id,
                        evidenceIDs: entry.ayahRecords.map(\.id),
                        sessionID: entry.sessionID,
                        sessionPassage: entry.sessionPassage,
                        verse: ayah,
                        word: 0,
                        outcome: rep.outcome,
                        provenance: mergedProvenance(entry.ayahRecords),
                        recordedOn: rep.recordedOn,
                        retractedOn: nil,
                        decayedWeight: weight
                    )
                    displayActiveEvents.append(event)
                }
            }

            let wordSummaries: [WordMistakeSummary] = wordEventsByWord.keys.sorted().compactMap { wordNumber in
                let events = (wordEventsByWord[wordNumber] ?? []).sorted { $0.recordedOn > $1.recordedOn }
                guard let latest = events.first?.recordedOn else { return nil }
                let score = events.reduce(0.0) { $0 + $1.decayedWeight }
                return WordMistakeSummary(
                    word: Word(verse: ayah, wordNumber: wordNumber),
                    score: score,
                    level: policy.heatLevel(for: score),
                    sessionCount: events.count,
                    lastMistakeOn: latest,
                    events: events
                )
            }

            // Retracted events for detail sheet (group by session + word; omit companion word=0 if retracted word>0 exists in same session).
            let retractedEvents = Self.buildRetractedEvents(
                records: retractedByVerse[verseKey] ?? [],
                ayah: ayah,
                sessionsByID: sessionsByID,
                quran: quran
            )

            let maxWordScore = wordSummaries.map(\.score).max() ?? 0.0
            let verseScore = max(ayahSessionScore, maxWordScore)
            let cleanSinceLast = lastMistakeOn.map { last in cleanDates.count { $0 > last } } ?? 0

            summaries[ayah] = VerseMistakeSummary(
                verse: ayah,
                score: verseScore,
                level: policy.heatLevel(for: verseScore),
                sessionCount: sessionMistakes.count,
                lastMistakeOn: lastMistakeOn,
                cleanRecallsSinceLastMistake: cleanSinceLast,
                wordSummaries: wordSummaries,
                activeEvents: displayActiveEvents.sorted { ($0.recordedOn, $0.word) > ($1.recordedOn, $1.word) },
                retractedEvents: retractedEvents
            )
        }

        return MistakeHistorySnapshot(policy: policy, verseSummaries: summaries)
    }

    /// Groups active weak verses into hafiz-sized passages for the H7 Repair Queue.
    ///
    /// Never emits isolated single-word items; every hot verse maps to:
    /// 1. an active user `PassageRecord` covering the verse, if one exists;
    /// 2. otherwise the most recently practiced multi-ayah `Passage` covering the verse;
    /// 3. otherwise the default `PassageSplitter` chunk (sura-on-page, ≤ 10 verses) containing the verse.
    public static func repairQueue(
        from snapshot: MistakeHistorySnapshot,
        history: MemorizationHistory,
        quran: Quran = .hafsMadani1405
    ) -> [RepairQueueItem] {
        let hotVerses = snapshot.hotVerses
        guard !hotVerses.isEmpty else { return [] }

        let activePassages: [Passage] = activePassageRecords(from: history.passages).compactMap { record in
            guard let first = AyahNumber(quran: quran, sura: record.first.sura, ayah: record.first.ayah),
                  let last = AyahNumber(quran: quran, sura: record.last.sura, ayah: record.last.ayah)
            else {
                return nil
            }
            return Passage(first, last)
        }

        let practicedMultiAyahPassages: [(passage: Passage, date: Date)] = history.sessions.compactMap { session in
            guard let first = AyahNumber(quran: quran, sura: session.first.sura, ayah: session.first.ayah),
                  let last = AyahNumber(quran: quran, sura: session.last.sura, ayah: session.last.ayah),
                  first < last
            else {
                return nil
            }
            return (Passage(first, last), session.endedOn ?? session.startedOn)
        }
        .sorted { $0.date > $1.date }

        var grouped: [Passage: [VerseMistakeSummary]] = [:]
        for summary in hotVerses {
            let passage = resolveRepairPassage(
                for: summary.verse,
                activePassages: activePassages,
                practicedPassages: practicedMultiAyahPassages
            )
            grouped[passage, default: []].append(summary)
        }

        return grouped.compactMap { passage, verses -> RepairQueueItem? in
            let sortedVerses = verses.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.verse < $1.verse
            }
            guard let maxLevel = sortedVerses.compactMap(\.level).max(),
                  let lastMistake = sortedVerses.compactMap(\.lastMistakeOn).max()
            else {
                return nil
            }
            let totalHeat = sortedVerses.reduce(0.0) { $0 + $1.score }
            let wordCount = sortedVerses.reduce(0) { $0 + $1.activeHeatWordCount }
            return RepairQueueItem(
                passage: passage,
                totalHeat: totalHeat,
                maxHeatLevel: maxLevel,
                mistakenVerseCount: sortedVerses.count,
                mistakenWordCount: wordCount,
                hotVerses: sortedVerses,
                lastMistakeOn: lastMistake
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalHeat != rhs.totalHeat { return lhs.totalHeat > rhs.totalHeat }
            if lhs.lastMistakeOn != rhs.lastMistakeOn { return lhs.lastMistakeOn > rhs.lastMistakeOn }
            return lhs.passage.first < rhs.passage.first
        }
    }

    // MARK: Private

    private static func isMistakeOutcome(_ outcome: RecallOutcome) -> Bool {
        outcome == .mistake || outcome == .revealed
    }

    /// Dedupes evidence records by `id`, preserving retraction if any copy is retracted.
    private static func dedupeAll(_ evidence: [RecallEvidenceRecord]) -> [RecallEvidenceRecord] {
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
        return order.compactMap { byID[$0] }
    }

    private static func representative(from records: [RecallEvidenceRecord]) -> RecallEvidenceRecord? {
        // Prefer `.revealed` over `.mistake`, manual over model, newest recordedOn.
        records.max { lhs, rhs in
            let lhsRank = (lhs.outcome == .revealed ? 2 : 1, lhs.provenance == .manual ? 1 : 0, lhs.recordedOn)
            let rhsRank = (rhs.outcome == .revealed ? 2 : 1, rhs.provenance == .manual ? 1 : 0, rhs.recordedOn)
            return lhsRank < rhsRank
        }
    }

    private static func mergedProvenance(_ records: [RecallEvidenceRecord]) -> EvidenceProvenance {
        records.contains(where: { $0.provenance == .manual }) ? .manual : .model
    }

    private static func buildRetractedEvents(
        records: [RecallEvidenceRecord],
        ayah: AyahNumber,
        sessionsByID: [UUID: PracticeSessionRecord],
        quran: Quran
    ) -> [MistakeEvent] {
        guard !records.isEmpty else { return [] }
        let bySession = Dictionary(grouping: records, by: \.sessionID)
        var events: [MistakeEvent] = []
        for (sessionID, sessionRecords) in bySession {
            let passage: Passage? = sessionsByID[sessionID].flatMap { s in
                guard let first = AyahNumber(quran: quran, sura: s.first.sura, ayah: s.first.ayah),
                      let last = AyahNumber(quran: quran, sura: s.last.sura, ayah: s.last.ayah)
                else {
                    return nil
                }
                return Passage(first, last)
            }
            let wordGroups = Dictionary(grouping: sessionRecords.filter { $0.word > 0 }, by: \.word)
            for (wordNumber, wordRecs) in wordGroups {
                guard let rep = representative(from: wordRecs) else { continue }
                events.append(
                    MistakeEvent(
                        id: rep.id,
                        evidenceIDs: wordRecs.map(\.id),
                        sessionID: sessionID,
                        sessionPassage: passage,
                        verse: ayah,
                        word: wordNumber,
                        outcome: rep.outcome,
                        provenance: mergedProvenance(wordRecs),
                        recordedOn: rep.recordedOn,
                        retractedOn: wordRecs.compactMap(\.retractedOn).min(),
                        decayedWeight: 0
                    )
                )
            }
            if wordGroups.isEmpty {
                let ayahRecs = sessionRecords.filter { $0.word == 0 }
                if let rep = representative(from: ayahRecs) {
                    events.append(
                        MistakeEvent(
                            id: rep.id,
                            evidenceIDs: ayahRecs.map(\.id),
                            sessionID: sessionID,
                            sessionPassage: passage,
                            verse: ayah,
                            word: 0,
                            outcome: rep.outcome,
                            provenance: mergedProvenance(ayahRecs),
                            recordedOn: rep.recordedOn,
                            retractedOn: ayahRecs.compactMap(\.retractedOn).min(),
                            decayedWeight: 0
                        )
                    )
                }
            }
        }
        return events.sorted { ($0.retractedOn ?? $0.recordedOn) > ($1.retractedOn ?? $1.recordedOn) }
    }

    private static func activePassageRecords(from records: [PassageRecord]) -> [PassageRecord] {
        var byID: [UUID: PassageRecord] = [:]
        var order: [UUID] = []
        for record in records {
            if var existing = byID[record.id] {
                if record.modifiedOn > existing.modifiedOn {
                    var updated = record
                    updated.removedOn = existing.removedOn ?? record.removedOn
                    byID[record.id] = updated
                } else {
                    existing.removedOn = existing.removedOn ?? record.removedOn
                    byID[record.id] = existing
                }
            } else {
                byID[record.id] = record
                order.append(record.id)
            }
        }
        return order.compactMap { byID[$0] }.filter { $0.removedOn == nil }
    }

    private static func resolveRepairPassage(
        for verse: AyahNumber,
        activePassages: [Passage],
        practicedPassages: [(passage: Passage, date: Date)]
    ) -> Passage {
        let containingActive = activePassages
            .filter { $0.first <= verse && verse <= $0.last }
            .min { ($0.verses.count, $0.first) < ($1.verses.count, $1.first) }
        if let containingActive {
            return containingActive
        }

        if let practiced = practicedPassages.first(where: { $0.passage.first <= verse && verse <= $0.passage.last }) {
            return practiced.passage
        }

        let pageVerses = verse.page.verses.filter { $0.sura == verse.sura }
        if let first = pageVerses.first, let last = pageVerses.last {
            let defaults = PassageSplitter.defaultPassages(covering: first ... last)
            if let match = defaults.first(where: { $0.first <= verse && verse <= $0.last }) {
                return match
            }
            return Passage(first, last)
        }
        return Passage(verse, verse)
    }
}
