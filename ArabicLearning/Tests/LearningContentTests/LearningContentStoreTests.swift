import ArabicScript
import LearningContent
import LearningModel
import QuranKit
import QuranResources
import VerseTextPersistence
import XCTest

/// Exercises the bundled, compiled database and cross-checks it against ArabicScript and the
/// canonical Uthmani text in QuranResources.
final class LearningContentStoreTests: XCTestCase {
    private let store = LearningContentStore()

    func test_lettersMatchArabicScriptInOrderAndForms() async throws {
        let letters = try await store.letters()
        XCTAssertEqual(letters.map(\.letter), ArabicLetter.allCases)
        for info in letters {
            XCTAssertEqual(info.forms, info.letter.forms, info.letter.rawValue)
        }
        XCTAssertEqual(letters.first?.name, "alif")
        XCTAssertEqual(letters.map(\.ordinal), Array(1 ... 29))
    }

    func test_curriculumIsOrderedAndItsPrerequisitesComeFirst() async throws {
        let curriculum = try await store.curriculum()
        XCTAssertEqual(curriculum.lessons.first?.id, "u1.l01")
        XCTAssertEqual(curriculum.units.map(\.id), ["U1", "U2", "U3", "U4", "U5", "U6", "U7", "U8", "U9", "U10"])
        XCTAssertEqual(curriculum.checkRequirements.keys.map(\.rawValue).sorted(), ["U2", "U3", "U4", "U5", "U6", "U7"].map { "check.\($0)" })
        XCTAssertEqual(curriculum.units.flatMap { curriculum.lessons(in: $0) }, curriculum.lessons)
        XCTAssertEqual(curriculum.lessons.map(\.ordinal), Array(1 ... curriculum.lessons.count))
        var taught: Set<SkillID> = []
        for lesson in curriculum.lessons {
            for skill in lesson.requires {
                XCTAssertTrue(taught.contains(skill), "\(lesson.id) requires \(skill) before it is taught")
            }
            for skill in lesson.teaches {
                for prerequisite in curriculum.prerequisites[skill] ?? [] {
                    XCTAssertTrue(
                        taught.contains(prerequisite) || lesson.teaches.contains(prerequisite),
                        "\(skill) needs \(prerequisite)"
                    )
                }
            }
            taught.formUnion(lesson.teaches)
        }
        let soundOfBa = try XCTUnwrap(SkillID("letter.sound.ب"))
        XCTAssertEqual(curriculum.prerequisites[soundOfBa], [SkillID("letter.recognize.ب")!, SkillID("orientation.rtl")!])
    }

    func test_alFatihahWordsAreCanonicalTextByteForByte() async throws {
        let words = try await store.quranWords(sura: 1)
        XCTAssertEqual(words.count, 29)
        let quran = Quran.hafsMadani1405
        let verses = quran.suras[0].verses
        let canonical = try await GRDBQuranVerseTextPersistence(fileURL: QuranResources.quranUthmaniV2Database)
            .textForVerses(verses)
        for word in words {
            let tokens = try XCTUnwrap(canonical[word.word.verse]).text.split(separator: " ")
            XCTAssertEqual(Array(word.text.text.utf8), Array(tokens[word.word.wordNumber - 1].utf8), "\(word.word)")
        }
        XCTAssertEqual(Set(words.map(\.word.verse)), Set(verses))
    }

    func test_everyCanonicalAyahDecomposesWithoutUnknownCharacters() async throws {
        let quran = Quran.hafsMadani1405
        let texts = try await GRDBQuranVerseTextPersistence(fileURL: QuranResources.quranUthmaniV2Database)
            .textForVerses(quran.verses)
        XCTAssertEqual(texts.count, 6236)
        for (verse, text) in texts {
            let graphemes = try XCTUnwrap(ArabicScript.graphemes(of: text.text), "\(verse)")
            XCTAssertEqual(graphemes.map(\.text).joined(), text.text, "\(verse)")
            for grapheme in graphemes {
                if case .unknown(let scalar) = grapheme.base {
                    XCTFail("\(verse): unknown base U+\(String(scalar.value, radix: 16, uppercase: true))")
                }
            }
        }
    }

    func test_rejectsAnUnsupportedSchema() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schema-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: LearningContentStore.bundledDatabaseURL, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try DatabaseQueueForTests(url: url)
        try writer.setSchemaVersion("99")
        do {
            _ = try await LearningContentStore(fileURL: url).letters()
            XCTFail("expected unsupportedSchema")
        } catch let error as LearningContentStore.ContentError {
            XCTAssertEqual(error, .unsupportedSchema("99"))
        }
    }
}

import GRDB

/// Edits a copied content database in place (test-only).
private struct DatabaseQueueForTests {
    init(url: URL) throws {
        queue = try DatabaseQueue(path: url.path)
    }

    func setSchemaVersion(_ version: String) throws {
        try queue.write { try $0.execute(sql: "UPDATE meta SET value = ? WHERE key = 'schema_version'", arguments: [version]) }
    }

    private let queue: DatabaseQueue
}
