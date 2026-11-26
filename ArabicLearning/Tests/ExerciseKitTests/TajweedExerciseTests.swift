import ExerciseKit
import LearningContent
import LearningModel
import XCTest

/// L6 exercises: spot a rule in colored letters, and hear it with the text hidden.
final class TajweedExerciseTests: XCTestCase {
    private nonisolated(unsafe) static var cached: (ExerciseGenerator, [TajweedExample])?

    private let seeds = 0 ..< 20 as Range<UInt64>

    private func content() async throws -> (generator: ExerciseGenerator, examples: [TajweedExample]) {
        if let cached = Self.cached { return cached }
        let store = LearningContentStore()
        let examples = try await store.tajweedExamples(bridges: store.bridgeSuras())
        let generator = try await ExerciseGenerator(letters: store.letters(), tajweed: examples)
        Self.cached = (generator, examples)
        return (generator, examples)
    }

    func test_exactlyOneOptionNamesARuleOfTheShownOrPlayedLetters() async throws {
        let (generator, examples) = try await content()
        let rules = Dictionary(examples.map { ($0.rule.id, $0.rule) }) { first, _ in first }
        let names = Set(rules.values.map(\.name))
        for rule in rules.values {
            for ability in ["spot", "listen"] {
                for seed in seeds {
                    let skill = SkillID("tajweed.\(ability).\(rule.id)")!
                    let exercise = try XCTUnwrap(generator.exercise(for: skill, seed: seed), "\(skill)")
                    guard case .choice(let options, let answer) = exercise.kind else { return XCTFail("expected a choice") }
                    let example: TajweedExample
                    switch exercise.prompt {
                    case .tajweedSpot(let shown) where ability == "spot": example = shown
                    case .tajweedListen(let played) where ability == "listen": example = played
                    default: return XCTFail("unexpected prompt \(exercise.prompt)")
                    }
                    XCTAssertEqual(example.rule, rule)
                    XCTAssertEqual(options[answer], rule.name)
                    XCTAssertEqual(exercise.recitation, example.recitation)
                    XCTAssertEqual(Set(options).count, options.count)
                    XCTAssertEqual(options.count, 4, "\(skill)")
                    XCTAssertTrue(options.allSatisfy(names.contains))
                    // No distractor is a rule that also applies where the learner looks or listens.
                    let neighbors = examples.filter { $0.ayah == example.ayah && $0.rule != rule }
                    let applies = neighbors.filter { ability == "spot" ? example.overlaps($0) : example.sharesWords(with: $0) }
                    for other in applies {
                        XCTAssertFalse(options.contains(other.rule.name), "\(skill): \(other.rule.id) also applies")
                    }
                }
            }
        }
    }

    func test_distractorsPreferTheSameGroup() async throws {
        let (generator, _) = try await content()
        let exercise = try XCTUnwrap(generator.exercise(for: SkillID("tajweed.spot.noonIkhfa")!, seed: 3))
        guard case .choice(let options, _) = exercise.kind else { return XCTFail("expected a choice") }
        XCTAssertEqual(Set(options), ["Hidden noon (ikhfa)", "Clear noon (izhar)", "Merging with ghunnah", "Merging without ghunnah"])
    }

    func test_aRuleWithoutExamplesHasNoExercise() async throws {
        let (generator, _) = try await content()
        XCTAssertNil(generator.exercise(for: SkillID("tajweed.spot.unknownRule")!, seed: 1))
    }
}
