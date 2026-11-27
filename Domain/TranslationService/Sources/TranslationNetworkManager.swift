//
//  TranslationNetworkManager.swift
//
//
//  Created by Afifi, Mohamed on 10/30/21.
//

import NetworkSupport
import QuranText

struct TranslationNetworkManager {
    static let path = "/data/translations.php"

    let networkManager: NetworkManager
    let parser: TranslationsParser
    /// Entries the feed lacks, appended unless the feed has an entry with the same id or file name.
    var supplementaryTranslations: [Translation] = []

    func getTranslations() async throws -> [Translation] {
        let data = try await networkManager.request(Self.path, parameters: [("v", "5")])
        let feed = try parser.parse(data)
        let ids = Set(feed.map(\.id))
        let fileNames = Set(feed.map(\.fileName))
        return feed + supplementaryTranslations.filter { !ids.contains($0.id) && !fileNames.contains($0.fileName) }
    }
}
