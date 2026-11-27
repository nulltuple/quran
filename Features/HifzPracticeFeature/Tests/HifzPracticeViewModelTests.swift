//
//  HifzPracticeViewModelTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
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
        masks = []
        closed = false
    }

    override func tearDown() {
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

    // MARK: Private

    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var masks: [PracticeMask?] = []
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
            mask: { [weak self] in self?.masks.append($0) },
            close: { [weak self] in self?.closed = true }
        )
    }
}
