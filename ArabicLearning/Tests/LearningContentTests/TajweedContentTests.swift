import ArabicScript
import LearningContent
import LearningModel
import QuranKit
import XCTest

/// L6 content: tajweed rules and their examples in the bridge suras. The spans come from Python
/// (Tools/learning/tajweed.py); these tests check them against ArabicScript's own grapheme split,
/// so the two languages agree on which letters a rule colors.
final class TajweedContentTests: XCTestCase {
    private let store = LearningContentStore()

    private func examples() async throws -> [TajweedExample] {
        try await store.tajweedExamples(bridges: store.bridgeSuras())
    }

    private func colored(_ example: TajweedExample) throws -> [ArabicGrapheme] {
        try example.words.flatMap { word in
            let graphemes = try XCTUnwrap(ArabicScript.graphemes(of: word.text.text))
            let range = try XCTUnwrap(example.highlights[word.word])
            XCTAssertLessThan(range.upperBound, graphemes.count, "\(word.word) \(example.rule.id)")
            return Array(graphemes[range.clamped(to: 0 ... graphemes.count - 1)])
        }
    }

    func test_everyRuleHasExamplesAndEveryTaughtSkillHasARule() async throws {
        let examples = try await examples()
        let rules = Set(examples.map(\.rule.id))
        XCTAssertEqual(rules.count, 13)
        let curriculum = try await store.curriculum()
        let taught = curriculum.lessons.flatMap(\.teaches).filter { $0.family == "tajweed" }
        XCTAssertEqual(taught.count, 26, "spot and listen for each rule")
        for skill in taught {
            XCTAssertTrue(rules.contains(String(skill.rawValue.split(separator: ".")[2])), "\(skill)")
        }
        XCTAssertEqual(curriculum.lessons.filter { $0.unit == "U9" }.map(\.title).first, "Natural madd")
    }

    func test_coloredLettersAreTheLettersEachRuleIsAbout() async throws {
        for example in try await examples() {
            let graphemes = try colored(example)
            let text = graphemes.map(\.text).joined()
            let letters = graphemes.compactMap(\.letter)
            switch example.rule.group {
            case "madd":
                let writesMadd = text.unicodeScalars.contains { "اوىيۥۦٰٓ".unicodeScalars.contains($0) }
                XCTAssertTrue(writesMadd, "\(example.rule.id) \(text)")
            case "noon":
                let carrier = try XCTUnwrap(graphemes.first)
                XCTAssertTrue(carrier.letter == .nun || carrier.has(.tanwin), "\(example.rule.id) \(text)")
                XCTAssertGreaterThanOrEqual(graphemes.count, 2, "the noon and the letter after it: \(text)")
            case "meem":
                XCTAssertEqual(graphemes.first?.letter, .mim, text)
            default:
                if example.rule.id == "qalqalah" {
                    XCTAssertTrue(letters.allSatisfy { [.qaf, .taHeavy, .ba, .jim, .dal].contains($0) }, text)
                } else {
                    XCTAssertTrue(graphemes.allSatisfy { [.nun, .mim].contains($0.letter) && $0.has(.shadda) }, text)
                }
            }
        }
    }

    func test_recitationCoversTheRulesWords() async throws {
        let suras = try await store.bridgeSuras()
        for example in try await examples() {
            let sura = try XCTUnwrap(suras.first { $0.recording == example.recitation.url })
            let words = sura.words.filter { example.highlights[$0.word.word] != nil }
            XCTAssertEqual(example.recitation.start, words.first?.start)
            XCTAssertEqual(example.recitation.end, words.last?.end)
            XCTAssertLessThan(example.recitation.start, example.recitation.end)
        }
    }

    func test_knownExamples() async throws {
        let examples = try await examples()
        let merging = try XCTUnwrap(examples.first { $0.rule.id == "noonIdghamNoGhunnah" })
        XCTAssertEqual(merging.words.map(\.text.text).joined(separator: " "), "يَكُن لَّهُۥ")
        XCTAssertEqual(try colored(merging).map(\.text), ["ن", "لَّ"])
        let lazim = try XCTUnwrap(examples.first { $0.rule.id == "maddLazim" })
        XCTAssertEqual(lazim.words.first?.word, Word(verse: AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 7)!, wordNumber: 9))
        XCTAssertEqual(Set(examples.map(\.agreement)), [.both, .phonetizer, .reviewed])
    }
}
