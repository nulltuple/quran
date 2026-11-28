//
//  SimilarVersesViewModelTests.swift
//

import CoreDataPersistenceTestSupport
import MemorizationPersistence
import MemorizationService
import QuranKit
import QuranResources
import XCTest
@testable import HifzReviewFeature

@MainActor
final class SimilarVersesViewModelTests: XCTestCase {
    func testWrongContinuationRecordsOneMistakeAgainstExpectedAyah() async throws {
        let store = TemporaryCoreDataStore()
        let persistence = CoreDataMemorizationPersistence(stack: store.stack())
        let model = makeModel(verse: ayah(109, 3), persistence: persistence)
        await model.loadMatches()
        model.selection = ayah(109, 5)
        await model.compareSelection()

        model.startContinuation()
        await model.chooseContinuation(ayah(109, 6))
        await model.chooseContinuation(ayah(109, 4))

        let history = try await persistence.history()
        let evidence = try XCTUnwrap(history.evidence.first)
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.evidence.count, 1)
        XCTAssertEqual(evidence.verse, MemorizationVerse(sura: 109, ayah: 4))
        XCTAssertEqual(evidence.outcome, .mistake)
        XCTAssertEqual(evidence.provenance, .manual)
    }

    func testEndingRevealAloneDoesNotRecordEvidenceAndGradeUsesSource() async throws {
        let store = TemporaryCoreDataStore()
        let persistence = CoreDataMemorizationPersistence(stack: store.stack())
        let model = makeModel(verse: ayah(2, 23), persistence: persistence)
        await model.loadMatches()
        model.selection = ayah(19, 48)
        await model.compareSelection()

        model.startEnding()
        await model.gradeEnding(correct: true)
        model.revealEnding()
        let before = try await persistence.history()
        XCTAssertTrue(before.evidence.isEmpty)

        await model.gradeEnding(correct: true)
        let history = try await persistence.history()
        XCTAssertEqual(history.evidence.map(\.verse), [MemorizationVerse(sura: 2, ayah: 23)])
        XCTAssertEqual(history.evidence.map(\.outcome), [.correct])
    }

    func testClosingAfterPlayingRelatedAyahStopsPlaybackAndRestoresOrigin() {
        let store = TemporaryCoreDataStore()
        let persistence = CoreDataMemorizationPersistence(stack: store.stack())
        let origin = ayah(1, 1)
        let related = ayah(27, 30)
        var played: [AyahNumber] = []
        var navigated: [AyahNumber] = []
        var stopCount = 0
        let model = SimilarVersesViewModel(
            origin: origin,
            similarities: SimilarVerseService(uthmaniDatabase: QuranResources.quranUthmaniV2Database),
            memorization: MemorizationService(persistence: persistence),
            jump: { navigated.append($0) },
            play: { played.append($0) },
            stop: { stopCount += 1 }
        )

        model.play(related)
        model.close()
        model.close()

        XCTAssertEqual(played, [related])
        XCTAssertEqual(navigated, [origin])
        XCTAssertEqual(stopCount, 1)
    }

    private func makeModel(verse: AyahNumber, persistence: CoreDataMemorizationPersistence) -> SimilarVersesViewModel {
        SimilarVersesViewModel(
            origin: verse,
            similarities: SimilarVerseService(uthmaniDatabase: QuranResources.quranUthmaniV2Database),
            memorization: MemorizationService(persistence: persistence),
            jump: { _ in },
            play: { _ in },
            stop: {}
        )
    }

    private func ayah(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: sura, ayah: ayah)!
    }
}
