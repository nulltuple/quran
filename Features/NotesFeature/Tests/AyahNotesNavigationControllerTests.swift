#if QURAN_SYNC
import UIKit
import XCTest
@testable import NotesFeature

@MainActor
final class AyahNotesNavigationControllerTests: XCTestCase {
    func test_sheet_optsOutOfTheVerticalBarWhateverItShows() {
        let navigationController = AyahNotesNavigationController(rootViewController: UIViewController())

        XCTAssertEqual(navigationController.preferredVerticalBarBehavior, .disabled)
        XCTAssertNil(navigationController.childForPreferredVerticalBarBehavior)
    }
}
#endif
