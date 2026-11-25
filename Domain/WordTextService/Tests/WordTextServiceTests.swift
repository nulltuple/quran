//
//  WordTextServiceTests.swift
//
//
//  Created by Mohamed Afifi on 2022-01-17.
//

import QuranKit
import QuranText
import TestResources
import XCTest
@testable import WordTextService

class WordTextServiceTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        previousType = preferences.wordTextType
        previousLanguage = WordByWordPreferences.shared.language
        service = WordTextService(fileURL: TestResources.resourceURL("word_by_word.db"))
    }

    override func tearDown() {
        preferences.wordTextType = previousType
        WordByWordPreferences.shared.language = previousLanguage
        super.tearDown()
    }

    func testWordEnglishTranslation() async throws {
        preferences.wordTextType = .translation
        WordByWordPreferences.shared.language = .off
        let text = try await service.textForWord(glyph(110, 3, 3), reading: .hafs_1405)
        XCTAssertEqual(text, "(of) your Lord")
    }

    func testWordEnglishTransliteration() async throws {
        preferences.wordTextType = .transliteration
        let text = try await service.textForWord(glyph(110, 3, 3), reading: .hafs_1405)
        XCTAssertEqual(text, "rabbika")
    }

    func testWordBengaliTranslationFollowsTheReaderLanguage() async throws {
        preferences.wordTextType = .translation
        WordByWordPreferences.shared.language = .bengali
        let text = try await service.textForWord(glyph(1, 1, 2), reading: .hafs_1405)
        XCTAssertEqual(text, "আল্লাহ (র)")
    }

    func testPointerCoversAyahsTheOldDatabaseLacked() async throws {
        // The old words.db covered 857 ayahs; 2:181 was not one of them.
        preferences.wordTextType = .translation
        WordByWordPreferences.shared.language = .english
        let text = try await service.textForWord(glyph(2, 181, 5), reading: .hafs_1405)
        XCTAssertEqual(text, "he (has) heard [it]", "Glyph 5 is word 5: بَعْدَ مَا is two glyphs")
    }

    func testMarkGlyphHasNoText() async throws {
        preferences.wordTextType = .translation
        // 2:2 glyph 5 is a pause mark.
        let text = try await service.textForWord(glyph(2, 2, 5), reading: .hafs_1405)
        XCTAssertNil(text)
    }

    func testReadingWithoutAVerifiedMappingHasNoText() async throws {
        preferences.wordTextType = .translation
        let text = try await service.textForWord(glyph(110, 3, 3), reading: .hafs_1421)
        XCTAssertNil(text)
    }

    func testIsWordPointerActiveDefaultsToFalse() {
        XCTAssertFalse(preferences.isWordPointerActive)
    }

    func testIsWordPointerActivePersists() {
        preferences.isWordPointerActive = true
        XCTAssertTrue(preferences.isWordPointerActive)

        preferences.isWordPointerActive = false
        XCTAssertFalse(preferences.isWordPointerActive)
    }

    // MARK: Private

    private var service: WordTextService!
    private let preferences = WordTextPreferences.shared
    private var previousType: WordTextType = .translation
    private var previousLanguage: WordByWordLanguage = .off

    private func glyph(_ sura: Int, _ ayah: Int, _ position: Int) -> Word {
        Word(verse: AyahNumber(quran: Quran.hafsMadani1405, sura: sura, ayah: ayah)!, wordNumber: position)
    }
}
