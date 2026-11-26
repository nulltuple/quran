//
//  TafsirViewModelTests.swift
//

import GRDB
import QuranKit
import QuranResources
import QuranText
import TranslationServiceFake
import Utilities
import VerseTextPersistence
import XCTest
@testable import QuranTextKit
@testable import TafsirFeature
@testable import TranslationService

@MainActor
final class TafsirViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        TafsirPreferences.shared.reset()
        localTranslations = LocalTranslationsFake()
        // Muyassar explains 2:2 and 2:3 together, on 2:3 (verse index 10); Ibn Kathir explains each ayah.
        databases = [
            muyassar.id: try Self.makeTafsirDatabase(rows: [
                (2, 1, "Muyassar 2:1"),
                (2, 2, 10),
                (2, 3, "Muyassar 2:2-3"),
                (2, 4, "Muyassar 2:4"),
            ]),
            ibnKathir.id: try Self.makeTafsirDatabase(rows: [
                (2, 1, "Ibn Kathir 2:1"),
                (2, 2, "Ibn Kathir 2:2"),
                (2, 3, "Ibn Kathir 2:3"),
            ]),
        ]
    }

    override func tearDown() async throws {
        TafsirPreferences.shared.reset()
        localTranslations.tearDown()
        for url in databases.values {
            try? FileManager.default.removeItem(at: url)
        }
        try await super.tearDown()
    }

    func testListsOnlyDownloadedTafsirsAndShowsTheSelectedOne() async throws {
        try await installTranslations()
        TafsirPreferences.shared.selectedTafsirId = ibnKathir.id
        let sut = makeSUT(startingAt: verse(2, 1))

        await sut.reloadTafsirs()

        XCTAssertEqual(Set(sut.tafsirs.map(\.id)), [muyassar.id, ibnKathir.id])
        XCTAssertEqual(sut.selectedTafsir?.id, ibnKathir.id)
        XCTAssertEqual(passage(of: sut)?.text.text?.text, "Ibn Kathir 2:1")
    }

    func testAyahInAPassageShowsThePassageAndNextSkipsPastIt() async throws {
        try await installTranslations()
        TafsirPreferences.shared.selectedTafsirId = muyassar.id
        var changedVerses: [AyahNumber] = []
        let sut = makeSUT(startingAt: verse(2, 2)) { changedVerses.append($0) }

        await sut.reloadTafsirs()

        let shown = try XCTUnwrap(passage(of: sut))
        XCTAssertEqual(shown.text.verses, [verse(2, 2), verse(2, 3)])
        XCTAssertEqual(shown.text.text?.text, "Muyassar 2:2-3")
        XCTAssertFalse(shown.arabicText.text.isEmpty)
        XCTAssertEqual(sut.nextVerse, verse(2, 4))
        XCTAssertEqual(sut.previousVerse, verse(2, 1))

        await sut.next()

        XCTAssertEqual(sut.verse, verse(2, 4))
        XCTAssertEqual(passage(of: sut)?.text.text?.text, "Muyassar 2:4")
        XCTAssertEqual(changedVerses, [verse(2, 4)])
    }

    func testPreviousFromTheEndOfAPassageGoesBeforeIt() async throws {
        try await installTranslations()
        TafsirPreferences.shared.selectedTafsirId = muyassar.id
        let sut = makeSUT(startingAt: verse(2, 3))
        await sut.reloadTafsirs()

        await sut.previous()

        XCTAssertEqual(sut.verse, verse(2, 1))
        XCTAssertEqual(passage(of: sut)?.text.verses, [verse(2, 1)])
    }

    func testSelectingAnotherTafsirKeepsTheAyahAndRemembersTheChoice() async throws {
        try await installTranslations()
        TafsirPreferences.shared.selectedTafsirId = muyassar.id
        let sut = makeSUT(startingAt: verse(2, 2))
        await sut.reloadTafsirs()

        await sut.select(try XCTUnwrap(sut.tafsirs.first { $0.id == ibnKathir.id }))

        XCTAssertEqual(sut.verse, verse(2, 2))
        XCTAssertEqual(passage(of: sut)?.text.verses, [verse(2, 2)])
        XCTAssertEqual(passage(of: sut)?.text.text?.text, "Ibn Kathir 2:2")
        XCTAssertEqual(TafsirPreferences.shared.selectedTafsirId, ibnKathir.id)
    }

    func testNoDownloadedTafsirShowsTheEmptyState() async throws {
        try await localTranslations.insertTranslation(sahih, installedVersion: sahih.version, downloaded: true)
        try await localTranslations.insertTranslation(muyassar, installedVersion: nil, downloaded: false)
        let sut = makeSUT(startingAt: verse(2, 1))

        await sut.reloadTafsirs()

        XCTAssertEqual(sut.tafsirs, [])
        XCTAssertEqual(sut.content, .noTafsirs)
    }

    func testFirstAyahOfTheQuranHasNoPreviousAyah() async throws {
        try await installTranslations()
        let sut = makeSUT(startingAt: Quran.hafsMadani1405.firstVerse)

        XCTAssertNil(sut.previousVerse)
    }

    // MARK: Private

    private var localTranslations: LocalTranslationsFake!
    private var databases: [Translation.ID: URL] = [:]

    private let sahih = translation(id: 98, fileName: "quran.ensi.db", languageCode: "en")
    private let muyassar = translation(id: 64, fileName: "quran.ar.muyassar.db", languageCode: "ar")
    private let ibnKathir = translation(id: 58, fileName: "quran.ar.ibnkathir.db", languageCode: "ar")
    private let jalalayn = translation(id: 92, fileName: "quran.ar.jalalayn.db", languageCode: "ar")

    private static func makeTafsirDatabase(rows: [(Int, Int, any DatabaseValueConvertible)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tafsir-\(UUID().uuidString)")
            .appendingPathExtension("db")
        let database = try DatabaseQueue(path: url.path)
        try database.write { db in
            try db.execute(sql: "CREATE VIRTUAL TABLE verses USING fts3(sura INTEGER, ayah INTEGER, text TEXT)")
            for (sura, ayah, text) in rows {
                try db.execute(
                    sql: "INSERT INTO verses(sura, ayah, text) VALUES (?, ?, ?)",
                    arguments: [sura, ayah, text.databaseValue]
                )
            }
        }
        return url
    }

    private func installTranslations() async throws {
        for downloaded in [sahih, muyassar, ibnKathir] {
            try await localTranslations.insertTranslation(downloaded, installedVersion: downloaded.version, downloaded: true)
        }
        try await localTranslations.insertTranslation(jalalayn, installedVersion: nil, downloaded: false)
    }

    private func makeSUT(
        startingAt verse: AyahNumber,
        onVerseChange: @escaping (AyahNumber) -> Void = { _ in }
    ) -> TafsirViewModel {
        let databases = databases
        let dataService = QuranTextDataService(
            localTranslationRetriever: localTranslations.retriever,
            arabicPersistence: GRDBQuranVerseTextPersistence(mode: .arabic, fileURL: QuranResources.quranUthmaniV2Database),
            translationsPersistenceBuilder: { translation in
                GRDBTranslationVerseTextPersistence(fileURL: databases[translation.id]!)
            }
        )
        return TafsirViewModel(
            startingVerse: verse,
            localTranslationsRetriever: localTranslations.retriever,
            dataService: dataService,
            onVerseChange: onVerseChange
        )
    }

    private func passage(of sut: TafsirViewModel) -> TafsirPassage? {
        if case .loaded(let passage) = sut.content {
            return passage
        }
        return nil
    }

    private func verse(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: sura, ayah: ayah)!
    }
}

private func translation(id: Int, fileName: String, languageCode: String) -> Translation {
    Translation(
        id: id,
        displayName: fileName,
        translator: nil,
        translatorForeign: nil,
        fileURL: URL(validURL: "https://example.invalid/\(id)"),
        fileName: fileName,
        languageCode: languageCode,
        version: 3,
        installedVersion: nil
    )
}
