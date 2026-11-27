//
//  CoreMLRecitationModelTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import CoreML
import QuranKit
import QuranResources
import TestResources
import VerseTextPersistence
import XCTest
@testable import RecitationRecognition

/// End to end on public EveryAyah recordings: audio → Core ML model → transcript → verse.
///
/// The model is not in git (125 MB). `make recitation-model` builds it into `.cache/recitation-model`;
/// without it these tests skip and say so. The V0 trail records a run with the model.
final class CoreMLRecitationModelTests: XCTestCase {
    // MARK: Internal

    func testIdentifiesShortRecitationsOfThreeReciters() async throws {
        let recognizer = try await makeRecognizer()
        for (fixture, expected, words) in [
            ("Husary_112001.mp3", "112:1", "قل هو الله احد"),
            ("Alafasy_001002.mp3", "1:2", "الحمد لله رب العالمين"),
            ("Ghamadi_040001.mp3", "40:1", "حم"),
        ] {
            let samples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/" + fixture))
            let result = try await recognizer.identifyVerses(in: samples)
            XCTAssertTrue(ArabicMatchNormalizer.normalize(result.transcript).contains(words), "\(fixture): \(result.transcript)")
            if expected == "40:1" {
                // "Ha Mim" opens seven suras and has two letters: never a confident answer.
                XCTAssertFalse(result.isConfident, fixture)
            } else {
                XCTAssertEqual(result.candidates.first.map(name), expected, fixture)
                XCTAssertTrue(result.isConfident, fixture)
            }
        }
    }

    func testRecitationsLongerThanOneWindowAreTranscribedInWindows() async throws {
        let recognizer = try await makeRecognizer()
        let samples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Ghamadi_002255.mp3"))
        XCTAssertGreaterThan(samples.count, 320_000 * 2)
        let result = try await recognizer.identifyVerses(in: samples)
        XCTAssertEqual(result.candidates.first.map(name), "2:255")
        XCTAssertTrue(result.isConfident)
    }

    func testSilenceGivesNoConfidentVerse() async throws {
        let recognizer = try await makeRecognizer()
        let result = try await recognizer.identifyVerses(in: [Float](repeating: 0, count: 3 * RecitationAudio.sampleRate))
        XCTAssertFalse(result.isConfident)
    }

    func testRecitedWordsAlignToCanonicalWordsWithTiming() async throws {
        let recognizer = try await makeRecognizer()
        let samples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Husary_112001.mp3"))
        let verse = try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: 1))
        let expected = try await ExpectedWordsReaderTests.makeReader().expectedWords(for: [verse])
        let steps = try await recognizer.alignWords(in: samples, to: expected)

        XCTAssertEqual(steps.map(\.kind), [.matched, .matched, .matched, .matched], "\(steps)")
        XCTAssertEqual(steps.flatMap(\.expected), (1 ... 4).map { Word(verse: verse, wordNumber: $0) })
        let frames = steps.compactMap(\.frames)
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames, frames.sorted { $0.lowerBound < $1.lowerBound }, "words come in recitation order")
        XCTAssertLessThanOrEqual(frames.last?.upperBound ?? .max, samples.count / CoreMLRecitationModel.samplesPerFrame)
    }

    func testALongHeldLastWordStillAlignsToItsWord() async throws {
        // Alafasy holds the madd of ٱلۡعَٰلَمِينَ for about 3 s; the model writes stray letters into
        // the hold and joins them to the word (measured 2026-11-27: "العالميندرس", frames 33–69).
        let recognizer = try await makeRecognizer()
        let samples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Alafasy_001002.mp3"))
        let verse = try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 2))
        let expected = try await ExpectedWordsReaderTests.makeReader().expectedWords(for: [verse])
        let steps = try await recognizer.alignWords(in: samples, to: expected)

        XCTAssertEqual(steps.flatMap(\.expected), (1 ... 4).map { Word(verse: verse, wordNumber: $0) }, "\(steps)")
        XCTAssertEqual(steps.prefix(3).map(\.kind), [.matched, .matched, .matched])
        XCTAssertNotEqual(steps.last?.kind, .omitted)
        XCTAssertNotNil(steps.last?.frames)
    }

    func testWordFramesCountFromTheStartOfALongRecording() async throws {
        let recognizer = try await makeRecognizer()
        let samples = try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/Ghamadi_002255.mp3"))
        let verse = try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 2, ayah: 255))
        // 2:255 is not in the test word database; its 50 Uthmani tokens are its 50 words.
        let text = try await GRDBQuranVerseTextPersistence(fileURL: QuranResources.quranUthmaniV2Database).textForVerse(verse).text
        let expected = text.split(separator: " ").enumerated().map { index, token in
            ExpectedWordText(words: [Word(verse: verse, wordNumber: index + 1)], text: String(token))
        }
        let steps = try await recognizer.alignWords(in: samples, to: expected)

        let matched = steps.filter { $0.kind == .matched }.flatMap(\.expected)
        XCTAssertGreaterThanOrEqual(Double(matched.count) / Double(expected.count), 0.9, "\(steps.filter { $0.kind != .matched })")
        let starts = steps.compactMap(\.frames?.lowerBound)
        XCTAssertEqual(starts, starts.sorted())
        // The recording spans three 20 s windows (250 frames each); later words keep their place.
        XCTAssertGreaterThan(starts.last ?? 0, 500)
    }

    func testWindowLatencyOnThisDevice() async throws {
        let (model, _) = try await Self.loadModel()
        let window = ArraySlice([Float](repeating: 0.01, count: model.windowSampleCount))
        _ = try await model.logProbabilities(for: window) // warm up
        var milliseconds: [Double] = []
        for _ in 0 ..< 5 {
            let start = Date()
            _ = try await model.logProbabilities(for: window)
            milliseconds.append(Date().timeIntervalSince(start) * 1000)
        }
        // A 20 s window must take well under 20 s; the activity name records the numbers.
        let summary = "RecitationModelLatency window_ms=\(milliseconds.map { Int($0) }.sorted())"
        await MainActor.run { XCTContext.runActivity(named: summary) { _ in } }
        XCTAssertLessThan(milliseconds.max() ?? .infinity, 5000)
    }

    // MARK: Private

    private actor Cache {
        static let shared = Cache()
        var loaded: (CoreMLRecitationModel, CTCVocabulary)?
        func set(_ value: (CoreMLRecitationModel, CTCVocabulary)) {
            loaded = value
        }
    }

    /// `.cache/recitation-model` at the repository root (this file is Domain/RecitationRecognition/Tests/).
    private static let modelDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/recitation-model")

    private static func loadModel() async throws -> (CoreMLRecitationModel, CTCVocabulary) {
        if let loaded = await Cache.shared.loaded {
            return loaded
        }
        let package = modelDirectory.appendingPathComponent("TilawiFastConformerInt8.mlpackage")
        let vocabularyURL = modelDirectory.appendingPathComponent("source/vocab.json")
        guard FileManager.default.fileExists(atPath: package.path), FileManager.default.fileExists(atPath: vocabularyURL.path) else {
            throw XCTSkip("No recitation model at \(package.path): run `make recitation-model` to build it.")
        }
        let compiled = try await MLModel.compileModel(at: package)
        let model = try CoreMLRecitationModel(compiledModelURL: compiled)
        let vocabulary = try CTCVocabulary(jsonData: Data(contentsOf: vocabularyURL), blankID: 1024)
        await Cache.shared.set((model, vocabulary))
        return (model, vocabulary)
    }

    private func makeRecognizer() async throws -> RecitationRecognizer {
        let (model, vocabulary) = try await Self.loadModel()
        let matcher = try await VerseMatcherTests.makeMatcher()
        return RecitationRecognizer(model: model, decoder: CTCDecoder(vocabulary: vocabulary), matcher: matcher)
    }

    private func name(_ candidate: VerseCandidate) -> String {
        "\(candidate.firstVerse.sura.suraNumber):\(candidate.firstVerse.ayah)"
    }
}
