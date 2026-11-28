//
//  PhoneticReference.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import QuranKit
import SQLite3

/// One expected tajweed or gemination unit inside a `PhoneticReference`, indexed in Unicode
/// character positions of `PhoneticReference.phonemes`. Used in V4 to separate clear pronunciation
/// mistakes (lahn jali) from fine tajweed rules, and in V5 for rule-level tajweed assessment.
public struct PhoneticTajweedUnit: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case madd
        case qalqalah
        case ghunnah
        case ikhfa
        case iqlab
        case idgham
        case idghamGhunnah = "idgham_ghunnah"
        case shadda
    }

    public let kind: Kind
    public let rule: String
    /// 0-based index into `PhoneticReference.words`.
    public let wordIndex: Int
    /// Character range `[lowerBound, upperBound)` inside `PhoneticReference.phonemes`.
    public let phonemeRange: Range<Int>
    /// Expected repeat count (e.g., 2/4/6 for madd, 4 for ghunnah, 2 for shadda).
    public let goldenCount: Int
    /// Target QPS scalar (`ا`, `ۥ`, `ۦ`, `ڇ`, `ں`, `۾`, `ن`, `م`, etc.).
    public let symbol: Unicode.Scalar

    public init(kind: Kind, rule: String, wordIndex: Int, phonemeRange: Range<Int>, goldenCount: Int, symbol: Unicode.Scalar) {
        self.kind = kind
        self.rule = rule
        self.wordIndex = wordIndex
        self.phonemeRange = phonemeRange
        self.goldenCount = goldenCount
        self.symbol = symbol
    }
}

/// One word's display text and character range inside `PhoneticReference.phonemes`.
public struct WordPhoneticSpan: Equatable, Sendable {
    /// 0-based word index in the passage.
    public let wordIndex: Int
    /// 1-based canonical word number within its ayah (or sequential for non-Quran Arabican drills).
    public let wordNumber: Int
    /// Uthmani display text for this word.
    public let displayText: String
    /// Character range `[lowerBound, upperBound)` inside `PhoneticReference.phonemes`.
    public let phonemeRange: Range<Int>

    public init(wordIndex: Int, wordNumber: Int, displayText: String, phonemeRange: Range<Int>) {
        self.wordIndex = wordIndex
        self.wordNumber = wordNumber
        self.displayText = displayText
        self.phonemeRange = phonemeRange
    }
}

/// Expected Quran Phonetic Script (QPS) reference for one ayah, a passage, or a custom Arabic word
/// sequence (enabling reuse in Arabican without depending on QuranEngine's full ayah database).
public struct PhoneticReference: Equatable, Sendable {
    public let phonemes: String
    public let words: [WordPhoneticSpan]
    public let units: [PhoneticTajweedUnit]

    public init(phonemes: String, words: [WordPhoneticSpan], units: [PhoneticTajweedUnit] = []) {
        self.phonemes = phonemes
        self.words = words
        self.units = units
    }

    /// Concatenates per-ayah references into one passage reference, shifting spans and word indices.
    public static func concatenate(_ references: [PhoneticReference]) -> PhoneticReference {
        var combinedPhonemes = ""
        var combinedWords: [WordPhoneticSpan] = []
        var combinedUnits: [PhoneticTajweedUnit] = []
        var charOffset = 0
        var wordOffset = 0

        for reference in references {
            combinedPhonemes += reference.phonemes
            let count = reference.phonemes.unicodeScalars.count
            for word in reference.words {
                combinedWords.append(WordPhoneticSpan(
                    wordIndex: word.wordIndex + wordOffset,
                    wordNumber: word.wordNumber,
                    displayText: word.displayText,
                    phonemeRange: (word.phonemeRange.lowerBound + charOffset) ..< (word.phonemeRange.upperBound + charOffset)
                ))
            }
            for unit in reference.units {
                combinedUnits.append(PhoneticTajweedUnit(
                    kind: unit.kind,
                    rule: unit.rule,
                    wordIndex: unit.wordIndex + wordOffset,
                    phonemeRange: (unit.phonemeRange.lowerBound + charOffset) ..< (unit.phonemeRange.upperBound + charOffset),
                    goldenCount: unit.goldenCount,
                    symbol: unit.symbol
                ))
            }
            charOffset += count
            wordOffset += reference.words.count
        }
        return PhoneticReference(phonemes: combinedPhonemes, words: combinedWords, units: combinedUnits)
    }
}

/// Read-only reader for the precompiled `quran_phonetics.db` SQLite reference built by
/// `Tools/phonetic-model.py build-ref` (using `obadx/quran-transcript`). Opens on demand per query
/// so it holds no open file handles or full-corpus memory at launch.
public struct PhoneticReferenceStore: Sendable {
    // MARK: Lifecycle

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    // MARK: Public

    public let databaseURL: URL

    public func reference(for verse: AyahNumber) throws -> PhoneticReference? {
        try reference(sura: verse.sura.suraNumber, ayah: verse.ayah)
    }

    public func reference(for verses: [AyahNumber]) throws -> PhoneticReference? {
        guard !verses.isEmpty else { return nil }
        var loaded: [PhoneticReference] = []
        for verse in verses {
            guard let item = try reference(for: verse) else {
                return nil
            }
            loaded.append(item)
        }
        return PhoneticReference.concatenate(loaded)
    }

    public func reference(sura: Int, ayah: Int) throws -> PhoneticReference? {
        var db: OpaquePointer?
        let status = sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw PhoneticReferenceError.cannotOpenDatabase(databaseURL.path)
        }
        defer { sqlite3_close(db) }

        guard let phonemes = try queryPhonemes(db: db, sura: sura, ayah: ayah) else {
            return nil
        }
        let scalarCount = phonemes.unicodeScalars.count
        let words = try queryWords(db: db, sura: sura, ayah: ayah, phonemeCount: scalarCount)
        let units = try queryUnits(db: db, sura: sura, ayah: ayah, phonemeCount: scalarCount)
        return PhoneticReference(phonemes: phonemes, words: words, units: units)
    }

    // MARK: Private

    private func queryPhonemes(db: OpaquePointer, sura: Int, ayah: Int) throws -> String? {
        let sql = "SELECT phonemes FROM ayah_phonetics WHERE sura = ? AND ayah = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw PhoneticReferenceError.queryFailed
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(sura))
        sqlite3_bind_int(stmt, 2, Int32(ayah))
        guard sqlite3_step(stmt) == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: cString)
    }

    private func queryWords(db: OpaquePointer, sura: Int, ayah: Int, phonemeCount: Int) throws -> [WordPhoneticSpan] {
        let sql = """
        SELECT word_index, word_number, text, start_idx, end_idx
        FROM word_spans
        WHERE sura = ? AND ayah = ?
        ORDER BY word_index ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw PhoneticReferenceError.queryFailed
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(sura))
        sqlite3_bind_int(stmt, 2, Int32(ayah))

        var result: [WordPhoneticSpan] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let wordIndex = Int(sqlite3_column_int(stmt, 0))
            let wordNumber = Int(sqlite3_column_int(stmt, 1))
            let text = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let start = max(0, min(phonemeCount, Int(sqlite3_column_int(stmt, 3))))
            let end = max(start, min(phonemeCount, Int(sqlite3_column_int(stmt, 4))))
            result.append(WordPhoneticSpan(
                wordIndex: wordIndex,
                wordNumber: wordNumber,
                displayText: text,
                phonemeRange: start ..< end
            ))
        }
        return result
    }

    private func queryUnits(db: OpaquePointer, sura: Int, ayah: Int, phonemeCount: Int) throws -> [PhoneticTajweedUnit] {
        let sql = """
        SELECT word_index, kind, rule, start_idx, end_idx, golden, char
        FROM tajweed_units
        WHERE sura = ? AND ayah = ?
        ORDER BY unit_index ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw PhoneticReferenceError.queryFailed
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(sura))
        sqlite3_bind_int(stmt, 2, Int32(ayah))

        var result: [PhoneticTajweedUnit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let wordIndex = Int(sqlite3_column_int(stmt, 0))
            let kindRaw = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let rule = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let start = max(0, min(phonemeCount, Int(sqlite3_column_int(stmt, 3))))
            let end = max(start, min(phonemeCount, Int(sqlite3_column_int(stmt, 4))))
            let golden = Int(sqlite3_column_int(stmt, 5))
            let charStr = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            guard let kind = PhoneticTajweedUnit.Kind(rawValue: kindRaw), let symbol = charStr.unicodeScalars.first else {
                continue
            }
            result.append(PhoneticTajweedUnit(
                kind: kind,
                rule: rule,
                wordIndex: wordIndex,
                phonemeRange: start ..< end,
                goldenCount: golden,
                symbol: symbol
            ))
        }
        return result
    }
}

public enum PhoneticReferenceError: Error, Equatable {
    case cannotOpenDatabase(String)
    case queryFailed
}
