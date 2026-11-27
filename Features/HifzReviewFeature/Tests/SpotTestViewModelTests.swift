//
//  SpotTestViewModelTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import MemorizationPersistence
import MemorizationService
import QuranKit
import QuranResources
import TestResources
import XCTest
@testable import HifzReviewFeature

@MainActor
final class SpotTestViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        persistence = CoreDataMemorizationPersistence(stack: store.stack())
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = utc
        clock = Clock()
        service = MemorizationService(persistence: persistence, now: { [clock] in clock!.now })
        textLoader = SpotTestTextLoader(
            uthmaniDatabase: QuranResources.quranUthmaniV2Database,
            wordByWordDatabase: TestResources.resourceURL("word_by_word.db"),
            ayahInfoDatabase: TestResources.resourceURL("hafs_1405_ayahinfo.db")
        )
    }

    override func tearDown() {
        service = nil
        persistence = nil
        store = nil
        super.tearDown()
    }

    func testFullSpotTestRecordsHintsMistakesForgotSkipsAndScoresAccurately() async throws {
        try await service.declareMemorized(v(112, 1) ... v(112, 4))
        var practiced: [Passage] = []
        var opened: [AyahNumber] = []

        let vm = SpotTestViewModel(
            service: service,
            textLoader: textLoader,
            calendar: calendar,
            now: { [clock] in clock!.now },
            makeSeed: { 42 },
            practicePassage: { practiced.append($0) },
            openAyah: { opened.append($0) }
        )

        await vm.refreshPools()
        XCTAssertEqual(vm.memorizedVerseCount, 4)
        XCTAssertTrue(vm.canStart)

        vm.ayahCount = 1
        vm.questionCount = 4
        vm.startCue = .firstWord
        vm.isTemporary = false
        await vm.startTest()

        XCTAssertEqual(vm.screenPhase, .testing)
        XCTAssertEqual(vm.questions.count, 4)
        // First cue reveals only 1 word (hidden words are never in visiblePromptLines).
        XCTAssertEqual(vm.visiblePromptLines.first?.words.count, 1)

        // Q1: Clean unassisted perfect.
        vm.revealAndGrade()
        XCTAssertEqual(vm.questionPhase, .grading)
        await vm.gradeCorrect()

        // Q2: First letter hint + Next word peek -> graded Correct (recorded as .hint).
        vm.showFirstLetterHint()
        XCTAssertNotNil(vm.hintLetter)
        vm.revealNextWord()
        XCTAssertNil(vm.hintLetter)
        XCTAssertEqual(vm.currentQuestionHints, 2)
        vm.revealAndGrade()
        await vm.gradeCorrect()

        // Q3: Mark 1 specific mistaken word -> granular Word Recall.
        let q3Verse = try XCTUnwrap(vm.currentQuestion?.verses.first)
        let q3Units = try XCTUnwrap(vm.loadedWords[q3Verse])
        vm.revealAndGrade()
        vm.beginMarkingMistakes()
        vm.toggleMistakenWord(verse: q3Verse, wordNumbers: q3Units[0].wordNumbers)
        await vm.saveMistakesAndAdvance()

        // Q4: Skip -> finishes test and computes score report.
        await vm.skipQuestion()

        guard case .results(let report) = vm.screenPhase else {
            return XCTFail("Expected results phase, got \(vm.screenPhase)")
        }
        XCTAssertTrue(vm.savedToHistory)
        XCTAssertFalse(vm.saveFailed)
        XCTAssertEqual(report.assessedQuestions, 3)
        XCTAssertEqual(report.skippedQuestions, 1)
        XCTAssertEqual(report.strictPassedQuestions, 1)
        XCTAssertEqual(report.strictScore, SpotTestRatio(numerator: 1, denominator: 3))
        XCTAssertEqual(report.coverageScore, SpotTestRatio(numerator: 3, denominator: 4))
        XCTAssertEqual(report.assistanceRate, SpotTestRatio(numerator: 1, denominator: 3))
        XCTAssertEqual(report.totalHints, 2)
        XCTAssertEqual(report.bestStreak, 1)
        XCTAssertGreaterThan(report.assessedWords, report.recalledWords)
        XCTAssertEqual(report.assessedWords - report.recalledWords, q3Units[0].wordNumbers.count)

        // History has 4 sessions saved (including hint, word mistake, and skip).
        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 4)
        XCTAssertTrue(history.evidence.contains { $0.outcome == .hint && $0.assistance == 2 })
        XCTAssertTrue(history.evidence.contains { $0.outcome == .mistake && $0.word == q3Units[0].wordNumbers[0] })
        XCTAssertTrue(history.evidence.contains { $0.outcome == .skipped })

        // Practice and Reader navigation hooks work from results.
        vm.practice(vm.questions[0].passage)
        vm.openInReader(vm.questions[0].passage.first)
        XCTAssertEqual(practiced, [vm.questions[0].passage])
        XCTAssertEqual(opened, [vm.questions[0].passage.first])
    }

    func testTemporaryTestLeavesHistoryUnchangedAndReplayUsesSameSeed() async throws {
        try await service.declareMemorized(v(112, 1) ... v(113, 5))
        let historyBefore = try await persistence.history()

        let vm = SpotTestViewModel(
            service: service,
            textLoader: textLoader,
            calendar: calendar,
            now: { [clock] in clock!.now },
            makeSeed: { 777 },
            practicePassage: { _ in },
            openAyah: { _ in }
        )

        vm.setCustomRanges(AyahRangeSet(v(112, 1) ... v(112, 4)))
        vm.ayahCount = 2
        vm.questionCount = 2
        vm.hideLocation = true
        vm.startCue = .referenceOnly
        vm.isTemporary = true

        await vm.startTest()
        let firstRunQuestions = vm.questions
        XCTAssertEqual(vm.activeConfiguration.effectiveStartCue, .firstWord)
        XCTAssertEqual(vm.visiblePromptLines.first?.words.count, 1)

        vm.revealAndGrade()
        await vm.gradeForgot()
        await vm.endTestEarly()

        guard case .results(let report) = vm.screenPhase else {
            return XCTFail("Expected results phase")
        }
        XCTAssertFalse(vm.savedToHistory)
        XCTAssertEqual(report.assessedQuestions, 1)
        XCTAssertEqual(report.revealedVerses, firstRunQuestions[0].verses.count)
        XCTAssertEqual(report.coverageScore, SpotTestRatio(numerator: 1, denominator: 2))
        XCTAssertEqual(report.wordRecallScore, SpotTestRatio(numerator: 0, denominator: report.assessedWords))

        let historyAfter = try await persistence.history()
        XCTAssertEqual(historyAfter, historyBefore)

        // Replay reproduces the exact same seeded questions.
        await vm.replaySameQuestions()
        XCTAssertEqual(vm.screenPhase, .testing)
        XCTAssertEqual(vm.questions, firstRunQuestions)
    }

    func testTimedTestAndLineLengthSamplingWithRealAyahInfoDatabase() async {
        let vm = SpotTestViewModel(
            service: service,
            textLoader: textLoader,
            calendar: calendar,
            now: { [clock] in clock!.now },
            makeSeed: { 101 },
            practicePassage: { _ in },
            openAyah: { _ in }
        )

        vm.setCustomRanges(AyahRangeSet(v(112, 1) ... v(114, 6)))
        vm.lengthUnit = .lines
        vm.lineCount = 2
        vm.limitMode = .timer
        vm.timerMinutes = 1
        vm.isTemporary = true

        await vm.startTest()
        XCTAssertEqual(vm.screenPhase, .testing)
        XCTAssertTrue(vm.isTimedTest)
        XCTAssertEqual(vm.remainingSeconds, 60)
        XCTAssertTrue(vm.questions.allSatisfy { ($0.targetLineCount ?? 0) >= 1 })

        // Expire timer before any question is answered -> all ratios nil (0 denominator).
        for _ in 0 ..< 60 {
            await vm.tickTimerOnce()
        }
        guard case .results(let report) = vm.screenPhase else {
            return XCTFail("Expected timer expiration to transition to results")
        }
        XCTAssertNil(report.strictScore)
        XCTAssertNil(report.wordRecallScore)
        XCTAssertNil(report.coverageScore)
        XCTAssertNil(report.assistanceRate)
    }

    // MARK: Private

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    private let quran = Quran.hafsMadani1405
    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var calendar: Calendar!
    private var clock: Clock!
    private var service: MemorizationService!
    private var textLoader: SpotTestTextLoader!

    private func v(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }
}
