//
//  ReciterDataRetrieverTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import Foundation
import QuranAudio
import SystemDependenciesFake
import XCTest
@testable import ReciterService

final class ReciterDataRetrieverTests: XCTestCase {
    func test_readsABundledTimingDatabase() async throws {
        let bundle = SystemBundleFake()
        let database = URL(fileURLWithPath: "/bundle/qul_afasy.db")
        bundle.urls["qul_afasy.db"] = database
        bundle.arrays["reciters.plist"] = [
            reciter(id: 1001, name: "qul", timingDatabase: "qul_afasy"),
            reciter(id: 1, name: "husary", timingDatabase: nil),
        ] as NSArray

        let reciters = await ReciterDataRetriever(bundle: bundle).getReciters()

        let qul = try XCTUnwrap(reciters.first { $0.id == 1001 })
        XCTAssertEqual(qul.bundledTimingDatabase, database)
        XCTAssertEqual(qul.timingDatabaseURL, database)
        XCTAssertNil(qul.localDatabasePath, "A bundled database is never downloaded")
        XCTAssertNil(qul.databaseRemoteURL(baseURL: URL(fileURLWithPath: "/")))

        let husary = try XCTUnwrap(reciters.first { $0.id == 1 })
        XCTAssertNil(husary.bundledTimingDatabase)
        XCTAssertNotNil(husary.localDatabasePath)
    }

    func test_aMissingBundledDatabaseLeavesTheReciterDownloadingItsOwn() async throws {
        let bundle = SystemBundleFake()
        bundle.arrays["reciters.plist"] = [reciter(id: 1001, name: "qul", timingDatabase: "missing")] as NSArray

        let reciters = await ReciterDataRetriever(bundle: bundle).getReciters()

        XCTAssertNil(try XCTUnwrap(reciters.first).bundledTimingDatabase)
    }

    private func reciter(id: Int, name: String, timingDatabase: String?) -> NSDictionary {
        var dictionary: [String: Any] = [
            "id": id,
            "name": name,
            "path": name,
            "url": "https://example.com/\(name)/",
            "databaseName": name,
            "hasGaplessAlternative": false,
            "category": "arabic",
        ]
        dictionary["timingDatabase"] = timingDatabase
        return dictionary as NSDictionary
    }
}
