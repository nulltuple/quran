import ExerciseKit
import LearningContent
import LearningEngine
import LearningModel
import LearningPersistence
import LearningUI
import XCTest

@MainActor
final class PracticeViewModelTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("arabican-ui-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeViewModel(presentation: PresentationProfile = .adult) async throws -> (PracticeViewModel, ProgressStore) {
        let store = try ProfileStore(directory: directory)
        let profile = try await store.create(name: "Test", presentation: presentation, now: now)
        let progress = try store.progress(for: profile.id)
        let now = now
        return (PracticeViewModel(profile: profile, content: LearningContentStore(), progress: progress, now: { now }), progress)
    }

    func test_aNewLearnerStartsWithTheOrientationLesson() async throws {
        let (viewModel, _) = try await makeViewModel()
        await viewModel.start()
        guard case .exercise(let exercise) = viewModel.state else { return XCTFail("\(viewModel.state)") }
        XCTAssertEqual(exercise.kind, .explanation)
        XCTAssertEqual(exercise.prompt, .explanation("Arabic is read right to left"))
    }

    func test_answeringEverythingCorrectlyRecordsEvidenceAndFinishes() async throws {
        let (viewModel, progress) = try await makeViewModel()
        await viewModel.start()
        var answered = 0
        while case .exercise(let exercise) = viewModel.state {
            switch exercise.kind {
            case .explanation: await viewModel.answer(.acknowledged)
            case .choice(_, let answer): await viewModel.answer(.choice(answer))
            case .match(_, _, let answers): await viewModel.answer(.match(answers))
            case .trace(let guide): await viewModel.answer(.trace(guide.map(\.points)))
            }
            if case .feedback = viewModel.state { viewModel.advance() }
            answered += 1
        }
        guard case .finished(let summary) = viewModel.state else { return XCTFail("\(viewModel.state)") }
        XCTAssertEqual(summary.incorrect, 0)
        XCTAssertGreaterThan(summary.correct, 0)
        XCTAssertEqual(answered, viewModel.exercises.count)
        let attempts = try await progress.attemptCount()
        XCTAssertEqual(attempts, summary.correct)
    }

    /// After reading U1's two explanations, the next session starts the letters (u2.l01).
    func test_finishingOrientationUnlocksTheLetters() async throws {
        let (viewModel, _) = try await makeViewModel()
        await viewModel.start()
        XCTAssertEqual(viewModel.exercises.count, 2)
        await viewModel.answer(.acknowledged)
        await viewModel.answer(.acknowledged)
        guard case .finished = viewModel.state else { return XCTFail("\(viewModel.state)") }
        await viewModel.start()
        XCTAssertEqual(viewModel.exercises.first?.skills, [SkillID("letter.recognize.ا")!])
        XCTAssertTrue(viewModel.exercises.contains {
            if case .match = $0.kind {
                true
            } else {
                false
            }
        })
    }

    func test_skippingRecordsUnscorableAndMovesOn() async throws {
        let (viewModel, progress) = try await makeViewModel()
        await viewModel.start()
        await viewModel.answer(.acknowledged)
        await viewModel.answer(.acknowledged)
        await viewModel.start()
        guard case .exercise = viewModel.state else { return XCTFail("\(viewModel.state)") }
        let before = viewModel.position
        await viewModel.answer(.skipped)
        XCTAssertEqual(viewModel.position, before + 1)
        let evidence = try await progress.evidence()
        XCTAssertTrue(evidence.values.contains { $0.unscorableAttempts == 1 })
    }

    func test_childSessionsAreShorter() async throws {
        let (adult, _) = try await makeViewModel(presentation: .adult)
        await adult.start()
        try? FileManager.default.removeItem(at: directory)
        let (child, _) = try await makeViewModel(presentation: .child)
        await child.start()
        XCTAssertLessThanOrEqual(child.exercises.count, SessionPlanner.itemCap(for: .child) + 1)
        XCTAssertLessThanOrEqual(child.exercises.count, adult.exercises.count)
    }
}
