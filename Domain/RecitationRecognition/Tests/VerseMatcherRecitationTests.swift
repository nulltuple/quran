//
//  VerseMatcherRecitationTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import QuranKit
import TestResources
import XCTest
@testable import RecitationRecognition

/// The matcher on 350 real transcripts: the Core ML int8 model's output for 50 EveryAyah verses
/// (seed 1) by each of seven reciters, written by `Tools/recitation-model.py eval` (V0 trail).
final class VerseMatcherRecitationTests: XCTestCase {
    // MARK: Internal

    func testIdentifiesRealTranscriptsOfSevenReciters() async throws {
        // 350 identifications take tens of seconds in a debug build on the simulator.
        executionTimeAllowance = 300
        let data = try Data(contentsOf: TestResources.resourceURL("recitation/everyayah_transcripts.json"))
        let clips = try JSONDecoder().decode([Clip].self, from: data)
        let matcher = try await VerseMatcherTests.makeMatcher()
        let quran = Quran.hafsMadani1405

        var top1 = 0, top5 = 0, confident = 0, confidentWrong: [String] = []
        for clip in clips {
            let parts = clip.key.split(separator: ":").compactMap { Int($0) }
            let verse = try XCTUnwrap(AyahNumber(quran: quran, sura: parts[0], ayah: parts[1]))
            let expected = matcher.matchingLetters(of: verse)
            let result = matcher.identify(transcript: clip.transcript, limit: 5)
            // A candidate is right when it covers the verse or has its exact text (55:13 and its 30 twins).
            let isRight = { (candidate: VerseCandidate) in
                (candidate.firstVerse ... candidate.lastVerse).contains(verse)
                    || (candidate.firstVerse == candidate.lastVerse && matcher.matchingLetters(of: candidate.firstVerse) == expected)
            }
            let first = result.candidates.first.map(isRight) ?? false
            top1 += first ? 1 : 0
            top5 += result.candidates.contains(where: isRight) ? 1 : 0
            if result.isConfident {
                confident += 1
                if !first {
                    confidentWrong.append("\(clip.reciter) \(clip.key)")
                }
            }
        }
        let summary = "VerseMatcherRecitations clips=\(clips.count) top1=\(top1) top5=\(top5) confident=\(confident) confidentWrong=\(confidentWrong)"
        await MainActor.run { XCTContext.runActivity(named: summary) { _ in } }
        XCTAssertEqual(clips.count, 350)
        // Measured 2026-11-26: top-1 350, top-5 350, 346 confident (V0 trail). Slack of about 1%.
        XCTAssertGreaterThanOrEqual(top1, 347)
        XCTAssertGreaterThanOrEqual(top5, 349)
        XCTAssertGreaterThanOrEqual(confident, 340)
        XCTAssertEqual(confidentWrong, [], "a confident answer must never name the wrong verse")
    }

    // MARK: Private

    private struct Clip: Decodable {
        let reciter: String
        let key: String
        let transcript: String
    }
}
