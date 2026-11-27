//
//  GRDBWordMorphologyPersistence.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Foundation
import GRDB
import QuranKit
import QuranText
import SQLitePersistence

/// Reads `quran_morphology.db`, which `Tools/build-quran-morphology.py` builds from the Quranic
/// Arabic Corpus on canonical word numbers (the numbers `word_by_word.db` uses).
public struct GRDBWordMorphologyPersistence: Sendable {
    // MARK: Lifecycle

    init(db: DatabaseConnection) {
        self.db = db
    }

    public init(fileURL: URL) {
        self.init(db: DatabaseConnection(url: fileURL))
    }

    // MARK: Public

    /// The segments of `word` in reading order; empty when the database has no such word.
    public func segments(of word: Word) async throws -> [MorphologySegment] {
        try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT s.text, g.part, g.tag, g.derivation, g.role, g.person, g.gender, g.number, g.verb_form,
                    g.aspect, g.voice, g.mood, g.grammatical_case, g.indefinite, g.family,
                    l.id AS lemma_id, l.lemma, l.occurrences AS lemma_occurrences,
                    r.id AS root_id, r.root, r.occurrences AS root_occurrences
                FROM segments s
                JOIN grammar g ON g.id = s.grammar_id
                LEFT JOIN lemmas l ON l.id = s.lemma_id
                LEFT JOIN roots r ON r.id = s.root_id
                WHERE s.sura = ? AND s.ayah = ? AND s.word = ?
                ORDER BY s.segment
                """,
                arguments: [word.verse.sura.suraNumber, word.verse.ayah, word.wordNumber]
            )
            return try rows.map(Self.segment)
        }
    }

    /// Up to `limit` words with `term`, in Quran order, after `after` (from the start when `nil`),
    /// each with its Arabic text (its segments joined).
    public func occurrences(of term: WordStudyTerm, quran: Quran, after: Word?, limit: Int) async throws -> [(Word, String)] {
        let (column, id) = switch term {
        case .lemma(let lemma): ("lemma_id", lemma.id)
        case .root(let root): ("root_id", root.id)
        }
        let start = after.map { [$0.verse.sura.suraNumber, $0.verse.ayah, $0.wordNumber] } ?? [0, 0, 0]
        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT s.sura, s.ayah, s.word, s.text FROM segments s
                JOIN (
                    SELECT DISTINCT sura, ayah, word FROM segments
                    WHERE \(column) = ? AND (sura, ayah, word) > (?, ?, ?)
                    ORDER BY sura, ayah, word LIMIT ?
                ) o ON s.sura = o.sura AND s.ayah = o.ayah AND s.word = o.word
                ORDER BY s.sura, s.ayah, s.word, s.segment
                """,
                arguments: StatementArguments([id] + start + [limit])
            )
            var result: [(Word, String)] = []
            for row in rows {
                guard let verse = AyahNumber(quran: quran, sura: row["sura"], ayah: row["ayah"]) else {
                    continue
                }
                let word = Word(verse: verse, wordNumber: row["word"])
                let text: String = row["text"]
                if result.last?.0 == word {
                    result[result.count - 1].1 += text
                } else {
                    result.append((word, text))
                }
            }
            return result
        }
    }

    // MARK: Internal

    let db: DatabaseConnection

    // MARK: Private

    private struct UnknownValue: Error {
        let column: String
        let value: String
    }

    private static func segment(_ row: Row) throws -> MorphologySegment {
        func decoded<T: RawRepresentable>(_ column: String) throws -> T? where T.RawValue == String {
            guard let raw: String = row[column] else {
                return nil
            }
            guard let value = T(rawValue: raw) else {
                throw UnknownValue(column: column, value: raw)
            }
            return value
        }
        guard let part: WordGrammar.Part = try decoded("part"), let role: WordGrammar.Role = try decoded("role") else {
            throw UnknownValue(column: "part or role", value: "NULL")
        }
        let grammar = WordGrammar(
            part: part,
            tag: row["tag"],
            derivation: row["derivation"],
            role: role,
            person: row["person"],
            gender: try decoded("gender"),
            number: try decoded("number"),
            verbForm: row["verb_form"],
            aspect: try decoded("aspect"),
            voice: try decoded("voice"),
            mood: try decoded("mood"),
            grammaticalCase: try decoded("grammatical_case"),
            isIndefinite: row["indefinite"] == 1,
            family: try decoded("family")
        )
        let lemma: WordLemma? = (row["lemma_id"] as Int?).map {
            WordLemma(id: $0, text: row["lemma"], occurrences: row["lemma_occurrences"])
        }
        let root: WordRoot? = (row["root_id"] as Int?).map {
            WordRoot(id: $0, letters: row["root"], occurrences: row["root_occurrences"])
        }
        return MorphologySegment(text: row["text"], grammar: grammar, lemma: lemma, root: root)
    }
}
