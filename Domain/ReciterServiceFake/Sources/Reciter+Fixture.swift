//
//  Reciter+Fixture.swift
//
//
//  Created by Mohammad Abdurraafay on 2023-02-11.
//

import Foundation
import TestResources
@testable import QuranAudio

extension Reciter {
    private static let baseURL = URL(validURL: "http://example.com")
    private static let gaplessDatabaseName = "mishari_alafasy"

    public static var gappedReciter: Reciter {
        Reciter(
            id: 11,
            nameKey: "reciter1",
            directory: "reciter1",
            audioURL: baseURL.appendingPathComponent("reciter1"),
            audioType: .gapped,
            hasGaplessAlternative: false,
            category: .arabic
        )
    }

    public static var gaplessReciter: Reciter {
        Reciter(
            id: 22,
            nameKey: "qari_afasy_gapless",
            directory: "mishari_alafasy",
            audioURL: baseURL.appendingPathComponent("mishari_alafasy"),
            audioType: .gapless(databaseName: gaplessDatabaseName),
            hasGaplessAlternative: false,
            category: .arabic
        )
    }

    /// A gapless reciter with a bundled QUL timing database that has word timings for suras 1, 2
    /// and 112 to 114.
    public static var wordTimingReciter: Reciter {
        Reciter(
            id: 1001,
            nameKey: "qari_afasy_qul_word_by_word",
            directory: "qul_mishari_alafasy",
            audioURL: baseURL.appendingPathComponent("qul_mishari_alafasy"),
            audioType: .gapless(databaseName: "qul_afasy"),
            hasGaplessAlternative: false,
            category: .arabic,
            bundledTimingDatabase: TestResources.resourceURL("qul_afasy.db")
        )
    }

    public func toPlistDictionary() -> [String: Any] {
        let databaseName: String = switch audioType {
        case .gapless(let db): db
        case .gapped: ""
        }
        return [
            "id": id,
            "name": nameKey,
            "path": directory,
            "url": audioURL.absoluteString,
            "databaseName": databaseName,
            "hasGaplessAlternative": hasGaplessAlternative,
            "category": category.rawValue,
        ]
    }
}
