//
//  WordStudyServiceTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import QuranKit
import QuranText
import TestResources
import WordTextService
import XCTest

final class WordStudyServiceTests: XCTestCase {
    // MARK: Internal

    func test_alHamduIsTheArticleAndANominativeNoun() async throws {
        let loaded = try await service.study(of: word(1, 2, 1), language: .english)
        let study = try XCTUnwrap(loaded)

        XCTAssertEqual(study.arabic, "ٱلْحَمْدُ")
        XCTAssertEqual(study.meaning, "All praises and thanks")
        XCTAssertEqual(study.transliteration, "al-ḥamdu")
        let segments = study.morphology.segments
        XCTAssertEqual(segments.map(\.text), ["ٱلْ", "حَمْدُ"])
        XCTAssertEqual(segments[0].grammar, WordGrammar(part: .particle, tag: "DET", role: .prefix))
        XCTAssertEqual(segments[0].lemma?.text, "ال")
        XCTAssertNil(segments[0].root)
        XCTAssertEqual(
            segments[1].grammar,
            WordGrammar(part: .noun, tag: "N", role: .stem, gender: .masculine, grammaticalCase: .nominative)
        )
    }

    func test_rootAndLemmaCountsMatchTheCorpus() async throws {
        let loaded = try await service.study(of: word(1, 2, 1), language: .english)
        let study = try XCTUnwrap(loaded)
        let head = try XCTUnwrap(study.morphology.headSegment)

        XCTAssertEqual(head.root?.letters, "حمد")
        XCTAssertEqual(head.root?.spacedLetters, "ح م د")
        XCTAssertEqual(head.root?.occurrences, 68)
        XCTAssertEqual(head.lemma?.text, "حَمْد")
        XCTAssertEqual(head.lemma?.occurrences, 43)
    }

    func test_verbGrammar() async throws {
        // 2:3 word 2, يُؤْمِنُونَ: "believe", form IV imperfect, 3rd person masculine plural, indicative.
        let loaded = try await service.study(of: word(2, 3, 2), language: .english)
        let study = try XCTUnwrap(loaded)
        let head = try XCTUnwrap(study.morphology.headSegment)

        XCTAssertEqual(head.grammar.part, .verb)
        XCTAssertEqual(head.grammar.verbForm, 4)
        XCTAssertEqual(head.grammar.aspect, .imperfect)
        XCTAssertEqual(head.grammar.voice, .active)
        XCTAssertEqual(head.grammar.mood, .indicative)
        XCTAssertEqual(head.grammar.person, 3)
        XCTAssertEqual(head.grammar.gender, .masculine)
        XCTAssertEqual(head.grammar.number, .plural)
        XCTAssertEqual(head.root?.letters, "أمن")
        XCTAssertEqual(study.morphology.segments.last?.grammar.role, .suffix)
    }

    func test_meaningFollowsTheLanguageAndFallsBackToEnglish() async throws {
        let bengali = try await service.study(of: word(1, 1, 1), language: .bengali)
        let off = try await service.study(of: word(1, 1, 1), language: .off)

        XCTAssertEqual(bengali?.meaning, "নামে")
        XCTAssertEqual(off?.meaning, "In (the) name")
    }

    func test_splitBadaMaWordsMapOneSegmentEach() async throws {
        // QAC keeps بَعْدَ مَا as one word in 13:37; the canonical words are 8 and 9.
        let first = try await service.study(of: word(13, 37, 8), language: .english)
        let second = try await service.study(of: word(13, 37, 9), language: .english)

        XCTAssertEqual(first?.arabic, "بَعْدَ")
        XCTAssertEqual(second?.arabic, "مَا")
        XCTAssertEqual(first?.meaning, "after what")
    }

    func test_noStudyForAWordPastTheAyahEnd() async throws {
        let study = try await service.study(of: word(1, 1, 5), language: .english)

        XCTAssertNil(study)
    }

    func test_occurrencesOfARootPageInQuranOrder() async throws {
        let study = try await service.study(of: word(1, 2, 1), language: .english)
        let head = try XCTUnwrap(study?.morphology.headSegment)
        let root = try XCTUnwrap(head.root)

        let first = try await service.occurrences(of: .root(root), quran: quran, after: nil, limit: 3, language: .english)
        XCTAssertEqual(first.map(\.word), [word(1, 2, 1), word(2, 30, 20), word(2, 267, 29)])
        XCTAssertEqual(first.first?.arabic, "ٱلْحَمْدُ")
        XCTAssertEqual(first.first?.meaning, "All praises and thanks")
        XCTAssertNil(first.last?.meaning, "The test word data stops at 2:181")

        let next = try await service.occurrences(of: .root(root), quran: quran, after: first.last?.word, limit: 100, language: .english)
        XCTAssertEqual(next.first.map { $0.word > word(2, 267, 29) }, true)
        XCTAssertEqual(first.count + next.count, 68, "ح م د is one segment in each of its 68 words")
        XCTAssertEqual(Set((first + next).map(\.word)).count, 68)
    }

    func test_occurrencesOfALemma() async throws {
        let study = try await service.study(of: word(1, 2, 1), language: .english)
        let head = try XCTUnwrap(study?.morphology.headSegment)
        let lemma = try XCTUnwrap(head.lemma)

        let all = try await service.occurrences(of: .lemma(lemma), quran: quran, after: nil, limit: 100, language: .english)

        XCTAssertEqual(all.count, 43)
        XCTAssertEqual(all.map(\.word), all.map(\.word).sorted())
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405
    private let service = WordStudyService(
        morphologyFileURL: TestResources.resourceURL("quran_morphology.db"),
        wordByWordFileURL: TestResources.resourceURL("word_by_word.db")
    )

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: AyahNumber(quran: quran, sura: sura, ayah: ayah)!, wordNumber: number)
    }
}
