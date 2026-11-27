//
//  CoreMLRecitationModelTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import CoreML
import QuranKit
import TestResources
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
