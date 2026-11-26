import ArabicScript
import Foundation
import LearningContent
import LearningModel
import XCTest

/// The L3 content: letter recordings, stroke guides and the letters of the compiled Quran words.
final class LetterMediaContentTests: XCTestCase {
    private let store = LearningContentStore()

    func test_everyClipIsABundledFileAndEveryLetterHasItsRecordings() async throws {
        let clips = try await store.audioClips()
        XCTAssertEqual(clips.count, 140)
        for clip in clips {
            XCTAssertTrue(FileManager.default.fileExists(atPath: clip.url.path), clip.url.lastPathComponent)
        }
        let keys = Set(clips.map { "\($0.letter.rawValue).\($0.kind.rawValue)" })
        for letter in ArabicLetter.allCases {
            XCTAssertTrue(keys.contains("\(letter.rawValue).name"), "\(letter.rawValue) name")
            if letter != .alif {
                for kind in ["fatha", "kasra", "damma"] {
                    XCTAssertTrue(keys.contains("\(letter.rawValue).\(kind)"), "\(letter.rawValue) \(kind)")
                }
            }
        }
    }

    func test_everyFormOfEveryLetterHasAStrokeGuideOnTheCanvas() async throws {
        let guides = try await store.strokeGuides()
        for letter in ArabicLetter.allCases {
            XCTAssertEqual(Set(guides[letter]?.keys.map { $0 } ?? []), Set(letter.forms), letter.rawValue)
            for (form, strokes) in guides[letter] ?? [:] {
                XCTAssertFalse(strokes.isEmpty, "\(letter.rawValue) \(form)")
                for stroke in strokes {
                    XCTAssertEqual(stroke.kind == .dot, stroke.points.count == 1, "\(letter.rawValue) \(form)")
                    XCTAssertTrue(stroke.points.allSatisfy { (0 ... 1).contains($0.x) && (0 ... 1).contains($0.y) })
                }
            }
        }
    }

    /// The compiler finds a word's letters in Python; ArabicScript must agree on what each word plainly writes.
    func test_wordLettersAgreeWithArabicScript() async throws {
        let words = try await store.wordLetters()
        XCTAssertEqual(words.filter { $0.pool == .practice }.count, 210)
        XCTAssertEqual(words.filter { $0.pool == .check }.count, 504)
        var plainly: Set<ArabicLetter> = []
        for entry in words {
            let graphemes = try XCTUnwrap(ArabicScript.graphemes(of: entry.word.text.text), entry.word.text.text)
            let bases = Set(graphemes.compactMap { grapheme -> ArabicLetter? in
                if case .letter(let letter) = grapheme.base { return letter }
                return nil
            })
            let variants = Set(graphemes.compactMap { grapheme -> ArabicLetter? in
                if case .variant(_, of: let letter) = grapheme.base { return letter }
                return nil
            })
            XCTAssertEqual(entry.exact, bases, entry.word.text.text)
            XCTAssertTrue(variants.isSubset(of: entry.exact.union(entry.implied)), entry.word.text.text)
            plainly.formUnion(entry.exact)
        }
        XCTAssertEqual(plainly, Set(ArabicLetter.allCases), "every letter has a word to find it in")
    }
}
