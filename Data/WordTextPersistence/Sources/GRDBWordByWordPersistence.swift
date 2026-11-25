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

/// A per-word text in the database.
public enum WordTextColumn: String, Sendable {
    case english
    case bengali
    case transliteration
}

/// Reads `word_by_word.db`, which `Tools/build-qul-word-data.py` builds from Quranic Universal
/// Library and Quran.com data. Words are numbered as QUL numbers them (canonical word numbers),
/// not counting the ayah-number marker; every word has a row.
public struct GRDBWordByWordPersistence: Sendable {
    // MARK: Lifecycle

    init(db: DatabaseConnection) {
        self.db = db
    }

    public init(fileURL: URL) {
        self.init(db: DatabaseConnection(url: fileURL))
    }

    // MARK: Public

    /// The `column` text of each word in `verses` that has one.
    public func texts(for verses: [AyahNumber], column: WordTextColumn) async throws -> [Word: String] {
        try await values(String.self, select: column.rawValue, from: "word_meanings", verses: verses)
    }

    /// The `column` text of one word, or `nil` when it has none.
    public func text(for word: Word, column: WordTextColumn) async throws -> String? {
        try await db.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT \(column.rawValue) FROM word_meanings WHERE sura = ? AND ayah = ? AND word = ?",
                arguments: [word.verse.sura.suraNumber, word.verse.ayah, word.wordNumber]
            )
        }
    }

    /// The glyph positions, in the Madani 1405 page images, of each word in `verses`. A word can
    /// span two glyphs (`إِلْ يَاسِينَ`), and two words can share one (`بَعْدَ مَا`).
    public func hafs1405GlyphPositions(for verses: [AyahNumber]) async throws -> [Word: ClosedRange<Int>] {
        guard let (first, last, wanted) = bounds(of: verses) else {
            return [:]
        }
        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT sura, ayah, word, MIN(glyph_position) AS first, MAX(glyph_position) AS last
                FROM hafs_1405_glyph_words WHERE \(Self.rangeCondition) GROUP BY sura, ayah, word
                """,
                arguments: Self.rangeArguments(first, last)
            )
            var result: [Word: ClosedRange<Int>] = [:]
            for row in rows {
                let firstGlyph: Int = row["first"]
                let lastGlyph: Int = row["last"]
                guard let verse = AyahNumber(quran: first.quran, sura: row["sura"], ayah: row["ayah"]),
                      wanted.contains(verse)
                else {
                    continue
                }
                result[Word(verse: verse, wordNumber: row["word"])] = firstGlyph ... lastGlyph
            }
            return result
        }
    }

    /// The word drawn by a glyph of the Madani 1405 page images, or `nil` for a mark (pause sign,
    /// ۞, ۩, ayah number) or an ayah without a mapping. A glyph two words share gives the first.
    public func hafs1405Word(atGlyph glyph: Word) async throws -> Word? {
        let number = try await db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT MIN(word) FROM hafs_1405_glyph_words WHERE sura = ? AND ayah = ? AND glyph_position = ?",
                arguments: [glyph.verse.sura.suraNumber, glyph.verse.ayah, glyph.wordNumber]
            )
        }
        return number.map { Word(verse: glyph.verse, wordNumber: $0) }
    }

    /// The number of words in each of `verses`, not counting the ayah-number marker.
    public func wordCounts(for verses: [AyahNumber]) async throws -> [AyahNumber: Int] {
        let words = try await values(Int.self, select: "word", from: "word_meanings", verses: verses)
        var counts: [AyahNumber: Int] = [:]
        for word in words.keys {
            counts[word.verse] = max(counts[word.verse] ?? 0, word.wordNumber)
        }
        return counts
    }

    /// For the ayahs in `verses` whose bundled Uthmani text splits words differently from the
    /// canonical words, the words each text token (in order, from 1) covers.
    public func uthmaniTokenWords(for verses: [AyahNumber]) async throws -> [AyahNumber: [ClosedRange<Int>]] {
        guard let (first, last, wanted) = bounds(of: verses) else {
            return [:]
        }
        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT sura, ayah, first_word, last_word FROM uthmani_tokens
                WHERE \(Self.rangeCondition) ORDER BY sura, ayah, token
                """,
                arguments: Self.rangeArguments(first, last)
            )
            var result: [AyahNumber: [ClosedRange<Int>]] = [:]
            for row in rows {
                let firstWord: Int = row["first_word"]
                let lastWord: Int = row["last_word"]
                guard let verse = AyahNumber(quran: first.quran, sura: row["sura"], ayah: row["ayah"]),
                      wanted.contains(verse), firstWord <= lastWord
                else {
                    continue
                }
                result[verse, default: []].append(firstWord ... lastWord)
            }
            return result
        }
    }

    // MARK: Internal

    let db: DatabaseConnection

    // MARK: Private

    // Verses on a page are contiguous; queries read the range and keep the requested ones.
    private static let rangeCondition = "(sura > ? OR (sura = ? AND ayah >= ?)) AND (sura < ? OR (sura = ? AND ayah <= ?))"

    private static func rangeArguments(_ first: AyahNumber, _ last: AyahNumber) -> StatementArguments {
        [
            first.sura.suraNumber, first.sura.suraNumber, first.ayah,
            last.sura.suraNumber, last.sura.suraNumber, last.ayah,
        ]
    }

    private func bounds(of verses: [AyahNumber]) -> (AyahNumber, AyahNumber, Set<AyahNumber>)? {
        guard let first = verses.min(), let last = verses.max() else {
            return nil
        }
        return (first, last, Set(verses))
    }

    private func values<Value: DatabaseValueConvertible & Sendable>(
        _ type: Value.Type,
        select expression: String,
        from table: String,
        verses: [AyahNumber]
    ) async throws -> [Word: Value] {
        guard let (first, last, wanted) = bounds(of: verses) else {
            return [:]
        }
        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT sura, ayah, word, \(expression) AS value FROM \(table)
                WHERE \(Self.rangeCondition)
                """,
                arguments: Self.rangeArguments(first, last)
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
