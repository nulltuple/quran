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

    /// Stores a finished session: one evidence record per verse, plus one per mistaken word.
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
            let ayah = evidenceRecord(
                session: session.id,
                verse: recall.verse,
                word: 0,
                recall.outcome,
                recall.assistance,
                recall.provenance,
                endedOn
            )
            let words = Set(recall.mistakenWords).sorted().map {
                evidenceRecord(session: session.id, verse: recall.verse, word: $0, .mistake, 0, recall.provenance, endedOn)
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

    // MARK: - Declared ranges & passages (H3)

    /// Declares `range` as already memorized and generates default review passages for any
    /// verses in `range` not already covered by active passages.
    @discardableResult
    public func declareMemorized(_ range: ClosedRange<AyahNumber>) async throws -> MemorizedRangeRecord {
        let timestamp = now()
        let canonical = canonicalRange(range)
        let record = MemorizedRangeRecord(
            id: makeID(),
            first: Self.verse(canonical.lowerBound),
            last: Self.verse(canonical.upperBound),
            declaredOn: timestamp
        )
        let history = try await persistence.history()
        let existingPassageRanges = AyahRangeSet(
            activePassages(from: history.passages).compactMap { passageRange($0) }
        )
        let uncovered = AyahRangeSet(canonical).subtracting(existingPassageRanges)
        let newPassages = PassageSplitter.defaultPassages(for: uncovered).map { passage in
            PassageRecord(
                id: makeID(),
                first: Self.verse(passage.first),
                last: Self.verse(passage.last),
                createdOn: timestamp,
                modifiedOn: timestamp
            )
        }
        try await persistence.saveDeclaredRange(record, passages: newPassages)
        return record
    }

    /// Removes a declared memorized range (tombstoned) and tombstones active passages wholly inside
    /// it that are not covered by any remaining declared range. Past practice evidence is preserved.
    public func removeDeclaredRange(id: UUID) async throws {
        let timestamp = now()
        let history = try await persistence.history()
        let activeRanges = activeDeclaredRanges(from: history.declaredRanges)
        guard let target = activeRanges.first(where: { $0.id == id }),
              let targetRange = declaredRange(target)
        else {
            return
        }
        let remainingSet = AyahRangeSet(
            activeRanges.filter { $0.id != id }.compactMap(declaredRange)
        )
        let targetSet = AyahRangeSet(targetRange)
        let orphanedPassageIDs = Set(
            activePassages(from: history.passages).compactMap { record -> UUID? in
                guard let range = passageRange(record) else { return nil }
                guard targetSet.contains(range), !remainingSet.contains(range) else { return nil }
                return record.id
            }
        )
        try await persistence.removeDeclaredRanges(withIDs: [id], removingPassageIDs: orphanedPassageIDs, on: timestamp)
    }

    /// Skips a passage for the rest of today (snoozes until start of tomorrow).
    public func skipPassage(
        _ passage: Passage,
        passageRecordID: UUID?,
        calendar: Calendar = .current
    ) async throws {
        let tomorrowStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now()) ?? now().addingTimeInterval(86400))
        try await reschedulePassage(passage, passageRecordID: passageRecordID, until: tomorrowStart)
    }

    /// Reschedules a passage until `date`.
    public func reschedulePassage(
        _ passage: Passage,
        passageRecordID: UUID?,
        until date: Date
    ) async throws {
        let timestamp = now()
        let canonical = canonicalPassage(passage)
        let history = try await persistence.history()
        let active = activePassages(from: history.passages)
        if var existing = matchingPassageRecord(id: passageRecordID, passage: canonical, in: active) {
            existing.snoozedUntil = date
            existing.modifiedOn = timestamp
            try await persistence.savePassages([existing])
        } else {
            let record = PassageRecord(
                id: makeID(),
                first: Self.verse(canonical.first),
                last: Self.verse(canonical.last),
                createdOn: timestamp,
                modifiedOn: timestamp,
                snoozedUntil: date
            )
            try await persistence.savePassages([record])
        }
    }

    /// Splits a multi-ayah passage after `splitVerse` into two user-editable passages.
    public func splitPassage(
        id passageRecordID: UUID?,
        passage: Passage,
        after splitVerse: AyahNumber
    ) async throws {
        let canonical = canonicalPassage(passage)
        guard let split = ayah(Self.verse(splitVerse)),
              split >= canonical.first,
              split < canonical.last,
              let secondStart = split.next
        else {
            return
        }
        let timestamp = now()
        let history = try await persistence.history()
        let active = activePassages(from: history.passages)
        var toSave: [PassageRecord] = []
        if var existing = matchingPassageRecord(id: passageRecordID, passage: canonical, in: active) {
            existing.removedOn = timestamp
            existing.modifiedOn = timestamp
            toSave.append(existing)
        }
        toSave.append(
            PassageRecord(
                id: makeID(),
                first: Self.verse(canonical.first),
                last: Self.verse(split),
                createdOn: timestamp,
                modifiedOn: timestamp
            )
        )
        toSave.append(
            PassageRecord(
                id: makeID(),
                first: Self.verse(secondStart),
                last: Self.verse(canonical.last),
                createdOn: timestamp,
                modifiedOn: timestamp
            )
        )
        try await persistence.savePassages(toSave)
    }

    /// Resets a passage's review progress by retracting its active evidence and clearing any snooze.
    public func resetPassage(_ passage: Passage, passageRecordID: UUID?) async throws {
        let timestamp = now()
        let canonical = canonicalPassage(passage)
        let history = try await persistence.history()
        let matchingSessionIDs = Set(
            history.sessions.compactMap { session -> UUID? in
                guard let first = ayah(session.first), let last = ayah(session.last) else { return nil }
                return Passage(first, last) == canonical ? session.id : nil
            }
        )
        let activeEvidenceIDs = Set(
            EvidenceReducer.effective(history.evidence)
                .filter { matchingSessionIDs.contains($0.sessionID) }
                .map(\.id)
        )
        if !activeEvidenceIDs.isEmpty {
            try await persistence.retractEvidence(withIDs: activeEvidenceIDs, on: timestamp)
        }
        let active = activePassages(from: history.passages)
        if var existing = matchingPassageRecord(id: passageRecordID, passage: canonical, in: active), existing.snoozedUntil != nil {
            existing.snoozedUntil = nil
            existing.modifiedOn = timestamp
            try await persistence.savePassages([existing])
        }
    }

    // MARK: - Review queue & memorization map (H3)

    /// Computes the Sabaq/Sabqi/Manzil review queue with reasons and daily budget tracking.
    public func reviewQueue(
        budgets: ReviewDailyBudgets = ReviewDailyBudgets(),
        calendar: Calendar = .current
    ) async throws -> ReviewQueueSnapshot {
        let currentNow = now()
        let history = try await persistence.history()
        let evidenceBySession = Dictionary(grouping: EvidenceReducer.effective(history.evidence), by: \.sessionID)

        let activeRanges = activeDeclaredRanges(from: history.declaredRanges)
        let declaredItems: [DeclaredRangeItem] = activeRanges.compactMap { record in
            guard let range = declaredRange(record) else { return nil }
            return DeclaredRangeItem(id: record.id, range: range, declaredOn: record.declaredOn)
        }
        let declaredSet = AyahRangeSet(declaredItems.map(\.range))

        var sessionsByPassage: [Passage: [PracticeSessionRecord]] = [:]
        for session in history.sessions {
            guard let first = ayah(session.first), let last = ayah(session.last) else { continue }
            sessionsByPassage[Passage(first, last), default: []].append(session)
        }

        let activePassageRecords = activePassages(from: history.passages)
        var recordsByPassage: [Passage: PassageRecord] = [:]
        for record in activePassageRecords {
            guard let first = ayah(record.first), let last = ayah(record.last) else { continue }
            let passage = Passage(first, last)
            if let existing = recordsByPassage[passage], existing.modifiedOn >= record.modifiedOn {
                continue
            }
            recordsByPassage[passage] = record
        }

        var candidatePassages = Set(recordsByPassage.keys)
        for (passage, sessions) in sessionsByPassage {
            let hasGradedSession = sessions.contains { EvidenceReducer.grade(of: evidenceBySession[$0.id] ?? []) != nil }
            if hasGradedSession {
                candidatePassages.insert(passage)
            }
        }

        struct RawEntry {
            let id: UUID
            let recordID: UUID?
            let passage: Passage
            let progress: PassageProgress
            let bucket: ReviewBucket
            let isDeclared: Bool
            let isDue: Bool
            let snoozedUntil: Date?
            let reason: ReviewReason
            let weakStreak: Int
            let practicedToday: Bool
        }

        var rawEntries: [RawEntry] = []
        for passage in candidatePassages {
            let record = recordsByPassage[passage]
            let sessions = sessionsByPassage[passage] ?? []
            let reviews = sessions.compactMap { session -> PassageScheduler.Review? in
                guard let grade = EvidenceReducer.grade(of: evidenceBySession[session.id] ?? []) else { return nil }
                return PassageScheduler.Review(date: session.endedOn ?? session.startedOn, grade: grade)
            }.sorted { $0.date < $1.date }

            let (strength, due) = scheduler.schedule(reviews)
            let lastPracticed = sessions.map { $0.endedOn ?? $0.startedOn }.max()
            let progress = PassageProgress(
                passage: passage,
                strength: strength,
                due: due,
                gradedSessions: reviews.count,
                lastPracticed: lastPracticed,
                lastGrade: reviews.last?.grade
            )
            let isDeclared = declaredSet.contains(passage.first ... passage.last)
            if strength == .unassessed, !isDeclared, record == nil {
                continue
            }

            let weakStreak = Self.trailingWeakStreak(in: reviews)
            let bucket = Self.bucket(for: progress, isDeclared: isDeclared)

            let activeSnooze: Date? = {
                guard let record, let snoozed = record.snoozedUntil, snoozed > currentNow else { return nil }
                // Practicing a snoozed passage after the snooze was set supersedes the snooze.
                if let lastPracticed, lastPracticed > record.modifiedOn {
                    return nil
                }
                return snoozed
            }()

            let isDue: Bool
            let reason: ReviewReason
            if let snoozedUntil = activeSnooze {
                isDue = false
                reason = .snoozedUntil(snoozedUntil)
            } else if let due {
                if due <= currentNow {
                    isDue = true
                    reason = Self.dueReason(progress: progress, weakStreak: weakStreak, due: due, now: currentNow, calendar: calendar)
                } else {
                    isDue = false
                    let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: currentNow), to: calendar.startOfDay(for: due)).day ?? 1)
                    reason = .scheduledInDays(days)
                }
            } else if isDeclared {
                isDue = true
                reason = .declaredUnassessed
            } else {
                isDue = false
                reason = .declaredUnassessed
            }

            let practicedToday = reviews.contains { calendar.isDate($0.date, inSameDayAs: currentNow) }
            rawEntries.append(
                RawEntry(
                    id: record?.id ?? Self.deterministicID(for: passage),
                    recordID: record?.id,
                    passage: passage,
                    progress: progress,
                    bucket: bucket,
                    isDeclared: isDeclared,
                    isDue: isDue,
                    snoozedUntil: activeSnooze,
                    reason: reason,
                    weakStreak: weakStreak,
                    practicedToday: practicedToday
                )
            )
        }

        let completedByBucket: [ReviewBucket: Int] = Dictionary(grouping: rawEntries.filter(\.practicedToday), by: \.bucket)
            .mapValues(\.count)

        let sortedDueRaw = rawEntries
            .filter(\.isDue)
            .sorted { lhs, rhs in
                let lhsRank = Self.urgencyRank(lhs.progress.strength, weakStreak: lhs.weakStreak)
                let rhsRank = Self.urgencyRank(rhs.progress.strength, weakStreak: rhs.weakStreak)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                let lhsDue = lhs.progress.due ?? .distantFuture
                let rhsDue = rhs.progress.due ?? .distantFuture
                if lhsDue != rhsDue { return lhsDue < rhsDue }
                return lhs.passage.first < rhs.passage.first
            }

        var remainingByBucket: [ReviewBucket: Int] = [:]
        for bucket in ReviewBucket.allCases {
            let done = completedByBucket[bucket] ?? 0
            remainingByBucket[bucket] = max(0, budgets.limit(for: bucket) - done)
        }

        let dueItems: [ReviewQueueItem] = sortedDueRaw.map { entry in
            let remaining = remainingByBucket[entry.bucket] ?? 0
            let withinBudget = remaining > 0
            if withinBudget {
                remainingByBucket[entry.bucket] = remaining - 1
            }
            return ReviewQueueItem(
                id: entry.id,
                passageRecordID: entry.recordID,
                passage: entry.passage,
                progress: entry.progress,
                bucket: entry.bucket,
                isDeclared: entry.isDeclared,
                isDue: true,
                isWithinDailyBudget: withinBudget,
                snoozedUntil: nil,
                reason: entry.reason
            )
        }

        let upcomingItems: [ReviewQueueItem] = rawEntries
            .filter { !$0.isDue }
            .sorted { lhs, rhs in
                let lhsDate = lhs.snoozedUntil ?? lhs.progress.due ?? .distantFuture
                let rhsDate = rhs.snoozedUntil ?? rhs.progress.due ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.passage.first < rhs.passage.first
            }
            .map { entry in
                ReviewQueueItem(
                    id: entry.id,
                    passageRecordID: entry.recordID,
                    passage: entry.passage,
                    progress: entry.progress,
                    bucket: entry.bucket,
                    isDeclared: entry.isDeclared,
                    isDue: false,
                    isWithinDailyBudget: false,
                    snoozedUntil: entry.snoozedUntil,
                    reason: entry.reason
                )
            }

        let dueCountByBucket = Dictionary(grouping: dueItems, by: \.bucket).mapValues(\.count)
        let bucketSummaries = ReviewBucket.allCases.map { bucket in
            ReviewBucketSummary(
                bucket: bucket,
                dueCount: dueCountByBucket[bucket] ?? 0,
                completedToday: completedByBucket[bucket] ?? 0,
                dailyBudget: budgets.limit(for: bucket)
            )
        }

        return ReviewQueueSnapshot(
            dueItems: dueItems,
            upcomingItems: upcomingItems,
            bucketSummaries: bucketSummaries,
            declaredRanges: declaredItems.sorted { ($0.range.lowerBound, $0.declaredOn) < ($1.range.lowerBound, $1.declaredOn) }
        )
    }

    /// Computes the Juz → Surah → Ayah memorization map keeping declared and demonstrated states distinct.
    public func mapSummary() async throws -> MemorizationMapSummary {
        let history = try await persistence.history()
        let evidenceBySession = Dictionary(grouping: EvidenceReducer.effective(history.evidence), by: \.sessionID)
        let declaredSet = AyahRangeSet(
            activeDeclaredRanges(from: history.declaredRanges).compactMap(declaredRange)
        )

        var sessionsByPassage: [Passage: [PracticeSessionRecord]] = [:]
        for session in history.sessions {
            guard let first = ayah(session.first), let last = ayah(session.last) else { continue }
            sessionsByPassage[Passage(first, last), default: []].append(session)
        }
        var strengthByPassage: [Passage: PassageStrength] = [:]
        for (passage, sessions) in sessionsByPassage {
            let reviews = sessions.compactMap { session -> PassageScheduler.Review? in
                guard let grade = EvidenceReducer.grade(of: evidenceBySession[session.id] ?? []) else { return nil }
                return PassageScheduler.Review(date: session.endedOn ?? session.startedOn, grade: grade)
            }
            strengthByPassage[passage] = scheduler.schedule(reviews).strength
        }

        let allVerses = quran.verses
        var stateByVerse: [MemorizationVerse: AyahMemorizationState] = [:]
        stateByVerse.reserveCapacity(allVerses.count)
        for verse in allVerses {
            let key = Self.verse(verse)
            stateByVerse[key] = declaredSet.contains(verse) ? .declaredUnassessed : .notMemorized
        }

        // Apply demonstrated evidence chronologically so latest recall governs each ayah.
        let orderedSessions = history.sessions.sorted { ($0.endedOn ?? $0.startedOn) < ($1.endedOn ?? $1.startedOn) }
        for session in orderedSessions {
            guard let first = ayah(session.first), let last = ayah(session.last) else { continue }
            let passage = Passage(first, last)
            let records = evidenceBySession[session.id] ?? []
            guard !records.isEmpty else { continue }
            let passageStrength = strengthByPassage[passage] ?? .learning
            let byVerse = Dictionary(grouping: records.filter { $0.outcome != .skipped }, by: \.verse)
            for (verseKey, verseRecords) in byVerse {
                if verseRecords.contains(where: { $0.outcome == .revealed }) {
                    stateByVerse[verseKey] = .learning
                } else if verseRecords.contains(where: {
                    [.mistake, .hint, .selfCorrected].contains($0.outcome) || $0.assistance > 0
                }) {
                    stateByVerse[verseKey] = .weak
                } else {
                    stateByVerse[verseKey] = switch passageStrength {
                    case .strong: .strong
                    case .weak: .weak
                    case .learning, .unassessed: .learning
                    }
                }
            }
        }

        var totalCounts: [AyahMemorizationState: Int] = [:]
        var totalDeclared = 0
        var totalDemonstrated = 0

        let suraSummaries: [SuraMemorizationSummary] = quran.suras.map { sura in
            let verses = sura.verses
            var states: [AyahMemorizationState] = []
            states.reserveCapacity(verses.count)
            var counts: [AyahMemorizationState: Int] = [:]
            var declaredCount = 0
            var demonstratedCount = 0
            for verse in verses {
                let state = stateByVerse[Self.verse(verse)] ?? .notMemorized
                states.append(state)
                counts[state, default: 0] += 1
                totalCounts[state, default: 0] += 1
                if declaredSet.contains(verse) {
                    declaredCount += 1
                    totalDeclared += 1
                }
                if state.isDemonstrated {
                    demonstratedCount += 1
                    totalDemonstrated += 1
                }
            }
            return SuraMemorizationSummary(
                sura: sura,
                totalVerses: verses.count,
                declaredCount: declaredCount,
                demonstratedCount: demonstratedCount,
                counts: counts,
                ayahStates: states
            )
        }

        let juzSummaries: [JuzMemorizationSummary] = quran.juzs.map { juz in
            let verses = juz.verses
            var juzCounts: [AyahMemorizationState: Int] = [:]
            var juzDeclared = 0
            var juzDemonstrated = 0
            var slices: [JuzSuraSlice] = []

            var currentSura = verses[0].sura
            var sliceStart = verses[0].ayah
            var sliceEnd = verses[0].ayah
            var sliceStates: [AyahMemorizationState] = []
            var sliceCounts: [AyahMemorizationState: Int] = [:]
            var sliceDeclared = 0
            var sliceDemonstrated = 0

            func flushSlice() {
                slices.append(
                    JuzSuraSlice(
                        juzNumber: juz.juzNumber,
                        sura: currentSura,
                        firstAyah: sliceStart,
                        lastAyah: sliceEnd,
                        declaredCount: sliceDeclared,
                        demonstratedCount: sliceDemonstrated,
                        counts: sliceCounts,
                        ayahStates: sliceStates
                    )
                )
            }

            for verse in verses {
                if verse.sura != currentSura {
                    flushSlice()
                    currentSura = verse.sura
                    sliceStart = verse.ayah
                    sliceStates = []
                    sliceCounts = [:]
                    sliceDeclared = 0
                    sliceDemonstrated = 0
                }
                sliceEnd = verse.ayah
                let state = stateByVerse[Self.verse(verse)] ?? .notMemorized
                sliceStates.append(state)
                sliceCounts[state, default: 0] += 1
                juzCounts[state, default: 0] += 1
                if declaredSet.contains(verse) {
                    sliceDeclared += 1
                    juzDeclared += 1
                }
                if state.isDemonstrated {
                    sliceDemonstrated += 1
                    juzDemonstrated += 1
                }
            }
            flushSlice()

            return JuzMemorizationSummary(
                juz: juz,
                totalVerses: verses.count,
                declaredCount: juzDeclared,
                demonstratedCount: juzDemonstrated,
                counts: juzCounts,
                suras: slices
            )
        }

        return MemorizationMapSummary(
            totalVerses: allVerses.count,
            declaredVerseCount: totalDeclared,
            demonstratedVerseCount: totalDemonstrated,
            counts: totalCounts,
            juzs: juzSummaries,
            suras: suraSummaries
        )
    }

    // MARK: - Spot tests (H4)

    /// Resolves the canonical verse pool for a spot-test source (memorized, custom, or preset).
    public func spotTestPool(
        for source: SpotTestSource,
        calendar: Calendar = .current
    ) async throws -> AyahRangeSet {
        switch source {
        case .custom(let rangeSet):
            return AyahRangeSet(rangeSet.ranges.map(canonicalRange))

        case .memorized:
            return try await allMemorizedAndPracticedPool()

        case .preset(let preset):
            return try await presetPool(preset, calendar: calendar)
        }
    }

    /// Generates seeded random-start spot-test questions for `configuration`.
    public func generateSpotTest(
        configuration: SpotTestConfiguration,
        lineSpans: [AyahNumber: VerseLineSpan] = [:],
        calendar: Calendar = .current
    ) async throws -> [SpotTestQuestion] {
        let pool = try await spotTestPool(for: configuration.source, calendar: calendar)
        guard !pool.isEmpty else { return [] }
        let targetCount: Int = switch configuration.limit.clamped {
        case .count(let n):
            n
        case .timer:
            min(max(20, pool.verseCount), 60)
        }
        return SpotTestSampler.sampleQuestions(
            from: pool,
            length: configuration.questionLength,
            count: targetCount,
            seed: configuration.seed,
            lineSpans: lineSpans
        )
    }

    /// Records completed spot-test questions into memorization history.
    ///
    /// **Temporary tests never change history:** when `isTemporary` is `true`, no session or
    /// evidence is written and an empty array is returned.
    @discardableResult
    public func recordSpotTest(
        _ results: [SpotTestQuestionResult],
        startedOn: Date,
        isTemporary: Bool
    ) async throws -> [UUID] {
        guard !isTemporary else { return [] }
        var savedIDs: [UUID] = []
        for result in results {
            let recalls: [VerseRecall] = if result.skipped {
                result.question.verses.map { verse in
                    VerseRecall(
                        verse: verse,
                        outcome: .skipped,
                        assistance: 0,
                        mistakenWords: [],
                        provenance: .manual
                    )
                }
            } else {
                result.verseOutcomes.map { item in
                    VerseRecall(
                        verse: item.verse,
                        outcome: item.outcome,
                        assistance: item.assistance,
                        mistakenWords: item.mistakenWords.sorted(),
                        provenance: .manual
                    )
                }
            }
            guard !recalls.isEmpty else { continue }
            let id = try await recordSession(result.question.passage, startedOn: startedOn, recalls: recalls)
            savedIDs.append(id)
        }
        return savedIDs
    }

    // MARK: Private

    private static let manzilThresholdDays: TimeInterval = 14 * 86400
    private static let recentPresetWindowDays: TimeInterval = 14 * 86400

    private func allMemorizedAndPracticedPool() async throws -> AyahRangeSet {
        let history = try await persistence.history()
        let evidenceBySession = Dictionary(grouping: EvidenceReducer.effective(history.evidence), by: \.sessionID)
        var ranges: [ClosedRange<AyahNumber>] = activeDeclaredRanges(from: history.declaredRanges)
            .compactMap(declaredRange)
        ranges.append(contentsOf: activePassages(from: history.passages).compactMap(passageRange))
        for session in history.sessions {
            guard EvidenceReducer.grade(of: evidenceBySession[session.id] ?? []) != nil,
                  let first = ayah(session.first),
                  let last = ayah(session.last)
            else { continue }
            ranges.append(first ... last)
        }
        return AyahRangeSet(ranges)
    }

    private func presetPool(_ preset: SpotTestPreset, calendar: Calendar) async throws -> AyahRangeSet {
        let currentNow = now()
        let queue = try await reviewQueue(calendar: calendar)
        let allItems = queue.dueItems + queue.upcomingItems

        switch preset {
        case .due:
            return AyahRangeSet(queue.dueItems.map { $0.passage.first ... $0.passage.last })

        case .weakest:
            let genuinelyWeak = allItems.filter { item in
                item.progress.strength == .weak
                    || (item.progress.strength == .learning && item.progress.lastGrade != .good)
            }
            if !genuinelyWeak.isEmpty {
                return AyahRangeSet(genuinelyWeak.map { $0.passage.first ... $0.passage.last })
            }
            let learning = allItems.filter { $0.progress.strength == .learning }
            return AyahRangeSet(learning.map { $0.passage.first ... $0.passage.last })

        case .warmUp:
            let strong = allItems.filter { $0.progress.strength == .strong }
            if !strong.isEmpty {
                return AyahRangeSet(strong.map { $0.passage.first ... $0.passage.last })
            }
            return try await allMemorizedAndPracticedPool()

        case .recent, .old:
            let history = try await persistence.history()
            let declaredItems = activeDeclaredRanges(from: history.declaredRanges)
            var candidates: [(range: ClosedRange<AyahNumber>, lastActivity: Date)] = []
            for item in allItems {
                let range = item.passage.first ... item.passage.last
                let declaredDate = declaredItems.compactMap { record -> Date? in
                    guard let r = declaredRange(record), r.lowerBound <= range.upperBound, r.upperBound >= range.lowerBound else {
                        return nil
                    }
                    return record.declaredOn
                }.max()
                let activity = item.progress.lastPracticed ?? declaredDate ?? Date.distantPast
                candidates.append((range: range, lastActivity: activity))
            }
            guard !candidates.isEmpty else { return AyahRangeSet() }

            let cutoff = currentNow.addingTimeInterval(-Self.recentPresetWindowDays)
            if preset == .recent {
                let recent = candidates.filter { $0.lastActivity >= cutoff }
                if !recent.isEmpty {
                    return AyahRangeSet(recent.map(\.range))
                }
                let sorted = candidates.sorted { $0.lastActivity > $1.lastActivity }
                let take = max(1, (sorted.count + 1) / 2)
                return AyahRangeSet(sorted.prefix(take).map(\.range))
            } else {
                let older = candidates.filter { $0.lastActivity < cutoff }
                if !older.isEmpty {
                    return AyahRangeSet(older.map(\.range))
                }
                let sorted = candidates.sorted { $0.lastActivity < $1.lastActivity }
                let take = max(1, (sorted.count + 1) / 2)
                return AyahRangeSet(sorted.prefix(take).map(\.range))
            }
        }
    }

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

    private func canonicalRange(_ range: ClosedRange<AyahNumber>) -> ClosedRange<AyahNumber> {
        let lower = ayah(Self.verse(range.lowerBound)) ?? range.lowerBound
        let upper = ayah(Self.verse(range.upperBound)) ?? range.upperBound
        return min(lower, upper) ... max(lower, upper)
    }

    private func canonicalPassage(_ passage: Passage) -> Passage {
        let first = ayah(Self.verse(passage.first)) ?? passage.first
        let last = ayah(Self.verse(passage.last)) ?? passage.last
        return Passage(first, last)
    }

    private func declaredRange(_ record: MemorizedRangeRecord) -> ClosedRange<AyahNumber>? {
        guard let first = ayah(record.first), let last = ayah(record.last), first <= last else { return nil }
        return first ... last
    }

    private func passageRange(_ record: PassageRecord) -> ClosedRange<AyahNumber>? {
        guard let first = ayah(record.first), let last = ayah(record.last), first <= last else { return nil }
        return first ... last
    }

    private func activeDeclaredRanges(from records: [MemorizedRangeRecord]) -> [MemorizedRangeRecord] {
        var byID: [UUID: MemorizedRangeRecord] = [:]
        var order: [UUID] = []
        for record in records {
            if var existing = byID[record.id] {
                existing.removedOn = existing.removedOn ?? record.removedOn
                byID[record.id] = existing
            } else {
                byID[record.id] = record
                order.append(record.id)
            }
        }
        return order.compactMap { byID[$0] }.filter { $0.removedOn == nil }
    }

    private func activePassages(from records: [PassageRecord]) -> [PassageRecord] {
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

    private func matchingPassageRecord(id: UUID?, passage: Passage, in active: [PassageRecord]) -> PassageRecord? {
        if let id, let byID = active.first(where: { $0.id == id }) {
            return byID
        }
        return active.first { record in
            guard let first = ayah(record.first), let last = ayah(record.last) else { return false }
            return Passage(first, last) == passage
        }
    }

    private static func trailingWeakStreak(in sortedReviews: [PassageScheduler.Review]) -> Int {
        var count = 0
        for review in sortedReviews.reversed() {
            if review.grade == .good {
                break
            }
            count += 1
        }
        return count
    }

    private static func bucket(for progress: PassageProgress, isDeclared: Bool) -> ReviewBucket {
        switch progress.strength {
        case .learning:
            return .sabaq
        case .weak:
            return .sabqi
        case .strong:
            if let due = progress.due, let last = progress.lastPracticed,
               due.timeIntervalSince(last) < manzilThresholdDays
            {
                return .sabqi
            }
            return .manzil
        case .unassessed:
            return isDeclared ? .manzil : .sabaq
        }
    }

    private static func dueReason(
        progress: PassageProgress,
        weakStreak: Int,
        due: Date,
        now: Date,
        calendar: Calendar
    ) -> ReviewReason {
        if weakStreak >= 1, progress.strength == .weak || (progress.strength == .learning && weakStreak >= 2) {
            return .weakSessions(weakStreak)
        }
        if progress.strength == .learning {
            return .learning
        }
        let overdueDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: due), to: calendar.startOfDay(for: now)).day ?? 0
        if overdueDays >= 1 {
            return .overdueDays(overdueDays)
        }
        return .dueToday
    }

    private static func urgencyRank(_ strength: PassageStrength, weakStreak: Int) -> Int {
        switch strength {
        case .weak: return 0
        case .learning: return weakStreak >= 2 ? 0 : 1
        case .strong: return 2
        case .unassessed: return 3
        }
    }

    /// Stable deterministic UUID for ad-hoc practiced passages without a stored `PassageRecord`.
    private static func deterministicID(for passage: Passage) -> UUID {
        let fS = UInt16(passage.first.sura.suraNumber)
        let fA = UInt16(passage.first.ayah)
        let lS = UInt16(passage.last.sura.suraNumber)
        let lA = UInt16(passage.last.ayah)
        let bytes: uuid_t = (
            0x48, 0x33, // "H3"
            UInt8(fS >> 8), UInt8(fS & 0xFF),
            UInt8(fA >> 8), UInt8(fA & 0xFF),
            0x40, UInt8(lS >> 8),
            0x80, UInt8(lS & 0xFF),
            UInt8(lA >> 8), UInt8(lA & 0xFF),
            0x00, 0x00, 0x00, 0x01
        )
        return UUID(uuid: bytes)
    }

    private func evidenceRecord(
        session: UUID,
        verse: AyahNumber,
        word: Int,
        _ outcome: RecallOutcome,
        _ assistance: Int,
        _ provenance: EvidenceProvenance,
        _ date: Date
    ) -> RecallEvidenceRecord {
        RecallEvidenceRecord(
            id: makeID(),
            sessionID: session,
            verse: Self.verse(verse),
            word: word,
            outcome: outcome,
            assistance: assistance,
            provenance: provenance,
            recordedOn: date
        )
    }
}
