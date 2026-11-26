import LearningUI
import XCTest

final class AppTabTests: XCTestCase {
    func test_tabsAppearInSpecOrder() {
        XCTAssertEqual(AppTab.allCases, [.learn, .practice, .quran, .progress])
    }

    func test_titlesAreLocalizedNotKeys() {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Learn", "Practice", "Quran", "Progress"])
    }

    func test_everyTabHasADistinctSymbol() {
        XCTAssertEqual(Set(AppTab.allCases.map(\.systemImage)).count, AppTab.allCases.count)
    }
}
