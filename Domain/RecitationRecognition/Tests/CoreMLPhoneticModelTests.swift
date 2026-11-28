//
//  CoreMLPhoneticModelTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreML
import TestResources
import XCTest
@testable import RecitationRecognition

/// End-to-end Core ML tests for the V4 phonetic assessment engine (HisnLabs Tajweed v2 int8).
/// Skips cleanly when `.cache/phonetic-model/out` has not been built (`make phonetic-model`).
final class CoreMLPhoneticModelTests: XCTestCase {
    private static let cachedDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/phonetic-model/out")

    private func loadCachedModel() async throws -> (CoreMLPhoneticModel, PhoneticReferenceStore) {
        let pkgURL = Self.cachedDir.appendingPathComponent(PhoneticModelStore.packageName)
        let vocabURL = Self.cachedDir.appendingPathComponent(PhoneticModelStore.vocabularyName)
        let dbURL = TestResources.resourceURL("recitation/quran_phonetics_sample.db")
        guard FileManager.default.fileExists(atPath: pkgURL.path),
              FileManager.default.fileExists(atPath: vocabURL.path)
        else {
            throw XCTSkip("No phonetic model at \(pkgURL.path): run `make phonetic-model` to build it.")
        }
        let compiled = try await MLModel.compileModel(at: pkgURL)
        let vocab = try PhoneticVocabulary(jsonData: Data(contentsOf: vocabURL))
        let model = try CoreMLPhoneticModel(compiledModelURL: compiled, vocabulary: vocab, computeUnits: .cpuOnly)
        return (model, PhoneticReferenceStore(databaseURL: dbURL))
    }

    func testCleanStudioRecitationsMatchExpectedPhonemesWithZeroFalseAlarms() async throws {
        let (model, store) = try await loadCachedModel()
        let assessor = PronunciationAssessor()

        // 1. Husary 112:1
        let husarySamples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Husary_112001.mp3"))
        let t0 = Date()
        let husaryTrans = try await model.transcribe(husarySamples)
        let ms1 = Int(Date().timeIntervalSince(t0) * 1000)
        let ref112 = try XCTUnwrap(store.reference(sura: 112, ayah: 1))
        let res112 = assessor.assess(transcription: husaryTrans, against: ref112)
        XCTAssertEqual(husaryTrans.text, ref112.phonemes)
        XCTAssertEqual(res112.confirmedMistakeCount, 0)
        XCTAssertEqual(res112.phonemeMatchRate, 1.0, accuracy: 0.001)

        // 2. Alafasy 1:2
        let alafasySamples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Alafasy_001002.mp3"))
        let t1 = Date()
        let alafasyTrans = try await model.transcribe(alafasySamples)
        let ms2 = Int(Date().timeIntervalSince(t1) * 1000)
        let ref12 = try XCTUnwrap(store.reference(sura: 1, ayah: 2))
        let res12 = assessor.assess(transcription: alafasyTrans, against: ref12)
        XCTAssertGreaterThan(res12.phonemeMatchRate, 0.95)
        XCTAssertEqual(res12.confirmedMistakeCount, 0)

        print("V4 CoreML simulator latency: 112:1=\(ms1)ms, 1:2=\(ms2)ms")
    }

    func testDetectsSpokenVowelConsonantAndTruncationErrorsRatherThanGuessingExpectedText() async throws {
        let (model, store) = try await loadCachedModel()
        let assessor = PronunciationAssessor()

        let husarySamples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Husary_112001.mp3"))
        let husaryTrans = try await model.transcribe(husarySamples)
        let ref112 = try XCTUnwrap(store.reference(sura: 112, ayah: 1))

        // 1. Planted vowel error: expected أَحِدٌ (kasra), audio says أَحَدٌ (fatha) -> MUST detect wrong vowel.
        let vowelMutatedRef = PhoneticReference(
            phonemes: "قُلهُوَللَااهُءَحِدڇ",
            words: ref112.words,
            units: ref112.units
        )
        let vowelRes = assessor.assess(transcription: husaryTrans, against: vowelMutatedRef)
        XCTAssertEqual(vowelRes.words[3].status, .mistake)
        XCTAssertTrue(vowelRes.words[3].confirmedIssues.contains(where: {
            if case .wrongVowel(.kasra, .fatha) = $0.kind { return true }
            return false
        }))

        // 2. Planted consonant error: expected أَسَدٌ, audio says أَحَدٌ -> MUST detect wrong consonant.
        let consonantMutatedRef = PhoneticReference(
            phonemes: "قُلهُوَللَااهُءَسَدڇ",
            words: ref112.words,
            units: ref112.units
        )
        let consonantRes = assessor.assess(transcription: husaryTrans, against: consonantMutatedRef)
        XCTAssertEqual(consonantRes.words[3].status, .mistake)
        XCTAssertTrue(consonantRes.words[3].confirmedIssues.contains(where: {
            if case .wrongConsonant("س", "ح") = $0.kind { return true }
            return false
        }))

        // 3. Audio-spliced dropped ending: cut off last 38% (drops أَحَدٌ) -> model must NOT hallucinate أَحَدٌ.
        let truncated = Array(husarySamples.prefix(Int(Double(husarySamples.count) * 0.62)))
        let truncTrans = try await model.transcribe(truncated)
        let truncRes = assessor.assess(transcription: truncTrans, against: ref112)
        XCTAssertFalse(truncTrans.text.contains("حَد"))
        XCTAssertEqual(truncRes.words[3].status, .mistake)
        XCTAssertEqual(truncRes.words[3].confirmedIssues.first?.kind, .wordNotHeard)

        // 4. Wrong-verse audio: Alafasy 1:2 assessed against 112:1 -> model hears 1:2, flags mismatches.
        let alafasySamples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Alafasy_001002.mp3"))
        let alafasyTrans = try await model.transcribe(alafasySamples)
        let wrongVerseRes = assessor.assess(transcription: alafasyTrans, against: ref112)
        XCTAssertGreaterThanOrEqual(wrongVerseRes.confirmedMistakeCount, 3)
        XCTAssertLessThan(wrongVerseRes.phonemeMatchRate, 0.4)
    }
}
