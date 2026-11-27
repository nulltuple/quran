//
//  RecitationCheckerTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranKit
import XCTest
@testable import RecitationRecognition

final class RecitationCheckerTests: XCTestCase {
    // MARK: Internal

    func testAFaithfulRecitationHasNoMistakes() {
        let check = checker.check(words("قل هو الله احد الله الصمد"), against: expected)
        XCTAssertEqual(check.words.map(\.mark), Array(repeating: .correct, count: 6))
        XCTAssertEqual(check.words.map(\.word), expected.flatMap(\.words))
        XCTAssertTrue(check.mistakes.isEmpty)
        XCTAssertTrue(check.skippedVerses.isEmpty)
    }

    func testAMissingWordIsAnOmission() {
        let check = checker.check(words("قل هو احد الله الصمد"), against: expected)
        XCTAssertEqual(check.mistakes.map(\.word), [word(1, 3)])
        XCTAssertEqual(check.mistakes.map(\.mark), [.omitted])
    }

    func testAConfidentlyDifferentWordIsASubstitution() {
        let recited = [
            RecognizedWord(text: "قل", frames: 0 ... 2, confidence: 0.9),
            RecognizedWord(text: "هو", frames: 3 ... 4, confidence: 0.9),
            RecognizedWord(text: "الرحمن", frames: 5 ... 9, confidence: 0.9),
            RecognizedWord(text: "احد", frames: 10 ... 12, confidence: 0.9),
        ]
        let check = checker.check(recited, against: Array(expected.prefix(4)))
        XCTAssertEqual(check.mistakes.map(\.mark), [.substituted(recited: "الرحمن")])
        XCTAssertEqual(check.mistakes.first?.frames, 5 ... 9)
    }

    func testADifferentWordTheModelIsUnsureOfIsOnlyUncertain() {
        let recited = [
            RecognizedWord(text: "قل", frames: 0 ... 2, confidence: 0.9),
            RecognizedWord(text: "هو", frames: 3 ... 4, confidence: 0.9),
            RecognizedWord(text: "الرحمن", frames: 5 ... 9, confidence: 0.4),
            RecognizedWord(text: "احد", frames: 10 ... 12, confidence: 0.9),
        ]
        let check = checker.check(recited, against: Array(expected.prefix(4)))
        XCTAssertTrue(check.mistakes.isEmpty)
        XCTAssertEqual(check.words[2].mark, .uncertain)
    }

    func testANearMissIsUncertainNotAMistake() {
        // "الهم" for "الله": similarity 0.5, between uncertain and matched.
        let check = checker.check(words("قل هو الهم احد"), against: Array(expected.prefix(4)))
        XCTAssertEqual(check.words[2].mark, .uncertain)
        XCTAssertTrue(check.mistakes.isEmpty)
    }

    func testASlipCorrectedStraightAwayIsNotAMistake() {
        let check = checker.check(words("قل هو الرحمن الله احد"), against: Array(expected.prefix(4)))
        XCTAssertTrue(check.mistakes.isEmpty, "\(check.words.map(\.mark))")
    }

    func testGoingBackOverAPhraseIsNotAMistake() {
        let check = checker.check(words("قل هو الله قل هو الله احد الله الصمد"), against: expected)
        XCTAssertTrue(check.mistakes.isEmpty, "\(check.words.map(\.mark))")
    }

    func testWordsAfterTheLastRecitedOneAreNotReached() {
        let check = checker.check(words("قل هو الله"), against: expected)
        XCTAssertEqual(check.words.map(\.mark), [.correct, .correct, .correct, .notReached, .notReached, .notReached])
        XCTAssertTrue(check.mistakes.isEmpty)
        XCTAssertTrue(check.skippedVerses.isEmpty)
    }

    func testAVerseWithNothingRecitedIsSkipped() {
        let check = checker.check(words("قل هو الله احد لم يلد ولم يولد"), against: expected + verse3)
        XCTAssertEqual(check.skippedVerses, [verse(2)])
        XCTAssertEqual(check.mistakes.map(\.word), [word(2, 1), word(2, 2)])
    }

    func testNothingRecitedReachesNoWord() {
        let check = checker.check([], against: expected)
        XCTAssertEqual(check.words.map(\.mark), Array(repeating: .notReached, count: 6))
        XCTAssertTrue(check.skippedVerses.isEmpty)
    }

    // MARK: Private

    private let checker = RecitationChecker()

    private var expected: [ExpectedWordText] {
        ["قُلۡ", "هُوَ", "ٱللَّهُ", "أَحَدٌ"].enumerated().map { ExpectedWordText(words: [word(1, $0 + 1)], text: $1) }
            + ["ٱللَّهُ", "ٱلصَّمَدُ"].enumerated().map { ExpectedWordText(words: [word(2, $0 + 1)], text: $1) }
    }

    private var verse3: [ExpectedWordText] {
        ["لَمۡ", "يَلِدۡ", "وَلَمۡ", "يُولَدۡ"].enumerated().map { ExpectedWordText(words: [word(3, $0 + 1)], text: $1) }
    }

    private func verse(_ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: ayah)!
    }

    private func word(_ ayah: Int, _ number: Int) -> Word {
        Word(verse: verse(ayah), wordNumber: number)
    }

    private func words(_ transcript: String) -> [RecognizedWord] {
        RecognizedWord.words(of: transcript)
    }
}
