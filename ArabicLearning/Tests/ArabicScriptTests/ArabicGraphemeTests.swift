import ArabicScript
import XCTest

final class ArabicGraphemeTests: XCTestCase {
    /// Al-Fatihah 1:1 as stored in QuranResources' `quran.ar.uthmani.v2.db`.
    private let bismillah = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"

    func test_graphemesRoundTripTheTextExactly() throws {
        let graphemes = try XCTUnwrap(ArabicScript.graphemes(of: bismillah))
        XCTAssertEqual(graphemes.map(\.text).joined(), bismillah)
        XCTAssertEqual(Array(graphemes.map(\.text).joined().utf8), Array(bismillah.utf8))
    }

    func test_firstWordDecomposesIntoLettersAndMarks() throws {
        let graphemes = try XCTUnwrap(ArabicScript.graphemes(of: "بِسۡمِ"))
        XCTAssertEqual(graphemes.map(\.letter), [.ba, .sin, .mim])
        XCTAssertEqual(graphemes.map(\.marks), [[.kasra], [.quranicSukun], [.kasra]])
        XCTAssertEqual(graphemes[1].marks.map(\.kind), [.sukun])
    }

    func test_shaddaAndDaggerAlifAreSeparateMarks() throws {
        let graphemes = try XCTUnwrap(ArabicScript.graphemes(of: "ٱلرَّحۡمَٰنِ"))
        XCTAssertEqual(graphemes.first?.base, .variant("ٱ", of: .alif))
        let ra = graphemes[2]
        XCTAssertEqual(ra.letter, .ra)
        // The canonical text stores the vowel before the shadda; marks keep source order.
        XCTAssertEqual(ra.marks, [.fatha, .shadda])
        XCTAssertTrue(ra.has(.shadda))
        let mim = graphemes[4]
        XCTAssertEqual(mim.marks.map(\.kind), [.shortVowel, .longVowel])
    }

    func test_spacesAndSymbolsAreTheirOwnGraphemes() throws {
        let graphemes = try XCTUnwrap(ArabicScript.graphemes(of: "۞ إِنَّ"))
        XCTAssertEqual(graphemes.map(\.base), [.symbol("۞"), .space, .variant("إ", of: .alif), .letter(.nun)])
    }

    func test_rejectsUnknownMarksAndOrphanMarks() {
        XCTAssertNil(ArabicScript.graphemes(of: "\u{064E}ب"), "A mark with no base")
        XCTAssertNil(ArabicScript.graphemes(of: "ب\u{0659}"), "U+0659 is not in the canonical text")
    }

    func test_everyMarkHasAKind() {
        XCTAssertEqual(ArabicMark.allCases.count, 30)
        XCTAssertEqual(ArabicMark.allCases.filter { $0.kind == .shortVowel }, [.fatha, .damma, .kasra])
    }
}
