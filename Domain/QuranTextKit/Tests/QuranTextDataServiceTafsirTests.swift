//
//  QuranTextDataServiceTafsirTests.swift
//

import GRDB
import QuranKit
import QuranText
import TranslationServiceFake
import Utilities
import VerseTextPersistence
import XCTest
@testable import QuranTextKit

final class QuranTextDataServiceTafsirTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        // Shaped like Quran.app's Muyassar file: 2:45 refers to 2:46 (verse index 53), which holds
        // the passage's text; 4:66 and 4:67 refer to 4:68 (index 561).
        databaseURL = try Self.makeTafsirDatabase(rows: [
            (2, 44, "Ayah 44 alone."),
            (2, 45, 53),
            (2, 46, "Ayahs 45 and 46 together."),
            (2, 47, "  \n"),
            (4, 66, 561),
            (4, 67, "561"),
            (4, 68, "Ayahs 66 to 68 together [[a note]]."),
        ])
        localTranslationsFake = LocalTranslationsFake()
        let url = databaseURL!
        service = QuranTextDataService(
            localTranslationRetriever: localTranslationsFake.retriever,
            arabicPersistence: GRDBQuranVerseTextPersistence(mode: .arabic, fileURL: TestData.quranTextURL),
            translationsPersistenceBuilder: { _ in GRDBTranslationVerseTextPersistence(fileURL: url) }
        )
    }

    override func tearDown() async throws {
        localTranslationsFake.tearDown()
        try? FileManager.default.removeItem(at: databaseURL)
        service = nil
        try await super.tearDown()
    }

    func testAyahWithItsOwnTextCoversOnlyItself() async throws {
        let tafsir = try await service.tafsir(for: verse(2, 44), translation: muyassar)

        XCTAssertEqual(tafsir.verses, [verse(2, 44)])
        XCTAssertEqual(tafsir.text?.text, "Ayah 44 alone.")
        XCTAssertFalse(tafsir.coversSeveralVerses)
    }

    func testReferringAyahShowsThePassageTextAndRange() async throws {
        let tafsir = try await service.tafsir(for: verse(2, 45), translation: muyassar)

        XCTAssertEqual(tafsir.verses, [verse(2, 45), verse(2, 46)])
        XCTAssertEqual(tafsir.text?.text, "Ayahs 45 and 46 together.")
        XCTAssertTrue(tafsir.coversSeveralVerses)
    }

    func testAyahHoldingThePassageTextFindsIntegerAndStringReferences() async throws {
        let tafsir = try await service.tafsir(for: verse(4, 68), translation: muyassar)
        let fromMiddle = try await service.tafsir(for: verse(4, 67), translation: muyassar)

        XCTAssertEqual(tafsir.verses, [verse(4, 66), verse(4, 67), verse(4, 68)])
        XCTAssertEqual(fromMiddle.verses, tafsir.verses)
        XCTAssertEqual(tafsir.firstVerse, verse(4, 66))
        XCTAssertEqual(tafsir.lastVerse, verse(4, 68))
        // Footnotes are parsed as in the translation view.
        XCTAssertEqual(tafsir.text?.footnotes, ["[[a note]]"])
    }

    func testBlankTextIsNoText() async throws {
        let tafsir = try await service.tafsir(for: verse(2, 47), translation: muyassar)

        XCTAssertEqual(tafsir.verses, [verse(2, 47)])
        XCTAssertNil(tafsir.text)
    }

    func testFeedTafsirIDsAreTafsirsAndTranslationsAreNot() {
        XCTAssertTrue(muyassar.isTafsir)
        XCTAssertTrue(Translation.tafsirIDs.isSuperset(of: [58, 64, 113]))
        XCTAssertFalse(TestData.sahihTranslation.isTafsir)
        XCTAssertFalse(TestData.khanTranslation.isTafsir)
    }

    // MARK: Private

    private var databaseURL: URL!
    private var localTranslationsFake: LocalTranslationsFake!
    private var service: QuranTextDataService!

    private let quran = Quran.hafsMadani1405

    private let muyassar = Translation(
        id: 64,
        displayName: "Arabic Muyassar Tafseer",
        translator: nil,
        translatorForeign: "الميسر",
        fileURL: URL(validURL: "https://android.quran.com/data/getTranslation.php?id=64&ext=zip"),
        fileName: "quran.ar.muyassar.db",
        languageCode: "ar",
        version: 10,
        installedVersion: 10
    )

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

    private func verse(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }
}
