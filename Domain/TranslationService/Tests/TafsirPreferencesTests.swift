//
//  TafsirPreferencesTests.swift
//

import QuranText
import Utilities
import XCTest
@testable import TranslationService

final class TafsirPreferencesTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        preferences.reset()
    }

    override func tearDown() {
        preferences.reset()
        super.tearDown()
    }

    func testFirstTafsirIsShownUntilOneIsSelected() {
        XCTAssertNil(preferences.selectedTafsirId)
        XCTAssertEqual(preferences.selectedTafsir(from: [muyassar, ibnKathir]), muyassar)
        XCTAssertNil(preferences.selectedTafsir(from: []))
    }

    func testSelectedTafsirIsKept() {
        preferences.selectedTafsirId = ibnKathir.id

        XCTAssertEqual(preferences.selectedTafsir(from: [muyassar, ibnKathir]), ibnKathir)
    }

    func testDeletedSelectedTafsirFallsBackToTheFirst() {
        preferences.selectedTafsirId = ibnKathir.id

        XCTAssertEqual(preferences.selectedTafsir(from: [muyassar]), muyassar)
    }

    // MARK: Private

    private let preferences = TafsirPreferences.shared
    private let muyassar = tafsir(id: 64, fileName: "quran.ar.muyassar.db")
    private let ibnKathir = tafsir(id: 58, fileName: "quran.ar.ibnkathir.db")
}

private func tafsir(id: Int, fileName: String) -> Translation {
    Translation(
        id: id,
        displayName: fileName,
        translator: nil,
        translatorForeign: nil,
        fileURL: URL(validURL: "https://example.invalid/\(id).zip"),
        fileName: fileName,
        languageCode: "ar",
        version: 1,
        installedVersion: 1
    )
}
