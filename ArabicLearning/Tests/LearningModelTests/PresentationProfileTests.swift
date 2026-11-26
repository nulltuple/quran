import LearningModel
import XCTest

final class PresentationProfileTests: XCTestCase {
    func test_childSessionsAreShorterAndUntimed() {
        XCTAssertLessThan(PresentationProfile.child.sessionMinutes.upperBound, PresentationProfile.adult.sessionMinutes.upperBound)
        XCTAssertLessThan(PresentationProfile.child.itemsPerStep.upperBound, PresentationProfile.adult.itemsPerStep.upperBound)
        XCTAssertFalse(PresentationProfile.child.allowsTimers)
        XCTAssertTrue(PresentationProfile.adult.allowsTimers)
    }
}
