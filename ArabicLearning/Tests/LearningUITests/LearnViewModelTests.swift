import LearningContent
import LearningModel
import LearningUI
import XCTest

@MainActor
final class LearnViewModelTests: XCTestCase {
    func test_loadsTheBundledCurriculum() async {
        let viewModel = LearnViewModel(content: LearningContentStore())
        XCTAssertEqual(viewModel.state, .loading)
        await viewModel.load()
        guard case .loaded(let curriculum) = viewModel.state else {
            return XCTFail("expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(curriculum.units.first?.title, "Getting started")
        XCTAssertFalse(curriculum.lessons.isEmpty)
    }

    func test_reportsFailureForAMissingDatabase() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).sqlite")
        let viewModel = LearnViewModel(content: LearningContentStore(fileURL: missing))
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .failed)
    }
}
