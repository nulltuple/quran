//
//  RecitationCheckerRecitationTests.swift
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

/// V3a's quality gate on public recordings: the 350 real transcripts of `VerseMatcherRecitationTests`
/// (the Core ML int8 model's output for 50 EveryAyah verses by each of seven reciters), checked as
/// they are (every reported mistake is a false alarm: the reciters recite correctly) and with one
/// planted mistake each: a word cut, or a word swapped for a word of another verse.
final class RecitationCheckerRecitationTests: XCTestCase {
    // MARK: Internal

    func testPlantedMistakesAreFoundAndFaithfulRecitationsRarelyFlagged() async throws {
        executionTimeAllowance = 300
        let clips = try await loadClips()
        let checker = RecitationChecker()
        var words = 0, falseAlarms = 0, cleanClipsFlagged = 0
        var cuts = 0, cutsFound = 0, swaps = 0, swapsFound = 0, plantedFlaggedElsewhere = 0

        for (index, clip) in clips.enumerated() {
            let clean = checker.check(clip.recited, against: clip.expected)
            words += clean.words.count
            falseAlarms += clean.mistakes.count
            cleanClipsFlagged += clean.mistakes.isEmpty ? 0 : 1

            // Plant in the middle of a clip whose clean check found nothing, on a word it matched.
            guard clean.mistakes.isEmpty, clip.recited.count >= 5 else { continue }
            let target = clip.recited.count / 2
            let steps = WordAligner().align(clip.recited, to: clip.expected)
            guard let step = steps.first(where: { $0.kind == .matched && $0.recognized.count == 1 && $0.recognized[0] == clip.recited[target] }),
                  step.expected.count == 1
            else { continue }
            let word = step.expected[0]

            var cut = clip.recited
            cut.remove(at: target)
            let cutCheck = checker.check(cut, against: clip.expected)
            cuts += 1
            cutsFound += cutCheck.mistakes.contains { $0.word == word } ? 1 : 0
            plantedFlaggedElsewhere += cutCheck.mistakes.filter { $0.word != word }.count

            let donor = clips[(index + 175) % clips.count].recited
            guard let other = donor.first(where: { WordAligner.similarity(WordAligner.letters($0.text), WordAligner.letters(clip.recited[target].text)) < 0.3 && $0.text.count >= 3 }) else { continue }
            var swapped = clip.recited
            swapped[target] = other
            let swapCheck = checker.check(swapped, against: clip.expected)
            swaps += 1
            swapsFound += swapCheck.mistakes.contains { $0.word == word } ? 1 : 0
            plantedFlaggedElsewhere += swapCheck.mistakes.filter { $0.word != word }.count
        }

        let summary = "RecitationChecker words=\(words) falseAlarms=\(falseAlarms) cleanClipsFlagged=\(cleanClipsFlagged)/\(clips.count) "
            + "cuts=\(cutsFound)/\(cuts) swaps=\(swapsFound)/\(swaps) flaggedElsewhere=\(plantedFlaggedElsewhere)"
        await MainActor.run { XCTContext.runActivity(named: summary) { _ in } }
        XCTAssertEqual(clips.count, 350)
        // Gate (V3a trail): at most 1 false alarm per 100 words recited correctly; at least 90% of
        // planted cuts and swaps found at the right word. Measured 2026-11-27: 33 false alarms in
        // 4,305 words (0.77%), cuts 213/232 (92%), swaps 212/230 (92%); the misses are mostly a
        // word the verse says twice, where the other occurrence covers it.
        XCTAssertLessThanOrEqual(Double(falseAlarms) / Double(words), 0.01)
        XCTAssertGreaterThan(cuts, 200)
        XCTAssertGreaterThan(swaps, 200)
        XCTAssertGreaterThanOrEqual(Double(cutsFound) / Double(cuts), 0.9)
        XCTAssertGreaterThanOrEqual(Double(swapsFound) / Double(swaps), 0.9)
    }

    // MARK: Private

    private struct Clip: Decodable {
        let key: String
        let transcript: String
    }

    private struct LoadedClip {
        let recited: [RecognizedWord]
        let expected: [ExpectedWordText]
    }

    private func loadClips() async throws -> [LoadedClip] {
        let data = try Data(contentsOf: TestResources.resourceURL("recitation/everyayah_transcripts.json"))
        let clips = try JSONDecoder().decode([Clip].self, from: data)
        let verses = try clips.map { clip in
            let parts = clip.key.split(separator: ":").compactMap { Int($0) }
            return try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: parts[0], ayah: parts[1]))
        }
        let texts = try await GRDBQuranVerseTextPersistence(fileURL: QuranResources.quranUthmaniV2Database)
            .textForVerses(Array(Set(verses)))
        return try zip(clips, verses).map { clip, verse in
            // One token per word for these 50 verses (WordAlignerRecitationTests).
            let text = try XCTUnwrap(texts[verse]?.text)
            let expected = text.split(separator: " ").enumerated().map { index, token in
                ExpectedWordText(words: [Word(verse: verse, wordNumber: index + 1)], text: String(token))
            }
            return LoadedClip(recited: RecognizedWord.words(of: clip.transcript), expected: expected)
        }
    }
}
