//
//  LearningContentStore.swift
//  ArabicLearning (Arabican app)
//

import ArabicScript
import Foundation
import GRDB
import LearningModel
import QuranKit
import QuranText
import SQLitePersistence

/// Read-only access to `learning-content.sqlite`, which `Tools/learning/compile.py` builds.
/// Learner state never lives here; content upgrades replace this file wholesale.
public struct LearningContentStore: Sendable {
    // MARK: Lifecycle

    public init(fileURL: URL = LearningContentStore.bundledDatabaseURL, quran: Quran = .hafsMadani1405) {
        db = DatabaseConnection(url: fileURL, readonly: true)
        self.quran = quran
    }

    // MARK: Public

    public enum ContentError: Error, Equatable {
        case unsupportedSchema(String?)
        case malformedRow(String)
    }

    /// The schema version this code reads.
    public static let schemaVersion = "1"

    public static let bundledDatabaseURL = Bundle.module.url(forResource: "learning-content", withExtension: "sqlite")!

    public func letters() async throws -> [LetterInfo] {
        try await read { db in
            let forms = try Row.fetchAll(db, sql: "SELECT letter, form FROM letter_form")
            var formsByLetter: [String: Set<LetterForm>] = [:]
            for row in forms {
                guard let form = LetterForm(rawValue: row["form"]) else {
                    throw ContentError.malformedRow("letter_form \(row)")
                }
                formsByLetter[row["letter"], default: []].insert(form)
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM letter ORDER BY ordinal").map { row in
                let char: String = row["letter"]
                guard let letter = ArabicLetter(rawValue: char) else {
                    throw ContentError.malformedRow("letter \(char)")
                }
                let letterForms = formsByLetter[char] ?? []
                return LetterInfo(
                    letter: letter,
                    ordinal: row["ordinal"],
                    name: row["name"],
                    sound: row["sound"],
                    family: row["family"],
                    forms: LetterForm.allCases.filter(letterForms.contains)
                )
            }
        }
    }

    public func curriculum() async throws -> Curriculum {
        try await read { db in
            var teaches: [String: [SkillID]] = [:]
            var requires: [String: [SkillID]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT lesson, skill, role FROM lesson_skill ORDER BY rowid") {
                let skill = try Self.skill(row["skill"])
                let lesson: String = row["lesson"]
                if row["role"] as String == "teaches" {
                    teaches[lesson, default: []].append(skill)
                } else {
                    requires[lesson, default: []].append(skill)
                }
            }
            let lessons = try Row.fetchAll(db, sql: "SELECT * FROM lesson ORDER BY ordinal").map { row in
                let id: String = row["id"]
                return Lesson(
                    id: id,
                    unit: row["unit"],
                    ordinal: row["ordinal"],
                    title: row["title"],
                    teaches: teaches[id] ?? [],
                    requires: requires[id] ?? []
                )
            }
            var prerequisites: [SkillID: Set<SkillID>] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT skill, prereq FROM skill_prereq") {
                try prerequisites[Self.skill(row["skill"]), default: []].insert(Self.skill(row["prereq"]))
            }
            let units = try Row.fetchAll(db, sql: "SELECT id, title FROM unit ORDER BY ordinal").map { row in
                LearningUnit(id: row["id"], title: row["title"])
            }
            return Curriculum(units: units, lessons: lessons, prerequisites: prerequisites)
        }
    }

    /// Titles of the skills that have one (orientation topics), used as explanation text.
    public func skillTitles() async throws -> [SkillID: String] {
        try await read { db in
            var result: [SkillID: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, title FROM skill WHERE title IS NOT NULL") {
                result[try Self.skill(row["id"])] = row["title"]
            }
            return result
        }
    }

    /// The canonical words of `sura` that the content includes, in reading order.
    public func quranWords(sura: Int) async throws -> [QuranWordText] {
        let quran = quran
        return try await read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT ayah, word, text, token_shared FROM quran_word_ref WHERE sura = ? ORDER BY ayah, word",
                arguments: [sura]
            ).map { row in
                guard let verse = AyahNumber(quran: quran, sura: sura, ayah: row["ayah"]) else {
                    throw ContentError.malformedRow("quran_word_ref \(sura):\(row["ayah"] as Int)")
                }
                return QuranWordText(
                    word: Word(verse: verse, wordNumber: row["word"]),
                    text: QuranText(row["text"]),
                    sharesToken: row["token_shared"] as Int != 0
                )
            }
        }
    }

    // MARK: Private

    private let db: DatabaseConnection
    private let quran: Quran

    private static func skill(_ raw: String) throws -> SkillID {
        guard let id = SkillID(raw) else {
            throw ContentError.malformedRow("skill \(raw)")
        }
        return id
    }

    /// Runs `block` after checking the schema version. The check is its own read so that
    /// `ContentError.unsupportedSchema` reaches callers unwrapped (`DatabaseConnection.read` wraps
    /// errors thrown inside its block in `PersistenceError`).
    private func read<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        let version = try await db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'schema_version'")
        }
        guard version == Self.schemaVersion else {
            throw ContentError.unsupportedSchema(version)
        }
        return try await db.read(block)
    }
}
