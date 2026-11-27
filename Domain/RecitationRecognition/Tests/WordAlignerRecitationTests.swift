//
//  WordAlignerRecitationTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranKit
import QuranResources
import TestResources
import VerseTextPersistence
import XCTest
@testable import RecitationRecognition

/// The aligner on the 350 real transcripts of `VerseMatcherRecitationTests` (the Core ML int8 model's
/// output for 50 EveryAyah verses by each of seven reciters), against each verse's Uthmani words.
final class WordAlignerRecitationTests: XCTestCase {
    // MARK: Internal

    func testRealTranscriptsMatchAlmostEveryCanonicalWord() async throws {
        executionTimeAllowance = 300
        let data = try Data(contentsOf: TestResources.resourceURL("recitation/everyayah_transcripts.json"))
        let clips = try JSONDecoder().decode([Clip].self, from: data)
        let quran = Quran.hafsMadani1405
        let verses = try clips.map { clip in
            let parts = clip.key.split(separator: ":").compactMap { Int($0) }
            return try XCTUnwrap(AyahNumber(quran: quran, sura: parts[0], ayah: parts[1]))
        }
        let texts = try await GRDBQuranVerseTextPersistence(fileURL: QuranResources.quranUthmaniV2Database)
            .textForVerses(Array(Set(verses)))
        let aligner = WordAligner()

        var expectedWords = 0, matched = 0, mismatched = 0, omitted = 0, inserted = 0
        for (clip, verse) in zip(clips, verses) {
            // One token per word: none of the 50 verses is one of the six ayahs where that fails
            // (ExpectedWordsReaderTests covers those).
            let text = try XCTUnwrap(texts[verse]?.text)
            let expected = text.split(separator: " ").enumerated().map { index, token in
                ExpectedWordText(words: [Word(verse: verse, wordNumber: index + 1)], text: String(token))
            }
            let steps = aligner.align(RecognizedWord.words(of: clip.transcript), to: expected)
            XCTAssertEqual(steps.flatMap(\.expected), expected.flatMap(\.words), "every word appears once, in order: \(clip.key)")
            expectedWords += expected.count
            for step in steps {
                switch step.kind {
                case .matched: matched += step.expected.count
                case .mismatched: mismatched += step.expected.count
                case .omitted: omitted += step.expected.count
                case .inserted: inserted += step.recognized.count
                }
            }
        }
        let summary = "WordAlignerRecitations words=\(expectedWords) matched=\(matched) mismatched=\(mismatched) omitted=\(omitted) inserted=\(inserted)"
        await MainActor.run { XCTContext.runActivity(named: summary) { _ in } }
        XCTAssertEqual(clips.count, 350)
        XCTAssertEqual(matched + mismatched + omitted, expectedWords)
        // Measured 2026-11-27: see the V0 (b) trail. The misses are mostly misheard words in clips
        // over 20 s, where a reciter goes back over a phrase.
        XCTAssertGreaterThanOrEqual(Double(matched) / Double(expectedWords), 0.97)
    }

    // MARK: Private

    private struct Clip: Decodable {
        let reciter: String
        let key: String
        let transcript: String
    }
}
