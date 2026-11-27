//
//  WordAlignerTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranKit
import XCTest
@testable import RecitationRecognition

/// The aligner on hand-written transcripts against the bundled Uthmani words.
final class WordAlignerTests: XCTestCase {
    // MARK: Internal

    func testThePlainSpellingOfAVerseMatchesEveryUthmaniWord() {
        // ٱلۡعَٰلَمِينَ has no written alef where the plain text writes العالمين.
        let steps = aligner.align(words("الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ"), to: expected(1, 2, "ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ"))
        XCTAssertEqual(steps.map(\.kind), [.matched, .matched, .matched, .matched])
        XCTAssertEqual(steps.map(\.expected), (1 ... 4).map { [word(1, 2, $0)] })
        XCTAssertEqual(steps.map(\.similarity), [1, 1, 1, 1])
    }

    func testTwoPlainWordsWrittenAsOneUthmaniWordAlignTogether() {
        // 2:21 opens with يَٰٓأَيُّهَا, written يا أيها in the plain text.
        let steps = aligner.align(words("يا أيها الناس اعبدوا"), to: expected(2, 21, "يَٰٓأَيُّهَا ٱلنَّاسُ ٱعۡبُدُواْ"))
        XCTAssertEqual(steps.map(\.kind), [.matched, .matched, .matched])
        XCTAssertEqual(steps.first?.recognized.map(\.text), ["يا", "أيها"])
        XCTAssertEqual(steps.first?.expected, [word(2, 21, 1)])
    }

    func testASkippedWordIsOmitted() {
        let steps = aligner.align(words("قل هو احد"), to: expected(112, 1, "قُلۡ هُوَ ٱللَّهُ أَحَدٌ"))
        XCTAssertEqual(steps.map(\.kind), [.matched, .matched, .omitted, .matched])
        XCTAssertEqual(steps[2].expected, [word(112, 1, 3)])
        XCTAssertEqual(steps[2].recognized, [])
    }

    func testARepeatedWordIsInserted() {
        // Either هو may be the inserted one: both alignments cost the same.
        let steps = aligner.align(words("قل هو هو الله احد"), to: expected(112, 1, "قُلۡ هُوَ ٱللَّهُ أَحَدٌ"))
        XCTAssertEqual(steps.filter { $0.kind == .matched }.flatMap(\.expected), (1 ... 4).map { word(112, 1, $0) })
        XCTAssertEqual(steps.filter { $0.kind == .inserted }.map { $0.recognized.map(\.text) }, [["هو"]])
        XCTAssertEqual(steps.count, 5)
    }

    func testAWrongWordInItsPlaceIsMismatched() {
        let steps = aligner.align(words("قل هو الله الصمد"), to: expected(112, 1, "قُلۡ هُوَ ٱللَّهُ أَحَدٌ"))
        XCTAssertEqual(steps.map(\.kind), [.matched, .matched, .matched, .mismatched])
        XCTAssertLessThan(steps[3].similarity, WordAligner.matchSimilarity)
    }

    func testTheBasmalaBeforeAVerseIsInserted() {
        let steps = aligner.align(words("بسم الله الرحمن الرحيم الم"), to: expected(2, 1, "الٓمٓ"))
        XCTAssertEqual(steps.map(\.kind), [.inserted, .inserted, .inserted, .inserted, .matched])
    }

    func testAStepKeepsItsRecitedFrames() {
        let recognized = [
            RecognizedWord(text: "يا", frames: 3 ... 5),
            RecognizedWord(text: "ايها", frames: 6 ... 9),
            RecognizedWord(text: "الناس", frames: 11 ... 16),
        ]
        let steps = aligner.align(recognized, to: expected(2, 21, "يَٰٓأَيُّهَا ٱلنَّاسُ"))
        XCTAssertEqual(steps.map(\.frames), [3 ... 9, 11 ... 16])
    }

    func testOneExpectedTextCanCoverTwoWords() {
        // 15:7's first token لَّوۡمَا writes the canonical words 1 and 2.
        let expected = [
            ExpectedWordText(words: [word(15, 7, 1), word(15, 7, 2)], text: "لَّوۡمَا"),
            ExpectedWordText(words: [word(15, 7, 3)], text: "تَأۡتِينَا"),
        ]
        let steps = aligner.align(words("لوما تأتينا"), to: expected)
        XCTAssertEqual(steps.map(\.kind), [.matched, .matched])
        XCTAssertEqual(steps.first?.expected, [word(15, 7, 1), word(15, 7, 2)])
    }

    func testEmptyInputs() {
        XCTAssertEqual(aligner.align([], to: []), [])
        XCTAssertEqual(aligner.align(words("قل"), to: []).map(\.kind), [.inserted])
        XCTAssertEqual(aligner.align([], to: expected(112, 1, "قُلۡ هُوَ")).map(\.kind), [.omitted, .omitted])
    }

    func testHamzaSeatsAreFolded() {
        XCTAssertEqual(WordAligner.letters("يُؤۡمِنُونَ"), WordAligner.letters("يومنون"))
        // ٱلۡمَلَٰٓئِكَةِ writes its alef as a dagger alef, which the alef-free comparison forgives.
        XCTAssertEqual(WordAligner.similarity(WordAligner.letters("ٱلۡمَلَٰٓئِكَةِ"), WordAligner.letters("الملائكة")), 1)
        XCTAssertEqual(WordAligner.letters("ءَايَٰتِ"), WordAligner.letters("ايت"))
    }

    // MARK: Private

    private let aligner = WordAligner()
    private let quran = Quran.hafsMadani1405

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: AyahNumber(quran: quran, sura: sura, ayah: ayah)!, wordNumber: number)
    }

    private func words(_ transcript: String) -> [RecognizedWord] {
        RecognizedWord.words(of: transcript)
    }

    /// One expected text per token, numbered from 1 (true for all but six ayahs).
    private func expected(_ sura: Int, _ ayah: Int, _ text: String) -> [ExpectedWordText] {
        text.split(separator: " ").enumerated().map { index, token in
            ExpectedWordText(words: [word(sura, ayah, index + 1)], text: String(token))
        }
    }
}
