import ArabicScript
import LearningContent
import LearningModel
import XCTest
@testable import ExerciseKit

/// Stroke fixtures come from the compiled Noorine guides, so a change to the content that breaks
/// tracing shows up here.
final class TraceCheckerTests: XCTestCase {
    private let checker = TraceChecker()

    private func guide(_ letter: ArabicLetter, _ form: LetterForm = .isolated) async throws -> [GuideStroke] {
        let guides = try await LearningContentStore().strokeGuides()
        return try XCTUnwrap(guides[letter]?[form], "\(letter) \(form)")
    }

    /// Draws `stroke` exactly, with intermediate points, like a finger would.
    private func trace(_ stroke: GuideStroke, offset: Double = 0, reversed: Bool = false) -> [CanvasPoint] {
        let points = stroke.points.map { CanvasPoint(x: $0.x + offset, y: $0.y + offset) }
        guard stroke.kind == .path else { return points }
        var dense: [CanvasPoint] = []
        for (a, b) in zip(points, points.dropFirst()) {
            for step in 0 ..< 10 {
                let t = Double(step) / 10
                dense.append(CanvasPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        dense.append(points[points.count - 1])
        return reversed ? dense.reversed() : dense
    }

    func test_anExactTracePassesForEveryFormOfEveryLetter() async throws {
        let guides = try await LearningContentStore().strokeGuides()
        XCTAssertEqual(guides.count, 29)
        for (letter, forms) in guides {
            for (form, guide) in forms {
                XCTAssertEqual(checker.check(guide.map { trace($0) }, against: guide), .passed, "\(letter.rawValue) \(form)")
            }
        }
    }

    func test_aSmallWobbleStillPasses() async throws {
        let ba = try await guide(.ba)
        XCTAssertEqual(checker.check(ba.map { trace($0, offset: 0.05) }, against: ba), .passed)
    }

    func test_aStrokeFarFromTheGuideFails() async throws {
        let ba = try await guide(.ba)
        XCTAssertEqual(checker.check([trace(ba[0], offset: 0.25), trace(ba[1])], against: ba), .offPath(index: 0))
    }

    func test_halfAStrokeFailsBecauseItMissesTheRest() async throws {
        let alif = try await guide(.alif)
        let full = trace(alif[0])
        XCTAssertEqual(checker.check([Array(full.prefix(full.count / 3))], against: alif), .offPath(index: 0))
    }

    func test_drawingAStrokeBackwardsFails() async throws {
        let alif = try await guide(.alif)
        XCTAssertEqual(checker.check([trace(alif[0], reversed: true)], against: alif), .wrongDirection(index: 0))
    }

    func test_aMissingOrExtraDotFails() async throws {
        let ta = try await guide(.ta)
        XCTAssertEqual(ta.filter { $0.kind == .dot }.count, 2)
        XCTAssertEqual(checker.check([trace(ta[0]), trace(ta[1])], against: ta), .wrongStrokeCount)
        XCTAssertEqual(checker.check(ta.map { trace($0) } + [[CanvasPoint(x: 0.1, y: 0.1)]], against: ta), .wrongStrokeCount)
    }

    func test_aTapAwayFromTheDotFailsAndDotsMayComeInAnyOrder() async throws {
        let ta = try await guide(.ta)
        let path = trace(ta[0])
        XCTAssertEqual(checker.check([path, trace(ta[2]), trace(ta[1])], against: ta), .passed)
        XCTAssertEqual(checker.check([path, trace(ta[1]), [CanvasPoint(x: 0.9, y: 0.1)]], against: ta), .missedDot(index: 2))
    }

    func test_gradingATraceExercise() async throws {
        let ba = try await guide(.ba)
        let exercise = Exercise(skills: [SkillID("letter.write.ب")!], prompt: .traceLetter(.ba), kind: .trace(guide: ba))
        XCTAssertEqual(ExerciseGrader.grade(exercise, .trace(ba.map { trace($0) })), [.correct])
        XCTAssertEqual(ExerciseGrader.grade(exercise, .trace([trace(ba[0])])), [.incorrect])
        XCTAssertEqual(ExerciseGrader.grade(exercise, .skipped), [.unscorable])
    }

    func test_resampleSpreadsPointsEvenly() {
        let line = [CanvasPoint(x: 0, y: 0), CanvasPoint(x: 0.1, y: 0), CanvasPoint(x: 1, y: 0)]
        let samples = TraceChecker.resample(line, count: 5)
        XCTAssertEqual(samples.map(\.x), [0, 0.25, 0.5, 0.75, 1], accuracy: 1e-9)
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) {
        XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line)
    }
}
