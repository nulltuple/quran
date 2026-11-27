//
//  TranslationsRepositoryTests.swift
//
//
//  Created by Mohamed Afifi on 2023-05-21.
//

import NetworkSupportFake
import QuranText
import TranslationServiceFake
import XCTest
@testable import NetworkSupport
@testable import TranslationService

class TranslationsRepositoryTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        session = NetworkSessionFake(queue: .main, delegate: nil)
        localTranslationsFake = LocalTranslationsFake(useFactory: true)
        service = TranslationsRepository(
            databasesURL: localTranslationsFake.databasesURL,
            networkManager: NetworkManager(session: session, baseURL: baseURL)
        )
    }

    override func tearDown() {
        super.tearDown()
        localTranslationsFake.tearDown()
        service = nil
        localTranslationsFake = nil
    }

    func test_firstTimeDownload() async throws {
        try session.respondWithTranslations(translations, baseURL: baseURL)

        try await service.downloadAndSyncTranslations()

        let localResults = try await retriever.getLocalTranslations()
        let expectedTranslations = translations.map {
            expectedTranslation($0, installedVersion: nil)
        }
        XCTAssertEqual(localResults, expectedTranslations)
    }

    func test_updatedVersion() async throws {
        let translation = translations[0]
        let updatedTranslation = Translation(
            id: translation.id + 45,
            displayName: translation.displayName,
            translator: translation.translator,
            translatorForeign: translation.translatorForeign,
            fileURL: translation.fileURL,
            fileName: translation.fileName,
            languageCode: translation.languageCode,
            version: 1000
        )

        try session.respondWithTranslations([translation], baseURL: baseURL)
        try await service.downloadAndSyncTranslations()

        try session.respondWithTranslations([updatedTranslation], baseURL: baseURL)
        try await service.downloadAndSyncTranslations()

        let localResults = try await retriever.getLocalTranslations()
        XCTAssertEqual(localResults, [updatedTranslation])
    }

    func test_updatedFileName() async throws {
        let translation = translations[0]
        let updatedTranslation = Translation(
            id: translation.id + 19,
            displayName: translation.displayName,
            translator: translation.translator,
            translatorForeign: translation.translatorForeign,
            fileURL: translation.fileURL,
            fileName: "updatedFileName.db",
            languageCode: translation.languageCode,
            version: translation.version
        )

        try session.respondWithTranslations([translation], baseURL: baseURL)
        try await service.downloadAndSyncTranslations()

        try session.respondWithTranslations([updatedTranslation], baseURL: baseURL)
        try await service.downloadAndSyncTranslations()

        let localResults = try await retriever.getLocalTranslations()

        // Expected to create a duplicate entry if fileName changed,
        // fileName should not change to upgrade, it's a unique value
        // per translation
        XCTAssertEqual(localResults.sorted(), [
            expectedTranslation(translation, installedVersion: nil),
            expectedTranslation(updatedTranslation, installedVersion: nil),
        ].sorted())
    }

    func test_supplementaryTafsirsAreListedAfterTheFeed() async throws {
        let service = TranslationsRepository(
            databasesURL: localTranslationsFake.databasesURL,
            networkManager: NetworkManager(session: session, baseURL: baseURL),
            supplementaryTranslations: Translation.supplementaryTafsirs
        )
        try session.respondWithTranslations(translations, baseURL: baseURL)

        try await service.downloadAndSyncTranslations()
        try await service.downloadAndSyncTranslations()

        let localResults = try await retriever.getLocalTranslations()
        XCTAssertEqual(localResults.sorted(), (translations + Translation.supplementaryTafsirs).map { expectedTranslation($0, installedVersion: nil) }.sorted())
    }

    func test_aFeedEntryWithTheSameFileNameWinsOverASupplementaryOne() async throws {
        let supplementary = Translation.supplementaryTafsirs[0]
        let feedEntry = Translation(
            id: 170,
            displayName: "Feed Ibn Kathir",
            translator: nil,
            translatorForeign: nil,
            fileURL: URL(validURL: "https://example.com/170.zip"),
            fileName: supplementary.fileName,
            languageCode: "en",
            version: 4
        )
        let service = TranslationsRepository(
            databasesURL: localTranslationsFake.databasesURL,
            networkManager: NetworkManager(session: session, baseURL: baseURL),
            supplementaryTranslations: [supplementary]
        )
        try session.respondWithTranslations([feedEntry], baseURL: baseURL)

        try await service.downloadAndSyncTranslations()

        let localResults = try await retriever.getLocalTranslations()
        XCTAssertEqual(localResults, [feedEntry])
    }

    func test_supplementaryTafsirsAreTafsirZipsWithUniqueIDsAndFiles() {
        let tafsirs = Translation.supplementaryTafsirs
        XCTAssertEqual(tafsirs.map(\.languageCode), ["en", "bn"])
        XCTAssertTrue(tafsirs.allSatisfy(\.isTafsir))
        XCTAssertTrue(tafsirs.allSatisfy { $0.fileURL.pathExtension == "zip" && $0.isUnprocessedFileZip })
        XCTAssertTrue(tafsirs.allSatisfy { $0.id > Translation.supplementaryTafsirIDBase })
        XCTAssertEqual(Set(tafsirs.map(\.fileName)).count, tafsirs.count)
        // The pack zip is named after the database it holds (`Tools/build-tafsir-pack.py zip`).
        XCTAssertEqual(tafsirs.map(\.fileURL.lastPathComponent), ["quran.en.ibnkathir.zip", "quran.bn.ahsanulbayaan.zip"])
        XCTAssertEqual(tafsirs.map(\.fileName), ["quran.en.ibnkathir.db", "quran.bn.ahsanulbayaan.db"])
    }

    // MARK: Private

    private var session: NetworkSessionFake!
    private var service: TranslationsRepository!
    private var localTranslationsFake: LocalTranslationsFake!

    private let baseURL = URL(validURL: "http://example.com")

    private let translations = [
        TranslationTestData.khanTranslation,
        TranslationTestData.sahihTranslation,
    ]

    private var retriever: LocalTranslationsRetriever {
        localTranslationsFake.retriever
    }

    // MARK: - Helpers

    private func expectedTranslation(_ translation: Translation, installedVersion: Int?) -> Translation {
        var translation = translation
        translation.installedVersion = installedVersion
        return translation
    }
}
