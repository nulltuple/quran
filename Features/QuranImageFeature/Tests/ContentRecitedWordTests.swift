//
//  ContentRecitedWordTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import AnnotationsService
import ImageService
import QuranAnnotations
import QuranKit
import QuranText
import ReadingService
import TestResources
import WordTextService
import XCTest
@testable import QuranImageFeature

/// Page 3 of the Madani 1405 images, where 2:7 has a pause-mark glyph after its 6th word, so its
/// 7th word is glyph 8.
@MainActor
final class ContentRecitedWordTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        previousReading = ReadingPreferences.shared.reading
        previousLanguage = WordByWordPreferences.shared.language
        ReadingPreferences.shared.reading = reading
        WordByWordPreferences.shared.language = .off
    }

    override func tearDown() {
        ReadingPreferences.shared.reading = previousReading
        WordByWordPreferences.shared.language = previousLanguage
        super.tearDown()
    }

    func test_highlightsTheRecitedWordsGlyph() async {
        let model = makeModel()
        await model.loadImagePage()

        recite(word(7, 7))

        XCTAssertEqual(model.decorations.wordHighlight, word(7, 8))
        XCTAssertEqual(model.decorations.scrollWord, word(7, 8))
        XCTAssertNil(model.decorations.wordCaption, "Word-by-word meanings are off")
    }

    func test_thePointedWordWinsOverTheRecitedWord() async {
        let model = makeModel()
        await model.loadImagePage()

        recite(word(7, 7))
        service.overlays.pointedWord = word(6, 1)

        XCTAssertEqual(model.decorations.wordHighlight, word(6, 1))
    }

    func test_captionsTheRecitedWordWithItsMeaning() async throws {
        WordByWordPreferences.shared.language = .english
        let model = makeModel()
        await model.loadImagePage()

        recite(word(7, 7))
        try await waitUntil { model.decorations.wordCaption != nil }

        XCTAssertEqual(model.decorations.wordCaption, "and on")
    }

    func test_readerScrollStopsFollowingTheWordUntilTheNextAyah() async {
        let model = makeModel()
        await model.loadImagePage()
        recite(word(7, 7))

        model.onReaderScroll()
        XCTAssertNil(model.recitedScrollWord)
        XCTAssertEqual(model.decorations.wordHighlight, word(7, 8), "The highlight stays")

        service.overlays.playingVerses = [verse(8)]
        service.overlays.recitedWord = word(8, 1)
        XCTAssertEqual(model.recitedScrollWord, word(8, 1))
    }

    func test_noRecitedWordAfterPlaybackStops() async {
        let model = makeModel()
        await model.loadImagePage()
        recite(word(7, 7))

        service.overlays.recitedWord = nil

        XCTAssertNil(model.decorations.wordHighlight)
        XCTAssertNil(model.recitedScrollWord)
    }

    func test_practiceMaskHidesLaterVersesAndTheCurrentVersesUnrevealedGlyphs() async throws {
        let model = makeModel()
        await model.loadImagePage()
        XCTAssertEqual(model.decorations.maskedWords, [])

        // Seven words of 2:7 revealed: its 7th word is glyph 8, after the pause mark.
        service.overlays.practiceMask = PracticeMask(hiddenVerses: [verse(8)], partialVerse: verse(7), revealedWords: 7)

        let masked = model.decorations.maskedWords
        XCTAssertFalse(masked.contains { $0.verse == verse(6) })
        XCTAssertFalse(masked.contains(word(7, 8)))
        XCTAssertTrue(masked.contains(word(7, 9)))
        let frames = try XCTUnwrap(model.imagePage?.wordFrames)
        XCTAssertTrue(Set(frames.wordFramesForVerse(verse(8)).map(\.word)).isSubset(of: masked))
        XCTAssertEqual(masked.filter { $0.verse == verse(7) }.map(\.wordNumber).min(), 9)
    }

    func test_practiceMaskWithNothingRevealedHidesTheWholeVerse() async throws {
        let model = makeModel()
        await model.loadImagePage()

        service.overlays.practiceMask = PracticeMask(hiddenVerses: [], partialVerse: verse(7), revealedWords: 0)

        let frames = try XCTUnwrap(model.imagePage?.wordFrames)
        XCTAssertEqual(model.decorations.maskedWords, Set(frames.wordFramesForVerse(verse(7)).map(\.word)))
    }

    // MARK: Private

    private let reading = Reading.hafs_1405
    private let service = VerseOverlayService()
    private var previousReading: Reading = .hafs_1405
    private var previousLanguage: WordByWordLanguage = .off

    private func verse(_ ayah: Int) -> AyahNumber {
        AyahNumber(quran: reading.quran, sura: 2, ayah: ayah)!
    }

    private func word(_ ayah: Int, _ number: Int) -> Word {
        Word(verse: verse(ayah), wordNumber: number)
    }

    private func recite(_ word: Word) {
        service.overlays.playingVerses = [word.verse]
        service.overlays.recitedWord = word
    }

    private func makeModel() -> ContentImageViewModel {
        ContentImageViewModel(
            reading: reading,
            page: reading.quran.pages[2],
            imageDataService: ImageDataService(
                ayahInfoDatabase: TestResources.resourceURL("hafs_1405_ayahinfo.db"),
                imagesURL: TestResources.testDataURL.appendingPathComponent("images"),
                ayahMarkerURL: nil
            ),
            overlayService: service,
            wordByWordService: WordByWordService(fileURL: TestResources.resourceURL("word_by_word.db"))
        )
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
