//
//  ContentTranslationWordByWordTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import AnnotationsService
import NoorUI
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
        WordByWordPreferences.shared.language = .off
    }

    override func tearDown() {
        WordByWordPreferences.shared.language = previousLanguage
        super.tearDown()
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

    func test_ignoresARecitedWordOnAnotherPage() async throws {
        let sut = try await makeSUT()

        service.overlays.recitedWord = Word(verse: verse.sura.quran.suras[112].firstVerse, wordNumber: 1)

        XCTAssertNil(sut.recitedWord)
    }

    // MARK: Private

    private let service = VerseOverlayService()
    private let verse = AyahNumber(quran: .hafsMadani1405, sura: 2, ayah: 2)!
    private var previousLanguage: WordByWordLanguage = .off

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
