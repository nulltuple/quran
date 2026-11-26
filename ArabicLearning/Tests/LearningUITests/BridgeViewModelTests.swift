import LearningContent
import LearningUI
import XCTest

@MainActor
final class BridgeViewModelTests: XCTestCase {
    func test_loadsTheBridgeSurasInLessonOrder() async {
        let viewModel = BridgeViewModel(content: LearningContentStore())
        await viewModel.load()
        guard case .loaded(let suras) = viewModel.state else {
            return XCTFail("expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(suras.map(\.sura), [1, 112, 113, 114, 108, 103, 110, 111])
    }

    func test_reportsFailureForAMissingDatabase() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).sqlite")
        let viewModel = BridgeViewModel(content: LearningContentStore(fileURL: missing))
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .failed)
    }
}
