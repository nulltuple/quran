import ArabicScript
import XCTest

final class ArabicLetterTests: XCTestCase {
    func test_alphabetHas28LettersPlusHamza() {
        XCTAssertEqual(ArabicLetter.allCases.count, 29)
        XCTAssertEqual(ArabicLetter.allCases.first, .alif)
        XCTAssertEqual(ArabicLetter.allCases.dropLast().last, .ya)
        XCTAssertEqual(Set(ArabicLetter.allCases.map(\.rawValue)).count, 29)
        XCTAssertTrue(ArabicLetter.allCases.allSatisfy { $0.rawValue.unicodeScalars.count == 1 })
    }

    func test_nonJoinersHaveOnlyIsolatedAndFinalForms() {
        let nonJoiners = ArabicLetter.allCases.filter { !$0.joinsToNext }
        XCTAssertEqual(nonJoiners.map(\.rawValue).joined(), "ادذرزوء")
        XCTAssertEqual(ArabicLetter.dal.forms, [.isolated, .final])
        XCTAssertEqual(ArabicLetter.hamza.forms, [.isolated])
        XCTAssertEqual(ArabicLetter.ba.forms, LetterForm.allCases)
    }

    func test_formTextUsesZeroWidthJoiners() {
        XCTAssertEqual(ArabicLetter.ba.text(in: .initial), "ب\u{200D}")
        XCTAssertEqual(ArabicLetter.ba.text(in: .medial), "\u{200D}ب\u{200D}")
        XCTAssertEqual(ArabicLetter.ba.text(in: .final), "\u{200D}ب")
        XCTAssertNil(ArabicLetter.ra.text(in: .medial))
        XCTAssertEqual(ArabicLetter.ra.text(in: .final), "\u{200D}ر")
    }
}
