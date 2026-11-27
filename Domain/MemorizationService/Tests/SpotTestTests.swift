//
//  SpotTestTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import MemorizationPersistence
import QuranKit
import XCTest
@testable import MemorizationService

final class SpotTestTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        persistence = CoreDataMemorizationPersistence(stack: store.stack())
        clock = Clock()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = utc
        service = MemorizationService(persistence: persistence, now: { [clock] in clock!.now })
    }

    override func tearDown() {
        service = nil
        persistence = nil
        store = nil
        super.tearDown()
    }

    func testSeededSamplerIsDeterministicAndRespectsNonContiguousRanges() {
        // Two disjoint suras: Al-Fatihah (1:1-7) and Al-Ikhlas..An-Nas (112:1-114:6).
        let pool = AyahRangeSet([
            v(1, 1) ... v(1, 7),
            v(112, 1) ... v(114, 6),
        ])

        let first = SpotTestSampler.sampleQuestions(from: pool, length: .ayahs(3), count: 5, seed: 42)
        let second = SpotTestSampler.sampleQuestions(from: pool, length: .ayahs(3), count: 5, seed: 42)
        let differentSeed = SpotTestSampler.sampleQuestions(from: pool, length: .ayahs(3), count: 5, seed: 99)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 5)
        XCTAssertNotEqual(first.map(\.passage), differentSeed.map(\.passage))

        // Every sampled question stays wholly inside the pool (never bridges across 1:7 -> 112:1)
        // and has distinct start verses.
        let starts = Set(first.map(\.passage.first))
        XCTAssertEqual(starts.count, first.count)
        for question in first {
            XCTAssertTrue(pool.contains(question.passage.first ... question.passage.last))
            XCTAssertLessThanOrEqual(question.verses.count, 3)
            XCTAssertNil(question.targetLineCount)
        }
    }

    func testSamplerHandlesSmallPoolAndEmptyPool() {
        XCTAssertEqual(
            SpotTestSampler.sampleQuestions(from: AyahRangeSet(), length: .ayahs(3), count: 5, seed: 1),
            []
        )

        let smallPool = AyahRangeSet(v(112, 1) ... v(112, 4))
        let questions = SpotTestSampler.sampleQuestions(from: smallPool, length: .ayahs(3), count: 10, seed: 7)
        // Only 4 distinct start verses exist in Al-Ikhlas.
        XCTAssertEqual(questions.count, 4)
        XCTAssertEqual(Set(questions.map(\.passage.first)).count, 4)
    }

    func testLineLengthSamplingUsesLineSpansAndFallsBackWithoutGeometry() throws {
        let pool = AyahRangeSet(v(112, 1) ... v(112, 4))
        // Simulate page 604 lines: 112:1-2 share line 3, 112:3 is line 4, 112:4 is line 5.
        let spans: [AyahNumber: VerseLineSpan] = [
            v(112, 1): VerseLineSpan(page: 604, firstLine: 3, lastLine: 3),
            v(112, 2): VerseLineSpan(page: 604, firstLine: 3, lastLine: 3),
            v(112, 3): VerseLineSpan(page: 604, firstLine: 4, lastLine: 4),
            v(112, 4): VerseLineSpan(page: 604, firstLine: 5, lastLine: 5),
        ]

        let withGeometry = SpotTestSampler.sampleQuestions(
            from: pool,
            length: .lines(2),
            count: 4,
            seed: 12,
            lineSpans: spans
        )
        let fromAyah1 = try XCTUnwrap(withGeometry.first { $0.passage.first == v(112, 1) })
        // Starting at 112:1 (line 3), 112:2 is still line 3, so 112:3 (line 4) is needed to cover 2 lines.
        XCTAssertEqual(fromAyah1.passage, Passage(v(112, 1), v(112, 3)))
        XCTAssertEqual(fromAyah1.targetLineCount, 2)

        // Fallback without lineSpans still produces valid spans with non-nil targetLineCount.
        let fallback = SpotTestSampler.sampleQuestions(
            from: pool,
            length: .lines(2),
            count: 2,
            seed: 12
        )
        XCTAssertEqual(fallback.count, 2)
        XCTAssertTrue(fallback.allSatisfy { ($0.targetLineCount ?? 0) >= 1 })
    }

    func testEffectiveStartCuePreventsBlankCardWhenLocationHidden() {
        let config = SpotTestConfiguration(
            source: .memorized,
            questionLength: .ayahs(2),
            limit: .count(5),
            startCue: .referenceOnly,
            hideLocation: true,
            isTemporary: false,
            seed: 1
        )
        XCTAssertEqual(config.effectiveStartCue, .firstWord)

        var shown = config
        shown.hideLocation = false
        XCTAssertEqual(shown.effectiveStartCue, .referenceOnly)
    }

    func testScorerReturnsNilWhenDenominatorsAreZero() {
        let empty = SpotTestScorer.score(results: [], plannedQuestions: 0)
        XCTAssertNil(empty.strictScore)
        XCTAssertNil(empty.wordRecallScore)
        XCTAssertNil(empty.coverageScore)
        XCTAssertNil(empty.assistanceRate)
        XCTAssertEqual(empty.bestStreak, 0)

        let emptyTimer = SpotTestScorer.score(results: [], plannedQuestions: nil)
        XCTAssertNil(emptyTimer.strictScore)
        XCTAssertNil(emptyTimer.wordRecallScore)
        XCTAssertNil(emptyTimer.coverageScore)
        XCTAssertNil(emptyTimer.assistanceRate)

        let q1 = SpotTestQuestion(id: 0, passage: Passage(v(112, 1), v(112, 2)))
        let allSkipped = SpotTestScorer.score(
            results: [SpotTestQuestionResult(question: q1, verseOutcomes: [], skipped: true)],
            plannedQuestions: 3
        )
        XCTAssertNil(allSkipped.strictScore)
        XCTAssertNil(allSkipped.wordRecallScore)
        XCTAssertNil(allSkipped.assistanceRate)
        XCTAssertEqual(allSkipped.coverageScore, SpotTestRatio(numerator: 0, denominator: 3))
        XCTAssertEqual(allSkipped.skippedQuestions, 1)
    }

    func testScorerComputesStrictWordRecallCoverageAssistanceAndStreak() {
        let q1 = SpotTestQuestion(id: 0, passage: Passage(v(112, 1), v(112, 1)))
        let q2 = SpotTestQuestion(id: 1, passage: Passage(v(112, 2), v(112, 2)))
        let q3 = SpotTestQuestion(id: 2, passage: Passage(v(112, 3), v(112, 3)))
        let q4 = SpotTestQuestion(id: 3, passage: Passage(v(112, 4), v(112, 4)))
        let q5 = SpotTestQuestion(id: 4, passage: Passage(v(113, 1), v(113, 1)))

        let results: [SpotTestQuestionResult] = [
            // Q1: error-free unassisted (4/4 words) -> streak 1
            SpotTestQuestionResult(
                question: q1,
                verseOutcomes: [SpotTestVerseOutcome(verse: v(112, 1), totalWords: 4, outcome: .correct)]
            ),
            // Q2: error-free unassisted (2/2 words) -> streak 2
            SpotTestQuestionResult(
                question: q2,
                verseOutcomes: [SpotTestVerseOutcome(verse: v(112, 2), totalWords: 2, outcome: .correct)]
            ),
            // Q3: 1 hint used, correct after hint (4/4 words, assisted, NOT strict) -> streak 0
            SpotTestQuestionResult(
                question: q3,
                verseOutcomes: [SpotTestVerseOutcome(verse: v(112, 3), totalWords: 4, outcome: .hint, assistance: 2)]
            ),
            // Q4: 1 mistaken word out of 5 words (4/5 recalled, unaided, NOT strict) -> streak 0
            SpotTestQuestionResult(
                question: q4,
                verseOutcomes: [SpotTestVerseOutcome(verse: v(112, 4), totalWords: 5, outcome: .mistake, mistakenWords: [3])]
            ),
            // Q5: skipped -> excluded from strict & word recall denominators, counted in skipped
            SpotTestQuestionResult(
                question: q5,
                verseOutcomes: [],
                skipped: true
            ),
        ]

        // Planned 6 questions (e.g. ended 1 early after 5 presented: 4 assessed, 1 skipped).
        let report = SpotTestScorer.score(results: results, plannedQuestions: 6)

        XCTAssertEqual(report.assessedQuestions, 4)
        XCTAssertEqual(report.skippedQuestions, 1)
        XCTAssertEqual(report.strictPassedQuestions, 2)
        XCTAssertEqual(report.assistedQuestions, 1)
        XCTAssertEqual(report.unaidedQuestions, 3)
        XCTAssertEqual(report.totalHints, 2)
        XCTAssertEqual(report.assessedWords, 15)
        XCTAssertEqual(report.recalledWords, 14)
        XCTAssertEqual(report.bestStreak, 2)

        XCTAssertEqual(report.strictScore, SpotTestRatio(numerator: 2, denominator: 4))
        XCTAssertEqual(report.wordRecallScore, SpotTestRatio(numerator: 14, denominator: 15))
        XCTAssertEqual(report.coverageScore, SpotTestRatio(numerator: 4, denominator: 6))
        XCTAssertEqual(report.assistanceRate, SpotTestRatio(numerator: 1, denominator: 4))
    }

    func testPresetsSelectDistinctPoolsForWarmUpWeakestDueRecentAndOld() async throws {
        // Day 0: Declare Al-Ikhlas (112) and Al-Falaq (113), practice Al-Falaq cleanly twice so it becomes strong & old.
        let p112 = Passage(v(112, 1), v(112, 4))
        let p113 = Passage(v(113, 1), v(113, 5))
        let p114 = Passage(v(114, 1), v(114, 6))

        try await service.declareMemorized(v(112, 1) ... v(114, 6))

        // Practice p113 cleanly on Day 0 and Day 3 -> strong, long review interval.
        try await service.recordSession(
            p113,
            startedOn: clock.now,
            recalls: p113.verses.map { VerseRecall(verse: $0, outcome: .correct) }
        )
        clock.advance(days: 3)
        try await service.recordSession(
            p113,
            startedOn: clock.now,
            recalls: p113.verses.map { VerseRecall(verse: $0, outcome: .correct) }
        )

        // Advance to Day 25 and Day 28: p113 is old (> 14 days) and overdue;
        // practice p112 cleanly twice (Day 25 & Day 28) -> strong, recent, and not due yet.
        // Practice p114 with a mistake on Day 28 -> recent, weak, due.
        clock.advance(days: 22)
        try await service.recordSession(
            p112,
            startedOn: clock.now,
            recalls: p112.verses.map { VerseRecall(verse: $0, outcome: .correct) }
        )
        clock.advance(days: 3)
        try await service.recordSession(
            p112,
            startedOn: clock.now,
            recalls: p112.verses.map { VerseRecall(verse: $0, outcome: .correct) }
        )
        try await service.recordSession(
            p114,
            startedOn: clock.now,
            recalls: [VerseRecall(verse: v(114, 1), outcome: .mistake, mistakenWords: [2])]
                + p114.verses.dropFirst().map { VerseRecall(verse: $0, outcome: .correct) }
        )

        let memorized = try await service.spotTestPool(for: .memorized, calendar: calendar)
        XCTAssertEqual(memorized, AyahRangeSet(v(112, 1) ... v(114, 6)))

        let warmUp = try await service.spotTestPool(for: .preset(.warmUp), calendar: calendar)
        XCTAssertTrue(warmUp.contains(v(112, 1) ... v(112, 4)))
        XCTAssertTrue(warmUp.contains(v(113, 1) ... v(113, 5)))
        XCTAssertFalse(warmUp.contains(v(114, 1)))

        let weakest = try await service.spotTestPool(for: .preset(.weakest), calendar: calendar)
        XCTAssertEqual(weakest, AyahRangeSet(v(114, 1) ... v(114, 6)))

        let due = try await service.spotTestPool(for: .preset(.due), calendar: calendar)
        XCTAssertTrue(due.contains(v(113, 1) ... v(113, 5)))
        XCTAssertFalse(due.contains(v(112, 1)))

        let recent = try await service.spotTestPool(for: .preset(.recent), calendar: calendar)
        XCTAssertTrue(recent.contains(v(112, 1) ... v(112, 4)))
        XCTAssertTrue(recent.contains(v(114, 1) ... v(114, 6)))
        XCTAssertFalse(recent.contains(v(113, 1)))

        let old = try await service.spotTestPool(for: .preset(.old), calendar: calendar)
        XCTAssertEqual(old, AyahRangeSet(v(113, 1) ... v(113, 5)))
    }

    func testTemporarySpotTestNeverMutatesHistoryAndSavedTestRecordsHintsAndSkips() async throws {
        try await service.declareMemorized(v(112, 1) ... v(112, 4))
        let historyBefore = try await persistence.history()

        let q1 = SpotTestQuestion(id: 0, passage: Passage(v(112, 1), v(112, 2)))
        let q2 = SpotTestQuestion(id: 1, passage: Passage(v(112, 3), v(112, 4)))
        let results: [SpotTestQuestionResult] = [
            SpotTestQuestionResult(
                question: q1,
                verseOutcomes: [
                    SpotTestVerseOutcome(verse: v(112, 1), totalWords: 4, outcome: .hint, assistance: 1),
                    SpotTestVerseOutcome(verse: v(112, 2), totalWords: 2, outcome: .mistake, mistakenWords: [2]),
                ]
            ),
            SpotTestQuestionResult(
                question: q2,
                verseOutcomes: [],
                skipped: true
            ),
        ]

        // Temporary mode: zero writes.
        let tempIDs = try await service.recordSpotTest(results, startedOn: clock.now, isTemporary: true)
        XCTAssertTrue(tempIDs.isEmpty)
        let historyAfterTemp = try await persistence.history()
        XCTAssertEqual(historyAfterTemp, historyBefore)

        // Non-temporary mode: saves both assessed (with hint & mistaken word) and skipped evidence.
        let savedIDs = try await service.recordSpotTest(results, startedOn: clock.now, isTemporary: false)
        XCTAssertEqual(savedIDs.count, 2)

        let historyAfterSave = try await persistence.history()
        XCTAssertEqual(historyAfterSave.sessions.count, 2)
        XCTAssertTrue(historyAfterSave.evidence.contains { $0.verse == MemorizationVerse(sura: 112, ayah: 1) && $0.outcome == .hint && $0.assistance == 1 })
        XCTAssertTrue(historyAfterSave.evidence.contains { $0.verse == MemorizationVerse(sura: 112, ayah: 2) && $0.word == 2 && $0.outcome == .mistake })
        XCTAssertTrue(historyAfterSave.evidence.contains { $0.verse == MemorizationVerse(sura: 112, ayah: 3) && $0.outcome == .skipped })
        XCTAssertTrue(historyAfterSave.evidence.contains { $0.verse == MemorizationVerse(sura: 112, ayah: 4) && $0.outcome == .skipped })

        // Skipped passage q2 stays unassessed in FSRS progress (all-skipped grade is nil).
        let q2Progress = try await service.progress(of: q2.passage)
        XCTAssertEqual(q2Progress.strength, .unassessed)
        XCTAssertEqual(q2Progress.gradedSessions, 0)
    }

    // MARK: Private

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_700_000_000)

        func advance(days: Double) {
            now = now.addingTimeInterval(days * 86400)
        }
    }

    private let quran = Quran.hafsMadani1405
    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var clock: Clock!
    private var calendar: Calendar!
    private var service: MemorizationService!

    private func v(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }
}
