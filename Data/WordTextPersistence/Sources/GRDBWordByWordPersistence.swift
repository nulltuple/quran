//
//  GRDBWordByWordPersistence.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import Foundation
import GRDB
import QuranKit
import SQLitePersistence

/// A language with word-by-word meanings in the database.
public enum WordMeaningLanguage: String, Sendable {
    case english
    case bengali
}

/// Reads `word_by_word.db`, which `Tools/build-qul-word-data.py` builds from Quranic Universal
/// Library data. Words are numbered as in the ayah's text, not counting the ayah-number marker.
public struct GRDBWordByWordPersistence: Sendable {
    // MARK: Lifecycle

    init(db: DatabaseConnection) {
        self.db = db
    }

    public init(fileURL: URL) {
        self.init(db: DatabaseConnection(url: fileURL))
    }

    // MARK: Public

    /// The meaning of each word in `verses` that has one in `language`.
    public func meanings(for verses: [AyahNumber], language: WordMeaningLanguage) async throws -> [Word: String] {
        try await values(String.self, table: "word_meanings", column: language.rawValue, verses: verses)
    }

    /// The glyph position, in the Madani 1405 page images, of each word in `verses` whose glyphs
    /// were matched; an unmatched ayah has none.
    public func hafs1405GlyphPositions(for verses: [AyahNumber]) async throws -> [Word: Int] {
        try await values(Int.self, table: "hafs_1405_glyph_words", column: "glyph_position", verses: verses)
    }

    /// The number of words in each of `verses`, not counting the ayah-number marker.
    public func wordCounts(for verses: [AyahNumber]) async throws -> [AyahNumber: Int] {
        let words = try await values(Int.self, table: "word_meanings", column: "word", verses: verses)
        var counts: [AyahNumber: Int] = [:]
        for word in words.keys {
            counts[word.verse] = max(counts[word.verse] ?? 0, word.wordNumber)
        }
        return counts
    }

    // MARK: Internal

    let db: DatabaseConnection

    // MARK: Private

    private func values<Value: DatabaseValueConvertible & Sendable>(
        _ type: Value.Type,
        table: String,
        column: String,
        verses: [AyahNumber]
    ) async throws -> [Word: Value] {
        guard let first = verses.min(), let last = verses.max() else {
            return [:]
        }
        let wanted = Set(verses)
        return try await db.read { db in
            // Verses on a page are contiguous; read the range and keep the requested ones.
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT sura, ayah, word, \(column) AS value FROM \(table)
                WHERE (sura > ? OR (sura = ? AND ayah >= ?)) AND (sura < ? OR (sura = ? AND ayah <= ?))
                """,
                arguments: [
                    first.sura.suraNumber, first.sura.suraNumber, first.ayah,
                    last.sura.suraNumber, last.sura.suraNumber, last.ayah,
                ]
            )
            var result: [Word: Value] = [:]
            for row in rows {
                guard let value = Value.fromDatabaseValue(row["value"]),
                      let verse = AyahNumber(quran: first.quran, sura: row["sura"], ayah: row["ayah"]),
                      wanted.contains(verse)
                else {
                    continue
                }
                result[Word(verse: verse, wordNumber: row["word"])] = value
            }
            return result
        }
    }
}
