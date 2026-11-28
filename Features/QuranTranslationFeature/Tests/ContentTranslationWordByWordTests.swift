//
//  ContentTranslationWordByWordTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import AnnotationsService
import NoorUI
import QuranAnnotations
import QuranKit
import QuranText
import WordTextService
import XCTest
@testable import QuranTranslationFeature

@MainActor
final class ContentTranslationWordByWordTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        previousLanguage = WordByWordPreferences.shared.language
        previousShowsTransliteration = WordByWordPreferences.shared.showsTransliteration
        WordByWordPreferences.shared.language = .off
        WordByWordPreferences.shared.showsTransliteration = false
    }

    override func tearDown() {
        WordByWordPreferences.shared.language = previousLanguage
        WordByWordPreferences.shared.showsTransliteration = previousShowsTransliteration
        super.tearDown()
    }

    func test_practiceRemovesUnrevealedArabicMeaningsAndTransliterationFromTheRow() async throws {
        WordByWordPreferences.shared.language = .english
        WordByWordPreferences.shared.showsTransliteration = true
        let sut = try await makeSUT()
        let original = try XCTUnwrap(arabicItem(in: sut))
        service.overlays.practiceMask = PracticeMask(hiddenVerses: [], partialVerse: verse, revealedWords: 1)

        let masked = try XCTUnwrap(arabicItem(in: sut))
        XCTAssertTrue(masked.text.text.contains("ذَٰلِكَ"))
        XCTAssertFalse(masked.text.text.contains("ٱلۡكِتَٰبُ"))
        XCTAssertNil(masked.words)
        XCTAssertNil(masked.wordNumbers)
        service.overlays.practiceMask = nil
        XCTAssertEqual(arabicItem(in: sut), original)
    }

    func test_practicePartialVerseHighlightsActiveWordAndRevealedMistakes() async throws {
        let sut = try await makeSUT()
        service.overlays.practiceMask = PracticeMask(
            hiddenVerses: [],
            partialVerse: verse,
            revealedWords: 3,
            mistakeWords: [Word(verse: verse, wordNumber: 2), Word(verse: verse, wordNumber: 5)],
            activeWord: Word(verse: verse, wordNumber: 3)
        )

        let masked = try XCTUnwrap(arabicItem(in: sut))
        XCTAssertEqual(masked.practiceActiveTokens, 3 ... 3)
        XCTAssertEqual(masked.practiceMistakeTokens, [2 ... 2], "hidden word 5 must not be highlighted")
    }

    func testMeaningIsOptionalAndCheckShowsArabicEvenWhenReaderNormallyHidesIt() async throws {
        let sut = try await makeSUT()
        sut.showArabicText = false
        sut.commitLoadedContent(verses: [verse], translations: [makeTranslation(id: 1)], verseTexts: [verse: makeVerseText(translationCount: 1)])
        func meaningRows() -> Int {
            sut.items(quranFont: .uthmanicHafs).filter {
                if case .translationTextChunk = $0 {
                    true
                } else {
                    false
                }
            }.count
        }
        service.overlays.practiceMask = PracticeMask(hiddenVerses: [], partialVerse: verse, revealedWords: 0)
        XCTAssertEqual(arabicItem(in: sut)?.text.text, "…", "unmapped script fails closed")
        XCTAssertEqual(arabicItem(in: sut)?.offersMeaningCue, true)
        XCTAssertEqual(meaningRows(), 0)
        service.overlays.practiceMask?.showsMeaning = true
        XCTAssertEqual(meaningRows(), 1)
        XCTAssertEqual(arabicItem(in: sut)?.text.text, "…")
        service.overlays.practiceMask = PracticeMask(hiddenVerses: [verse], partialVerse: nil, revealedWords: 0)
        XCTAssertEqual(arabicItem(in: sut)?.offersMeaningCue, false)
        XCTAssertEqual(meaningRows(), 0)
        service.overlays.practiceMask = PracticeMask(hiddenVerses: [], partialVerse: nil, revealedWords: 0)
        service.overlays.practiceMask?.checkedVerse = verse
        XCTAssertTrue(arabicItem(in: sut)?.text.text.contains("Arabic") == true)
        service.overlays.practiceMask = nil
        XCTAssertNil(arabicItem(in: sut))
    }

    func test_highlightsTheRecitedWordInTheArabicText() async throws {
        let sut = try await makeSUT()

        service.overlays.recitedWord = Word(verse: verse, wordNumber: 4)

        let arabic = try XCTUnwrap(arabicItem(in: sut))
        XCTAssertEqual(arabic.highlightedTokens, 4 ... 4)
        XCTAssertNil(arabic.words, "Word-by-word meanings are off")
    }

    func test_showsEachWordWithItsMeaning() async throws {
        WordByWordPreferences.shared.language = .bengali
        let sut = try await makeSUT()
        try await waitUntil { !sut.wordMeanings.isEmpty }

        let words = try XCTUnwrap(arabicItem(in: sut)?.words)
        XCTAssertEqual(words.count, 7)
        XCTAssertEqual(words[0], QuranWordMeaning(arabic: "ذَٰلِكَ", meaning: "(এটা) সেই"))
        XCTAssertEqual(words[3].arabic, "رَيۡبَۛ")
    }

    func test_showsEachWordsTransliterationBetweenItAndItsMeaning() async throws {
        WordByWordPreferences.shared.language = .english
        WordByWordPreferences.shared.showsTransliteration = true
        let sut = try await makeSUT()
        try await waitUntil { !sut.wordTransliterations.isEmpty }

        let words = try XCTUnwrap(arabicItem(in: sut)?.words)
        XCTAssertEqual(words[0], QuranWordMeaning(arabic: "ذَٰلِكَ", meaning: "That", transliteration: "dhālika"))
        XCTAssertEqual(words[1].transliteration, "l-kitābu")
    }

    func test_noTransliterationUntilTheReaderTurnsItOn() async throws {
        WordByWordPreferences.shared.language = .english
        let sut = try await makeSUT()
        try await waitUntil { !sut.wordMeanings.isEmpty }

        let words = try XCTUnwrap(arabicItem(in: sut)?.words)
        XCTAssertNil(words[0].transliteration)

        WordByWordPreferences.shared.showsTransliteration = true
        try await waitUntil { arabicItem(in: sut)?.words?[0].transliteration == "dhālika" }
    }

    func test_turningTransliterationOffRemovesIt() async throws {
        WordByWordPreferences.shared.language = .bengali
        WordByWordPreferences.shared.showsTransliteration = true
        let sut = try await makeSUT()
        try await waitUntil { !sut.wordTransliterations.isEmpty }

        WordByWordPreferences.shared.showsTransliteration = false
        try await waitUntil { sut.wordTransliterations.isEmpty }

        XCTAssertEqual(arabicItem(in: sut)?.words?[0], QuranWordMeaning(arabic: "ذَٰلِكَ", meaning: "(এটা) সেই"))
    }

    func test_transliterationAloneShowsNoWords() async throws {
        WordByWordPreferences.shared.showsTransliteration = true
        let sut = try await makeSUT()

        XCTAssertNil(arabicItem(in: sut)?.words, "Word-by-word meanings are off")
        XCTAssertTrue(sut.wordTransliterations.isEmpty)
    }

    func test_turningMeaningsOffShowsTheTextAgain() async throws {
        WordByWordPreferences.shared.language = .english
        let sut = try await makeSUT()
        try await waitUntil { arabicItem(in: sut)?.words != nil }

        WordByWordPreferences.shared.language = .off

        XCTAssertNil(arabicItem(in: sut)?.words)
    }

    func test_noWordsWhenTheTextSplitsWordsDifferently() async throws {
        WordByWordPreferences.shared.language = .english
        let sut = try await makeSUT(arabicText: "ذَٰلِكَ ٱلۡكِتَٰبُ")
        try await waitUntil { !sut.wordMeanings.isEmpty }

        service.overlays.recitedWord = Word(verse: verse, wordNumber: 2)

        let arabic = try XCTUnwrap(arabicItem(in: sut))
        XCTAssertNil(arabic.words)
        XCTAssertNil(arabic.highlightedWord)
        XCTAssertNil(arabic.highlightedTokens)
    }

    func test_showsTwoWordsTheTextWritesAsOneTokenTogether() async throws {
        // 15:7's text writes QUL's words لَّوۡ and مَا as one token, لَّوۡمَا.
        WordByWordPreferences.shared.language = .english
        let verse = AyahNumber(quran: .hafsMadani1405, sura: 15, ayah: 7)!
        let sut = try await makeSUT(verse: verse, arabicText: "لَّوۡمَا تَأۡتِينَا بِٱلۡمَلَٰٓئِكَةِ إِن كُنتَ مِنَ ٱلصَّٰدِقِينَ")
        try await waitUntil { arabicItem(in: sut)?.words != nil }

        service.overlays.recitedWord = Word(verse: verse, wordNumber: 2)

        let arabic = try XCTUnwrap(arabicItem(in: sut))
        XCTAssertEqual(arabic.words?.count, 7)
        XCTAssertEqual(arabic.words?.first, QuranWordMeaning(arabic: "لَّوۡمَا", meaning: "Why not"))
        XCTAssertEqual(arabic.highlightedWord, 1, "QUL word 2 is part of the first token")
        XCTAssertEqual(arabic.highlightedTokens, 1 ... 1)

        service.overlays.recitedWord = Word(verse: verse, wordNumber: 3)
        XCTAssertEqual(arabicItem(in: sut)?.highlightedWord, 2)
    }

    func test_showsOneWordTheTextWritesAsTwoTokensTogether() async throws {
        // 37:130's text writes QUL's word إِلۡ يَاسِينَ as two tokens.
        WordByWordPreferences.shared.language = .english
        let verse = AyahNumber(quran: .hafsMadani1405, sura: 37, ayah: 130)!
        let sut = try await makeSUT(verse: verse, arabicText: "سَلَٰمٌ عَلَىٰٓ إِلۡ يَاسِينَ")
        try await waitUntil { arabicItem(in: sut)?.words != nil }

        service.overlays.recitedWord = Word(verse: verse, wordNumber: 3)

        let arabic = try XCTUnwrap(arabicItem(in: sut))
        XCTAssertEqual(arabic.words?.map(\.arabic), ["سَلَٰمٌ", "عَلَىٰٓ", "إِلۡ يَاسِينَ"])
        XCTAssertEqual(arabic.words?.last?.meaning, "Elijah")
        XCTAssertEqual(arabic.highlightedWord, 3)
        XCTAssertEqual(arabic.highlightedTokens, 3 ... 4)
    }

    func test_eachWordOpensWordStudyByItsFirstCanonicalWord() async throws {
        // 15:7's first token, لَّوۡمَا, shows QUL words 1 and 2; word study opens word 1.
        WordByWordPreferences.shared.language = .english
        let verse = AyahNumber(quran: .hafsMadani1405, sura: 15, ayah: 7)!
        let sut = try await makeSUT(verse: verse, arabicText: "لَّوۡمَا تَأۡتِينَا بِٱلۡمَلَٰٓئِكَةِ إِن كُنتَ مِنَ ٱلصَّٰدِقِينَ")
        sut.onWordTapped = { _ in }
        try await waitUntil { arabicItem(in: sut)?.words != nil }

        XCTAssertEqual(arabicItem(in: sut)?.wordNumbers, [1, 3, 4, 5, 6, 7, 8])
    }

    func test_wordsAreNotTappableWithoutWordStudy() async throws {
        WordByWordPreferences.shared.language = .english
        let sut = try await makeSUT()
        try await waitUntil { arabicItem(in: sut)?.words != nil }

        XCTAssertNil(arabicItem(in: sut)?.wordNumbers)
    }

    func test_aWordURLOpensWordStudyForThatWord() async throws {
        let sut = try await makeSUT()
        var studied: [Word] = []
        sut.onWordTapped = { studied.append($0) }

        let url = try XCTUnwrap(TranslationURL(url: TranslationURL.word(sura: 2, ayah: 2, word: 3).url))
        sut.openURL(url)

        XCTAssertEqual(studied, [Word(verse: verse, wordNumber: 3)])
    }

    func test_ignoresARecitedWordOnAnotherPage() async throws {
        let sut = try await makeSUT()

        service.overlays.recitedWord = Word(verse: verse.sura.quran.suras[112].firstVerse, wordNumber: 1)

        XCTAssertNil(sut.recitedWord)
    }

    // MARK: Private

    private let service = VerseOverlayService()
    private let verse = AyahNumber(quran: .hafsMadani1405, sura: 2, ayah: 2)!
    private var previousLanguage: WordByWordLanguage = .off
    private var previousShowsTransliteration = false

    private func makeSUT(
        verse: AyahNumber? = nil,
        arabicText: String = "ذَٰلِكَ ٱلۡكِتَٰبُ لَا رَيۡبَۛ فِيهِۛ هُدٗى لِّلۡمُتَّقِينَ"
    ) async throws -> ContentTranslationViewModel {
        let verse = verse ?? self.verse
        let sut = makeContentTranslationViewModel(overlayService: service)
        sut.verses = [verse]
        sut.commitLoadedContent(
            verses: [verse],
            translations: [],
            verseTexts: [verse: VerseText(arabicText: QuranText(arabicText), translations: [], arabicPrefix: [], arabicSuffix: [])]
        )
        try await waitUntil { !sut.wordLayouts.isEmpty }
        return sut
    }

    private func arabicItem(in sut: ContentTranslationViewModel) -> TranslationArabicText? {
        for item in sut.items(quranFont: .uthmanicHafs) {
            if case .arabicText(let arabic, _) = item {
                return arabic
            }
        }
        return nil
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
