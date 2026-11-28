//
//  PronunciationAssessorTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import QuranKit
import TestResources
import XCTest
@testable import RecitationRecognition

final class PronunciationAssessorTests: XCTestCase {
    private func makeTranscription(_ text: String, probability: Float = 0.98) -> PhoneticTranscription {
        let symbols = Array(text.unicodeScalars).enumerated().map { idx, scalar in
            PhoneticSymbol(symbol: scalar, probability: probability, centerSeconds: Double(idx) * 0.1, frameIndex: idx * 5)
        }
        return PhoneticTranscription(
            symbols: symbols,
            endSeconds: Double(symbols.count) * 0.1,
            frameCount: max(1, symbols.count * 5),
            audioSeconds: Double(symbols.count) * 0.1
        )
    }

    private func sampleStore() -> PhoneticReferenceStore {
        PhoneticReferenceStore(databaseURL: TestResources.resourceURL("recitation/quran_phonetics_sample.db"))
    }

    func testReadsSampleReferenceDatabaseForCanonicalAyahs() throws {
        let store = sampleStore()
        let ref = try XCTUnwrap(store.reference(sura: 112, ayah: 1))
        XCTAssertEqual(ref.phonemes, "قُلهُوَللَااهُءَحَدڇ")
        XCTAssertEqual(ref.words.count, 4)
        XCTAssertEqual(ref.words.map(\.wordNumber), [1, 2, 3, 4])
        XCTAssertTrue(ref.units.contains(where: { $0.kind == .qalqalah }))
    }

    func testCleanRecitationHasZeroMistakesAndFullMatchRate() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        let result = PronunciationAssessor().assess(
            transcription: makeTranscription("قُلهُوَللَااهُءَحَدڇ"),
            against: ref
        )
        XCTAssertEqual(result.phonemeMatchRate, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.confirmedMistakeCount, 0)
        XCTAssertEqual(result.uncertainCount, 0)
        XCTAssertTrue(result.words.allSatisfy { $0.status == .correct })
    }

    func testDetectsWrongVowelWithHighConfidence() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        // Reciter said أَحِد (kasra) instead of أَحَد (fatha).
        let result = PronunciationAssessor().assess(
            transcription: makeTranscription("قُلهُوَللَااهُءَحِدڇ", probability: 0.99),
            against: ref
        )
        XCTAssertEqual(result.confirmedMistakeCount, 1)
        XCTAssertEqual(result.words[3].status, .mistake)
        XCTAssertEqual(result.words[3].confirmedIssues.first?.kind, .wrongVowel(expected: .fatha, heard: .kasra))
    }

    func testDetectsWrongConsonantWithHighConfidence() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        // Reciter said أَسَد instead of أَحَد.
        let result = PronunciationAssessor().assess(
            transcription: makeTranscription("قُلهُوَللَااهُءَسَدڇ", probability: 0.99),
            against: ref
        )
        XCTAssertEqual(result.confirmedMistakeCount, 1)
        XCTAssertEqual(result.words[3].status, .mistake)
        XCTAssertEqual(result.words[3].confirmedIssues.first?.kind, .wrongConsonant(expected: "ح", heard: "س"))
    }

    func testDetectsOnsetVowelAndConsonantErrorWhenConfidenceMeetsOnsetThreshold() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        // Reciter said كَلْ instead of قُلْ at onset (high confidence 0.99 >= 0.85).
        let result = PronunciationAssessor().assess(
            transcription: makeTranscription("قَلهُوَللَااهُءَحَدڇ", probability: 0.99),
            against: ref
        )
        XCTAssertEqual(result.words[0].status, .mistake)
        XCTAssertEqual(result.words[0].confirmedIssues.first?.kind, .wrongVowel(expected: .damma, heard: .fatha))
    }

    func testLowConfidenceMismatchIsUncertainNeverConfirmedMistake() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        // Same vowel mismatch, but model probability is 0.45 (< 0.70 threshold).
        let result = PronunciationAssessor().assess(
            transcription: makeTranscription("قُلهُوَللَااهُءَحِدڇ", probability: 0.45),
            against: ref
        )
        XCTAssertEqual(result.confirmedMistakeCount, 0)
        XCTAssertEqual(result.uncertainCount, 1)
        XCTAssertEqual(result.words[3].status, .uncertain)
        XCTAssertEqual(result.words[3].uncertainIssues.first?.certainty, .uncertain)
    }

    func testTajweedOnlyDifferencesAreKeptSeparateFromV4PronunciationMistakes() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        // Missing qalqalah (ڇ dropped at end of أَحَد) is a V5 tajweed issue, NOT a V4 clear pronunciation mistake.
        let result = PronunciationAssessor().assess(
            transcription: makeTranscription("قُلهُوَللَااهُءَحَد", probability: 0.99),
            against: ref
        )
        XCTAssertEqual(result.confirmedMistakeCount, 0)
        XCTAssertEqual(result.words[3].status, .correct)
    }

    func testDetectsMissingWordWhenAudioEndsEarly() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        let result = PronunciationAssessor().assess(
            transcription: makeTranscription("قُلهُوَللَااهُ", probability: 0.99),
            against: ref
        )
        XCTAssertEqual(result.words[3].status, .mistake)
        XCTAssertEqual(result.words[3].confirmedIssues.first?.kind, .wordNotHeard)
    }

    func testWorksOnCustomNonQuranReferenceForArabicanReuse() {
        // Standalone word drill (e.g., Arabican reading exercise) with no Quran database needed.
        let customRef = PhoneticReference(
            phonemes: "كَتَبَ",
            words: [WordPhoneticSpan(wordIndex: 0, wordNumber: 1, displayText: "كَتَبَ", phonemeRange: 0 ..< 6)]
        )
        let ok = PronunciationAssessor().assess(transcription: makeTranscription("كَتَبَ"), against: customRef)
        XCTAssertEqual(ok.confirmedMistakeCount, 0)

        let wrong = PronunciationAssessor().assess(transcription: makeTranscription("كُتِبَ"), against: customRef)
        XCTAssertEqual(wrong.confirmedMistakeCount, 2)
        XCTAssertEqual(wrong.words[0].status, .mistake)
    }
}
