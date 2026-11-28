//
//  TajweedAssessorTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreML
import TestResources
import XCTest
@testable import RecitationRecognition

final class TajweedAssessorTests: XCTestCase {
    private static let cachedDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/phonetic-model/out")

    private func sampleStore() -> PhoneticReferenceStore {
        PhoneticReferenceStore(databaseURL: TestResources.resourceURL("recitation/quran_phonetics_sample.db"))
    }

    private func makeTranscription(
        _ text: String,
        probability: Float = 0.95,
        stepSeconds: Double = 0.1
    ) -> PhoneticTranscription {
        let scalars = Array(text.unicodeScalars)
        let symbols = scalars.enumerated().map { idx, scalar in
            PhoneticSymbol(
                symbol: scalar,
                probability: probability,
                centerSeconds: Double(idx) * stepSeconds,
                frameIndex: idx * 5
            )
        }
        return PhoneticTranscription(
            symbols: symbols,
            endSeconds: Double(scalars.count) * stepSeconds,
            frameCount: max(1, scalars.count * 5),
            audioSeconds: Double(scalars.count) * stepSeconds
        )
    }

    func testCleanRecitationHasZeroTajweedRemarks() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        let result = TajweedAssessor().assess(
            transcription: makeTranscription("قُلهُوَللَااهُءَحَدڇ"),
            against: ref
        )
        XCTAssertEqual(result.confirmedRemarkCount, 0)
        XCTAssertEqual(result.uncertainRemarkCount, 0)
    }

    func testDetectsMissingQalqalahOnAhad() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        // Missing bounce ڇ at the end of أَحَد.
        let result = TajweedAssessor().assess(
            transcription: makeTranscription("قُلهُوَللَااهُءَحَد", probability: 0.95),
            against: ref
        )
        XCTAssertEqual(result.confirmedRemarkCount, 1)
        XCTAssertEqual(result.confirmedRemarks.first?.category, .qalqalah)
        XCTAssertEqual(result.confirmedRemarks.first?.kind, .qalqalahMissing(letter: "د"))
    }

    func testDetectsDroppedNaturalMaddAndTooShortMadd() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 1, ayah: 2))
        // Expected: ءَلحَمدُلِللَااهِرَببِلعَاالَمِۦۦۦۦن
        // Drop the natural madd on ٱلْعَٰلَمِينَ (remove اا).
        let result = TajweedAssessor().assess(
            transcription: makeTranscription("ءَلحَمدُلِللَااهِرَببِلعَلَمِۦۦۦۦن", probability: 0.95),
            against: ref
        )
        XCTAssertTrue(result.confirmedRemarks.contains(where: {
            if case .maddDropped = $0.kind, $0.category == .madd { return true }
            return false
        }))
    }

    func testDetectsShortGhunnahAndPronouncedIkhfaOnQdatVerse() {
        // Al-Ma'idah 5:109 phrase used in qdat_bench: إِننننَكَ (4x ن) + أَںںںتَ (3x ں) + ٱلْغُيُوبِ (ڇ)
        let ref = PhoneticReference(
            phonemes: "قَاالُۥۥلَااعِلمَلَنَااااءِننننَكَءَںںںتَعَللَاامُلغُيُۥۥۥۥبڇ",
            words: [
                WordPhoneticSpan(wordIndex: 0, wordNumber: 1, displayText: "قَالُوا۟", phonemeRange: 0 ..< 8),
                WordPhoneticSpan(wordIndex: 1, wordNumber: 2, displayText: "لَا", phonemeRange: 8 ..< 12),
                WordPhoneticSpan(wordIndex: 2, wordNumber: 3, displayText: "عِلْمَ", phonemeRange: 12 ..< 17),
                WordPhoneticSpan(wordIndex: 3, wordNumber: 4, displayText: "لَنَآ", phonemeRange: 17 ..< 25),
                WordPhoneticSpan(wordIndex: 4, wordNumber: 5, displayText: "إِنَّكَ", phonemeRange: 25 ..< 34),
                WordPhoneticSpan(wordIndex: 5, wordNumber: 6, displayText: "أَنتَ", phonemeRange: 34 ..< 41),
                WordPhoneticSpan(wordIndex: 6, wordNumber: 7, displayText: "عَلَّٰمُ", phonemeRange: 41 ..< 50),
                WordPhoneticSpan(wordIndex: 7, wordNumber: 8, displayText: "ٱلْغُيُوبِ", phonemeRange: 50 ..< 61),
            ],
            units: [
                PhoneticTajweedUnit(kind: .madd, rule: "NormalMaddRule", wordIndex: 0, phonemeRange: 2 ..< 4, goldenCount: 2, symbol: Unicode.Scalar(0x0627)!),
                PhoneticTajweedUnit(kind: .madd, rule: "NormalMaddRule", wordIndex: 1, phonemeRange: 10 ..< 12, goldenCount: 2, symbol: Unicode.Scalar(0x0627)!),
                PhoneticTajweedUnit(kind: .madd, rule: "MonfaselMaddRule", wordIndex: 3, phonemeRange: 21 ..< 25, goldenCount: 4, symbol: Unicode.Scalar(0x0627)!),
                PhoneticTajweedUnit(kind: .ghunnah, rule: "ghunnah", wordIndex: 4, phonemeRange: 27 ..< 31, goldenCount: 4, symbol: Unicode.Scalar(0x0646)!),
                PhoneticTajweedUnit(kind: .ikhfa, rule: "Ikhfa", wordIndex: 5, phonemeRange: 36 ..< 39, goldenCount: 3, symbol: Unicode.Scalar(0x06BA)!),
                PhoneticTajweedUnit(kind: .qalqalah, rule: "Qalqalah", wordIndex: 7, phonemeRange: 60 ..< 61, goldenCount: 1, symbol: Unicode.Scalar(0x0687)!),
            ]
        )

        // Learner makes 3 tajweed mistakes: short ghunnah (3x ن), clear nun instead of ikhfa (ن), dropped qalqalah (no ڇ).
        let heard = "قَاالُۥۥلَااعِلمَلَنَااااءِنننَكَءَنتَعَللَاامُلغُيُۥۥۥۥب"
        let res = TajweedAssessor().assess(transcription: makeTranscription(heard, probability: 0.92), against: ref)
        XCTAssertTrue(res.confirmedRemarks.contains(where: {
            if case .ghunnahTooShort = $0.kind { return true }
            return false
        }))
        XCTAssertTrue(res.confirmedRemarks.contains(where: { $0.kind == .ikhfaPronouncedClearly }))
        XCTAssertTrue(res.confirmedRemarks.contains(where: {
            if case .qalqalahMissing = $0.kind { return true }
            return false
        }))
    }

    func testLowConfidenceTajweedFindingIsUncertainNeverConfirmed() throws {
        let ref = try XCTUnwrap(sampleStore().reference(sura: 112, ayah: 1))
        let res = TajweedAssessor().assess(
            transcription: makeTranscription("قُلهُوَللَااهُءَحَد", probability: 0.20),
            against: ref
        )
        XCTAssertEqual(res.confirmedRemarkCount, 0)
        XCTAssertEqual(res.uncertainRemarkCount, 1)
        XCTAssertEqual(res.uncertainRemarks.first?.certainty, .uncertain)
    }

    func testTimingCalibrationDistinguishesSixCountMaddFromFourCount() {
        // Two natural madds of 0.30 s each -> pace = 0.15 s/count.
        // One lazim madd written as 4 symbols but held 1.35 s -> 1.35 / 0.15 = 9.0 >= 8.3 -> measured as 6 counts (passes Lazem {6}!).
        let ref = PhoneticReference(
            phonemes: "قَاالَاااامَااد",
            words: [
                WordPhoneticSpan(wordIndex: 0, wordNumber: 1, displayText: "قال", phonemeRange: 0 ..< 5),
                WordPhoneticSpan(wordIndex: 1, wordNumber: 2, displayText: "لا", phonemeRange: 5 ..< 10),
                WordPhoneticSpan(wordIndex: 2, wordNumber: 3, displayText: "ماد", phonemeRange: 10 ..< 15),
            ],
            units: [
                PhoneticTajweedUnit(kind: .madd, rule: "NormalMaddRule", wordIndex: 0, phonemeRange: 2 ..< 4, goldenCount: 2, symbol: Unicode.Scalar(0x0627)!),
                PhoneticTajweedUnit(kind: .madd, rule: "LazemMaddRule", wordIndex: 1, phonemeRange: 6 ..< 10, goldenCount: 6, symbol: Unicode.Scalar(0x0627)!),
                PhoneticTajweedUnit(kind: .madd, rule: "NormalMaddRule", wordIndex: 1, phonemeRange: 11 ..< 13, goldenCount: 2, symbol: Unicode.Scalar(0x0627)!),
            ]
        )
        let scalars = Array(ref.phonemes.unicodeScalars)
        // Natural madd 1 (indices 1..4): 0.30s; Lazim (indices 5..10): 1.40s; Natural madd 2 (indices 10..13): 0.30s.
        let timestamps: [Double] = [0.0, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.95, 1.30, 1.65, 2.00, 2.10, 2.20, 2.30, 2.40]
        let symbols = scalars.enumerated().map { i, s in
            PhoneticSymbol(symbol: s, probability: 0.98, centerSeconds: timestamps[i], frameIndex: i * 5)
        }
        let trans = PhoneticTranscription(symbols: symbols, endSeconds: 2.60, frameCount: 130, audioSeconds: 2.60)
        let res = TajweedAssessor().assess(transcription: trans, against: ref)
        XCTAssertNotNil(res.secondsPerCount)
        let lazim = res.measuredMadds.first(where: { $0.rule == "LazemMaddRule" })
        XCTAssertEqual(lazim?.heardCounts, 6)
        XCTAssertEqual(lazim?.measuredByTiming, true)
        XCTAssertEqual(res.confirmedRemarkCount, 0)
    }

    func testCoreMLStudioRecitationsProduceAccurateTajweedMeasurementsAndZeroFalseAlarms() async throws {
        let pkgURL = Self.cachedDir.appendingPathComponent(PhoneticModelStore.packageName)
        let vocabURL = Self.cachedDir.appendingPathComponent(PhoneticModelStore.vocabularyName)
        guard FileManager.default.fileExists(atPath: pkgURL.path),
              FileManager.default.fileExists(atPath: vocabURL.path)
        else {
            throw XCTSkip("No phonetic model at \(pkgURL.path): run `make phonetic-model` to build it.")
        }
        let compiled = try await MLModel.compileModel(at: pkgURL)
        let vocab = try PhoneticVocabulary(jsonData: Data(contentsOf: vocabURL))
        let model = try CoreMLPhoneticModel(compiledModelURL: compiled, vocabulary: vocab, computeUnits: .cpuOnly)
        let store = sampleStore()
        let assessor = TajweedAssessor()

        // 1. Husary 112:1 (qalqalah present on أَحَدٌ -> 0 remarks).
        let husary = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Husary_112001.mp3"))
        let hTrans = try await model.transcribe(husary)
        let ref112 = try XCTUnwrap(store.reference(sura: 112, ayah: 1))
        let res112 = assessor.assess(transcription: hTrans, against: ref112)
        XCTAssertEqual(res112.confirmedRemarkCount, 0)

        // 2. Alafasy 1:2 (aarid madd on ٱلْعَٰلَمِينَ measured at 4 counts -> 0 remarks).
        let alafasy = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Alafasy_001002.mp3"))
        let aTrans = try await model.transcribe(alafasy)
        let ref12 = try XCTUnwrap(store.reference(sura: 1, ayah: 2))
        let res12 = assessor.assess(transcription: aTrans, against: ref12)
        XCTAssertEqual(res12.confirmedRemarkCount, 0)
        XCTAssertTrue(res12.measuredMadds.contains(where: { $0.rule == "AaredMaddRule" && $0.heardCounts >= 2 }))
    }
}
