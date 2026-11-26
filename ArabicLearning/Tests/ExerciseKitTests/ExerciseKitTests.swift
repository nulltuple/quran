import ArabicScript
import ExerciseKit
import LearningContent
import LearningEngine
import LearningModel
import XCTest

final class ExerciseKitTests: XCTestCase {
    private func generator() async throws -> ExerciseGenerator {
        try await ExerciseGenerator(letters: LearningContentStore().letters(), skillTitles: [SkillID("orientation.rtl")!: "Right to left"])
    }

    func test_recognitionUsesTheLettersShapeFamilyAsDistractors() async throws {
        let generator = try await generator()
        let exercise = try XCTUnwrap(generator.exercise(for: SkillID("letter.recognize.ب")!, seed: 7))
        XCTAssertEqual(exercise.prompt, .findLetterNamed("bā"))
        guard case .choice(let options, let answer) = exercise.kind else { return XCTFail("expected choice") }
        XCTAssertEqual(options.count, 4)
        XCTAssertEqual(options[answer], "ب")
        XCTAssertTrue(Set(options).isSuperset(of: ["ب", "ت", "ث"]), "ba's family: \(options)")
        XCTAssertEqual(Set(options).count, 4)
    }

    func test_sameSeedSameExerciseDifferentSeedDifferentOrder() async throws {
        let generator = try await generator()
        let skill = SkillID("letter.sound.ج")!
        XCTAssertEqual(generator.exercise(for: skill, seed: 42), generator.exercise(for: skill, seed: 42))
        let orders = Set((0 ..< 20).compactMap { seed -> [String]? in
            guard case .choice(let options, _)? = generator.exercise(for: skill, seed: UInt64(seed))?.kind else { return nil }
            return options
        })
        XCTAssertGreaterThan(orders.count, 1)
    }

    /// Pins one exercise so a change to the generator or the content is noticed.
    func test_fixtureForSeedOne() async throws {
        let generator = try await generator()
        let exercise = try XCTUnwrap(generator.exercise(for: SkillID("sound.discriminate.ذ-ز-ظ")!, seed: 1))
        guard case .choice(let options, let answer) = exercise.kind, case .letterForSound(let sound) = exercise.prompt else {
            return XCTFail("expected a letter-for-sound choice")
        }
        XCTAssertEqual(Set(options), ["ذ", "ز", "ظ"])
        let letters = try await generator.letters(for: sound)
        XCTAssertEqual(letters, [options[answer]])
    }

    func test_matchGradesEachPair() async throws {
        let skills = ["ا", "ب", "ت"].map { SkillID("letter.recognize.\($0)")! }
        let generator = try await generator()
        let exercise = try XCTUnwrap(generator.matchExercise(for: skills, seed: 5))
        guard case .match(let left, let right, let answers) = exercise.kind else { return XCTFail("expected match") }
        XCTAssertEqual(left, ["ا", "ب", "ت"])
        XCTAssertEqual(Set(right), ["alif", "bā", "tā"])
        XCTAssertEqual(ExerciseGrader.grade(exercise, .match(answers)), [.correct, .correct, .correct])
        let swapped = [answers[1], answers[0], answers[2]]
        XCTAssertEqual(ExerciseGrader.grade(exercise, .match(swapped)), [.incorrect, .incorrect, .correct])
    }

    func test_skippingIsUnscorableNeverWrong() async throws {
        let generator = try await generator()
        let exercise = try XCTUnwrap(generator.exercise(for: SkillID("letter.recognize.م")!, seed: 2))
        XCTAssertEqual(ExerciseGrader.grade(exercise, .skipped), [.unscorable])
        guard case .choice(_, let answer) = exercise.kind else { return XCTFail("expected choice") }
        XCTAssertEqual(ExerciseGrader.grade(exercise, .choice(answer)), [.correct])
        XCTAssertEqual(ExerciseGrader.grade(exercise, .choice((answer + 1) % 4)), [.incorrect])
    }

    func test_orientationIsAnExplanation() async throws {
        let generator = try await generator()
        let exercise = try XCTUnwrap(generator.exercise(for: SkillID("orientation.rtl")!, seed: 0))
        XCTAssertEqual(exercise.prompt, .explanation("Right to left"))
        XCTAssertEqual(ExerciseGrader.grade(exercise, .acknowledged), [.correct])
    }
}

private extension ExerciseGenerator {
    /// Test helper: which letters' sound is `sound` (via the recognition exercise's content).
    func letters(for sound: String) async throws -> [String] {
        try await LearningContentStore().letters().filter { $0.sound == sound }.map(\.letter.rawValue)
    }
}
