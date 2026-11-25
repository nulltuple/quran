//
//  GRDBAyahTimingPersistence.swift
//
//
//  Created by Mohamed Afifi on 2023-05-22.
//

import Foundation
import GRDB
import QuranAudio
import QuranKit
import SQLitePersistence

public struct GRDBAyahTimingPersistence: AyahTimingPersistence {
    // MARK: Lifecycle

    init(db: DatabaseConnection) {
        self.db = db
    }

    public init(fileURL: URL) {
        self.init(db: DatabaseConnection(url: fileURL))
    }

    // MARK: Public

    public func getVersion() async throws -> Int {
        try await db.read { db in
            let property = try GRDBProperty
                .filter(GRDBProperty.Columns.property == "version")
                .fetchOne(db)
            let version = property.flatMap { Int($0.value) }
            return version ?? 1
        }
    }

    public func getOrderedTimingForSura(startAyah: QuranKit.AyahNumber) async throws -> SuraTiming {
        try await db.read { db in
            let query = GRDBTiming.filter(GRDBTiming.Columns.sura == startAyah.sura.suraNumber
                && GRDBTiming.Columns.ayah >= startAyah.ayah)
                .order(GRDBTiming.Columns.ayah)
            var timings: [AyahTiming] = []
            var endTime: Timing?
            let rows = try query.fetchAll(db)
            for row in rows {
                let ayah = row.ayah
                let time = Timing(time: row.time)
                if ayah == 999 {
                    endTime = time
                } else {
                    let verse = AyahNumber(quran: startAyah.quran, sura: row.sura, ayah: ayah)!
                    let timing = AyahTiming(ayah: verse, time: time)
                    timings.append(timing)
                }
            }
            return SuraTiming(verses: timings, endTime: endTime)
        }
    }

    public func getWordTimings(for sura: Sura) async throws -> [AyahNumber: AyahWordTimings] {
        try await db.read { db in
            // Only reciters with word-level data, such as QUL recitations, have this table.
            guard try db.tableExists(GRDBWordTiming.databaseTableName) else {
                return [:]
            }
            let rows = try GRDBWordTiming
                .filter(GRDBWordTiming.Columns.sura == sura.suraNumber)
                .order(GRDBWordTiming.Columns.ayah, GRDBWordTiming.Columns.seq)
                .fetchAll(db)
            var words: [AyahNumber: [WordTiming]] = [:]
            for row in rows {
                guard let ayah = AyahNumber(quran: sura.quran, sura: row.sura, ayah: row.ayah) else {
                    continue
                }
                words[ayah, default: []].append(WordTiming(
                    word: row.word,
                    start: Timing(time: row.start).seconds,
                    end: Timing(time: row.end).seconds
                ))
            }
            return words.mapValues(AyahWordTimings.init)
        }
    }

    // MARK: Internal

    let db: DatabaseConnection
}

private struct GRDBTiming: Decodable, FetchableRecord, TableRecord {
    enum Columns {
        static let sura = Column(CodingKeys.sura)
        static let ayah = Column(CodingKeys.ayah)
        static let time = Column(CodingKeys.time)
    }

    static var databaseTableName: String {
        "timings"
    }

    var sura: Int
    var ayah: Int
    var time: Int
}

private struct GRDBWordTiming: Decodable, FetchableRecord, TableRecord {
    enum Columns {
        static let sura = Column(CodingKeys.sura)
        static let ayah = Column(CodingKeys.ayah)
        static let seq = Column(CodingKeys.seq)
    }

    static var databaseTableName: String {
        "word_timings"
    }

    var sura: Int
    var ayah: Int
    var seq: Int
    var word: Int
    var start: Int
    var end: Int
}

private struct GRDBProperty: Decodable, FetchableRecord, TableRecord {
    enum Columns {
        static let property = Column(CodingKeys.property)
        static let value = Column(CodingKeys.value)
    }

    static var databaseTableName: String {
        "properties"
    }

    var property: String
    var value: String
}
