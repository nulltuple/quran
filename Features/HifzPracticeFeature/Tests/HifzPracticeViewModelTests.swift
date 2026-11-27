//
//  HifzPracticeViewModelTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import Foundation
import MemorizationPersistence
import MemorizationService
import QuranAnnotations
import QuranKit
import QuranResources
import RecitationRecognition
import TestResources
import XCTest
@testable import HifzPracticeFeature

@MainActor
final class HifzPracticeViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        persistence = CoreDataMemorizationPersistence(stack: store.stack())
        suiteName = "HifzPracticeViewModelTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        stateStore = PracticeStateStore(userDefaults: userDefaults)
        masks = []
        listened = []
        stoppedListening = 0
        closed = false
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        stateStore = nil
        userDefaults = nil
        persistence = nil
        store = nil
        super.tearDown()
    }

    func testPracticeHidesTheAyahsRevealsOnRequestAndSavesTheGrades() async throws {
        let sut = makeSUT()
        await sut.start()
        XCTAssertEqual(sut.phase, .reciting)
        XCTAssertEqual(masks.last, PracticeMask(hiddenVerses: [verse(2), verse(3), verse(4)], partialVerse: verse(1), revealedWords: 0))

        sut.showHint()
        XCTAssertEqual(sut.hint, "قُ", "the first letter of قُلۡ, with its vowel")
        sut.revealNextWord()
        XCTAssertNil(sut.hint)
        XCTAssertEqual(masks.last??.revealedWords, 1)

        sut.check()
        XCTAssertEqual(sut.phase, .grading)
        XCTAssertEqual(masks.last??.revealedWords, 4, "112:1 has four words")
        XCTAssertNil(masks.last??.partialVerse, "the checked ayah shows whole, with its end marker")
        XCTAssertFalse(sut.hasHiddenWord)

        await sut.grade(.correct)
        XCTAssertEqual(sut.currentVerse, verse(2))
        XCTAssertEqual(masks.last, PracticeMask(hiddenVerses: [verse(3), verse(4)], partialVerse: verse(2), revealedWords: 0))
        for outcome in [RecallOutcome.correct, .mistake, .revealed] {
            sut.check()
            await sut.grade(outcome)
        }

        guard case .finished(let progress) = sut.phase else {
            return XCTFail("Expected finished, got \(sut.phase)")
        }
        XCTAssertEqual(progress.lastGrade, .again)
        XCTAssertEqual(progress.gradedSessions, 1)
        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(
            history.evidence.sorted { $0.verse < $1.verse }.map(\.outcome),
            [.hint, .correct, .mistake, .revealed],
            "Correct after a hint and a peeked word is recorded as a hint"
        )
        XCTAssertEqual(history.evidence.first { $0.verse.ayah == 1 }?.assistance, 2)

        await sut.end()
        XCTAssertEqual(masks.last, .some(nil), "the page shows every word again")
        XCTAssertTrue(closed)
        let sessions = try await persistence.history().sessions
        XCTAssertEqual(sessions.count, 1, "ending after finishing saves nothing more")
    }

    func testEndingEarlySavesOnlyTheGradedAyahs() async throws {
        let sut = makeSUT()
        await sut.start()
        sut.check()
        await sut.grade(.correct)

        await sut.end()

        let history = try await persistence.history()
        XCTAssertEqual(history.evidence.map(\.outcome), [.correct])
        XCTAssertEqual(history.sessions.first?.last, MemorizationVerse(sura: 112, ayah: 4))
        XCTAssertTrue(closed)
    }

    func testEndingBeforeGradingSavesNothing() async throws {
        let sut = makeSUT()
        await sut.start()

        await sut.end()

        let sessions = try await persistence.history().sessions
        XCTAssertEqual(sessions, [])
    }

    func testOneSelectedAyahPracticesToTheEndOfItsPage() {
        let quran = Quran.hafsMadani1405
        let start = AyahNumber(quran: quran, sura: 2, ayah: 6)!
        XCTAssertEqual(HifzPracticeBuilder.passage(for: [start]), Passage(start, start.page.lastVerse))
        XCTAssertEqual(HifzPracticeBuilder.passage(for: [verse(3), verse(1)]), Passage(verse(1), verse(3)))
        XCTAssertNil(HifzPracticeBuilder.passage(for: []))
    }

    func testCueLevelKeepsWordsOfHiddenAyahsVisibleAndIsRemembered() async throws {
        let sut = makeSUT()
        await sut.start()

        sut.setCueLevel(.firstWord)

        let mask = try XCTUnwrap(masks.last ?? nil)
        XCTAssertEqual(mask.cueWords, Set((1 ... 4).map { Word(verse: verse($0), wordNumber: 1) }))
        XCTAssertEqual(stateStore.cueLevel, .firstWord)

        sut.check()
        XCTAssertEqual(
            masks.last??.cueWords,
            Set((2 ... 4).map { Word(verse: verse($0), wordNumber: 1) }),
            "the checked ayah shows whole, so it needs no cue"
        )

        sut.setCueLevel(.alternateWords)
        // 112:2 is ٱللَّهُ ٱلصَّمَدُ: two words, so only its first is a cue.
        XCTAssertTrue(masks.last??.cueWords.contains(Word(verse: verse(2), wordNumber: 1)) == true)
        XCTAssertFalse(masks.last??.cueWords.contains(Word(verse: verse(2), wordNumber: 2)) == true)
    }

    func testCumulativeOrderGoesBackOverTheAyahsSoFar() async throws {
        stateStore.order = .cumulative
        let sut = makeSUT()
        await sut.start()

        var recited: [Int] = []
        while let current = sut.currentVerse {
            recited.append(current.ayah)
            if recited.count == 3 {
                XCTAssertEqual(sut.currentStep?.step, 2, "the A+B step")
                XCTAssertEqual(masks.last??.hiddenVerses, [verse(2), verse(3), verse(4)], "going back hides the later ayahs again")
            }
            sut.check()
            await sut.grade(.correct)
        }

        XCTAssertEqual(recited, [1, 2, 1, 2, 3, 1, 2, 3, 4, 1, 2, 3, 4])
        XCTAssertEqual(sut.steps.count, 7)
        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.evidence.count, 13)
    }

    func testOrderChangesOnlyBeforeTheFirstGrade() async {
        let sut = makeSUT()
        await sut.start()
        sut.revealNextWord()

        sut.setOrder(.cumulative)
        XCTAssertEqual(sut.order, .cumulative)
        XCTAssertEqual(sut.revealedWords, 0, "a new order starts over")
        XCTAssertEqual(stateStore.order, .cumulative)

        sut.check()
        await sut.grade(.correct)
        XCTAssertFalse(sut.canChangeOrder)
        sut.setOrder(.straight)
        XCTAssertEqual(sut.order, .cumulative)
    }

    func testMistakenWordsAreRecordedWithTheAyah() async throws {
        let sut = makeSUT()
        await sut.start()
        sut.check()

        sut.markMistakes()
        XCTAssertEqual(sut.phase, .markingMistakes)
        XCTAssertEqual(sut.wordChoices.map(\.words), [[1], [2], [3], [4]], "قُلۡ هُوَ ٱللَّهُ أَحَدٌ")
        XCTAssertEqual(sut.wordChoices.first?.text, "قُلۡ")
        sut.toggleMistake(sut.wordChoices[2])
        sut.toggleMistake(sut.wordChoices[3])
        sut.toggleMistake(sut.wordChoices[3])
        XCTAssertEqual(sut.markedWords, [3])
        await sut.saveMistakes()
        XCTAssertEqual(sut.currentVerse, verse(2))
        XCTAssertEqual(sut.markedWords, [])

        await sut.end()
        let evidence = try await persistence.history().evidence
        XCTAssertEqual(evidence.map(\.word).sorted(), [0, 3])
        XCTAssertEqual(Set(evidence.map(\.outcome)), [.mistake])
    }

    func testListenAndRepeatPlaysTheAyahAndCountsAsHelp() async throws {
        let sut = makeSUT()
        await sut.start()

        sut.toggleListening()
        XCTAssertEqual(listened, [verse(1)])
        XCTAssertTrue(sut.isListening)
        sut.audioStopped()
        XCTAssertFalse(sut.isListening, "playback finished")

        sut.toggleListening()
        sut.check()
        XCTAssertFalse(sut.isListening)
        XCTAssertEqual(stoppedListening, 1, "checking stops the recitation")
        await sut.grade(.correct)

        await sut.end()
        let evidence = try await persistence.history().evidence
        XCTAssertEqual(evidence.map(\.outcome), [.hint])
        XCTAssertEqual(evidence.first?.assistance, 2)
    }

    func testPracticeResumesAfterTheAppIsKilled() async throws {
        let first = makeSUT()
        await first.start()
        first.check()
        await first.grade(.correct)
        first.check()
        await first.grade(.mistake)
        // The app is killed: `first` never ends.

        let second = makeSUT()
        await second.start()
        XCTAssertEqual(second.currentVerse, verse(3))
        XCTAssertTrue(second.resumed)
        XCTAssertEqual(masks.last, PracticeMask(hiddenVerses: [verse(4)], partialVerse: verse(3), revealedWords: 0))
        second.check()
        await second.grade(.correct)
        XCTAssertFalse(second.resumed)
        await second.end()

        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.evidence.sorted { $0.verse < $1.verse }.map(\.outcome), [.correct, .mistake, .correct])
        XCTAssertNil(stateStore.draft, "a saved session leaves no draft")
    }

    func testAnotherPassagesDraftIsSavedAsItsOwnSession() async throws {
        let other = Passage(AyahNumber(quran: .hafsMadani1405, sura: 113, ayah: 1)!, AyahNumber(quran: .hafsMadani1405, sura: 113, ayah: 5)!)
        try stateStore.saveDraft(PracticeDraft(
            passage: other,
            order: .straight,
            position: 1,
            startedOn: Date(timeIntervalSince1970: 1_800_000_000),
            recalls: [VerseRecall(verse: other.first, outcome: .correct)]
        ))

        let sut = makeSUT()
        await sut.start()

        XCTAssertEqual(sut.currentVerse, verse(1))
        XCTAssertFalse(sut.resumed)
        XCTAssertNil(stateStore.draft)
        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.map(\.first), [MemorizationVerse(sura: 113, ayah: 1)])
    }

    // MARK: Private

    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var stateStore: PracticeStateStore!
    private var masks: [PracticeMask?] = []
    private var listened: [AyahNumber] = []
    private var stoppedListening = 0
    private var closed = false

    private func verse(_ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: ayah)!
    }

    private func makeSUT() -> HifzPracticeViewModel {
        HifzPracticeViewModel(
            passage: Passage(verse(1), verse(4)),
            verseText: RecitationVerseText(
                quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
                wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
            ),
            service: MemorizationService(persistence: persistence),
            store: stateStore,
            mask: { [weak self] in self?.masks.append($0) },
            listen: { [weak self] in self?.listened.append($0) },
            stopListening: { [weak self] in self?.stoppedListening += 1 },
            close: { [weak self] in self?.closed = true }
        )
    }
}
