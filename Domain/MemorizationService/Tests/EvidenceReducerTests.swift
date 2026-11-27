//
//  EvidenceReducerTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import MemorizationPersistence
import XCTest
@testable import MemorizationService

final class EvidenceReducerTests: XCTestCase {
    func testDuplicatesCountOnceAndARetractionInAnyCopyWins() {
        let record = evidence(ayah: 1, .correct)
        var retracted = record
        retracted.retractedOn = Date(timeIntervalSince1970: 1)
        let other = evidence(ayah: 2, .correct)

        XCTAssertEqual(EvidenceReducer.effective([record, other, record]), [record, other])
        XCTAssertEqual(EvidenceReducer.effective([record, retracted, other]), [other])
        // Idempotent.
        let once = EvidenceReducer.effective([record, retracted, other])
        XCTAssertEqual(EvidenceReducer.effective(once), once)
    }

    func testAllCorrectWithoutHelpIsGood() {
        XCTAssertEqual(EvidenceReducer.grade(of: [evidence(ayah: 1, .correct), evidence(ayah: 2, .correct)]), .good)
    }

    func testHintsAssistanceAndSelfCorrectionsAreHard() {
        XCTAssertEqual(EvidenceReducer.grade(of: [evidence(ayah: 1, .correct), evidence(ayah: 2, .hint)]), .hard)
        XCTAssertEqual(EvidenceReducer.grade(of: [evidence(ayah: 1, .correct, assistance: 1)]), .hard)
        XCTAssertEqual(EvidenceReducer.grade(of: [evidence(ayah: 1, .selfCorrected)]), .hard)
    }

    func testAFewMistakenVersesAreHardAndAThirdOrMoreIsAgain() {
        let fourCorrect = (1 ... 4).map { evidence(ayah: $0, .correct) }
        XCTAssertEqual(EvidenceReducer.grade(of: fourCorrect + [evidence(ayah: 5, word: 3, .mistake)]), .hard)
        XCTAssertEqual(EvidenceReducer.grade(of: [evidence(ayah: 1, .correct), evidence(ayah: 2, .mistake)]), .again)
    }

    func testARevealedVerseIsAgain() {
        XCTAssertEqual(EvidenceReducer.grade(of: [evidence(ayah: 1, .correct), evidence(ayah: 2, .revealed)]), .again)
    }

    func testSkippedVersesAreNotGraded() {
        XCTAssertNil(EvidenceReducer.grade(of: [evidence(ayah: 1, .skipped)]))
        XCTAssertNil(EvidenceReducer.grade(of: []))
        XCTAssertEqual(EvidenceReducer.grade(of: [evidence(ayah: 1, .skipped), evidence(ayah: 2, .correct)]), .good)
    }

    private func evidence(ayah: Int, word: Int = 0, _ outcome: RecallOutcome, assistance: Int = 0) -> RecallEvidenceRecord {
        RecallEvidenceRecord(
            id: UUID(),
            sessionID: UUID(),
            verse: MemorizationVerse(sura: 112, ayah: ayah),
            word: word,
            outcome: outcome,
            assistance: assistance,
            provenance: .manual,
            recordedOn: Date(timeIntervalSince1970: 0)
        )
    }
}
