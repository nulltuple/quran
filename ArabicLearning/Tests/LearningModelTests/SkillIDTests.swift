import LearningModel
import XCTest

final class SkillIDTests: XCTestCase {
    func test_acceptsNamespacedIds() throws {
        let id = try XCTUnwrap(SkillID("letter.recognize.ب"))
        XCTAssertEqual(id.family, "letter")
        XCTAssertEqual(id.description, "letter.recognize.ب")
    }

    func test_rejectsMalformedIds() {
        for raw in ["", "letter", "letter.", ".letter", "letter..ب", "letter.recognize ب"] {
            XCTAssertNil(SkillID(raw), raw)
        }
    }

    func test_codableRoundTripAndRejection() throws {
        let id = try XCTUnwrap(SkillID("sound.discriminate.ح-ه"))
        let data = try JSONEncoder().encode([id])
        XCTAssertEqual(try JSONDecoder().decode([SkillID].self, from: data), [id])
        XCTAssertThrowsError(try JSONDecoder().decode([SkillID].self, from: Data(#"["bad"]"#.utf8)))
    }
}
