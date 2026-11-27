//
//  CTCDecoderTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import XCTest
@testable import RecitationRecognition

final class CTCDecoderTests: XCTestCase {
    // Ids: 0 "<unk>", 1 "▁قل", 2 "▁هو", 3 "ل", 4 blank.
    private let decoder = CTCDecoder(vocabulary: CTCVocabulary(pieces: ["<unk>", "\u{2581}قل", "\u{2581}هو", "ل", "_"], blankID: 4))

    func testCollapsesRepeatsDropsBlanksAndJoinsWordPieces() {
        let transcript = decoder.decode(frameTokens: [4, 1, 1, 4, 2, 2, 4])
        XCTAssertEqual(transcript.text, "قل هو")
        XCTAssertEqual(transcript.tokens.map(\.frames), [1 ... 2, 4 ... 5])
    }

    func testABlankBetweenEqualTokensKeepsBoth() {
        let transcript = decoder.decode(frameTokens: [3, 4, 3])
        XCTAssertEqual(transcript.tokens.map(\.id), [3, 3])
        XCTAssertEqual(transcript.text, "لل")
    }

    func testDecodesTheBestTokenOfEachFrame() {
        let logProbabilities = CTCLogProbabilities(frameCount: 2, vocabularySize: 5, values: [
            -9, -0.1, -9, -9, -3,
            -9, -9, -0.2, -9, -2,
        ])
        XCTAssertEqual(decoder.decode(logProbabilities).text, "قل هو")
    }

    func testReadsTheModelVocabularyJSON() throws {
        let json = Data(#"{"1": "▁قل", "0": "<unk>", "2": "_"}"#.utf8)
        let vocabulary = try CTCVocabulary(jsonData: json, blankID: 2)
        XCTAssertEqual(vocabulary.pieces, ["<unk>", "\u{2581}قل", "_"])
        XCTAssertThrowsError(try CTCVocabulary(jsonData: Data(#"{"5": "x"}"#.utf8), blankID: 0))
    }
}
