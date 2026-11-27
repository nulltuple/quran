//
//  RecognizedWordTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import XCTest
@testable import RecitationRecognition

final class RecognizedWordTests: XCTestCase {
    // MARK: Internal

    func testTokensGroupIntoWordsWithTheirFrames() {
        // Frames: ▁قل ▁قل _ ▁هو ▁هو ل _ _ ▁
        let transcript = decoder.decode(frameTokens: [1, 1, 4, 2, 2, 3, 4, 4, 5])
        XCTAssertEqual(transcript.words(), [
            RecognizedWord(text: "قل", frames: 0 ... 1),
            RecognizedWord(text: "هول", frames: 3 ... 5),
        ])
    }

    func testFramesAreShiftedByTheWindowOffset() {
        let transcript = decoder.decode(frameTokens: [4, 1, 4, 2])
        XCTAssertEqual(transcript.words(frameOffset: 250).map(\.frames), [251 ... 251, 253 ... 253])
    }

    func testAPieceThatEndsAWordAndStartsAnotherSplitsThere() {
        // "ل▁ا": the first part ends the current word, the second starts the next.
        let decoder = CTCDecoder(vocabulary: CTCVocabulary(pieces: ["\u{2581}قل", "ل\u{2581}ا", "_"], blankID: 2))
        let words = decoder.decode(frameTokens: [0, 2, 1]).words()
        XCTAssertEqual(words, [RecognizedWord(text: "قلل", frames: 0 ... 2), RecognizedWord(text: "ا", frames: 2 ... 2)])
    }

    func testAPlainTranscriptHasWordsWithoutTiming() {
        XCTAssertEqual(RecognizedWord.words(of: " قل  هو\nالله "), [
            RecognizedWord(text: "قل", frames: nil),
            RecognizedWord(text: "هو", frames: nil),
            RecognizedWord(text: "الله", frames: nil),
        ])
    }

    // MARK: Private

    // Ids: 0 "<unk>", 1 "▁قل", 2 "▁هو", 3 "ل", 4 blank, 5 "▁".
    private let decoder = CTCDecoder(vocabulary: CTCVocabulary(
        pieces: ["<unk>", "\u{2581}قل", "\u{2581}هو", "ل", "_", "\u{2581}"],
        blankID: 4
    ))
}
