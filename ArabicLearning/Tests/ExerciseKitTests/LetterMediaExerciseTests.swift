import ArabicScript
import ExerciseKit
import LearningContent
import LearningModel
import XCTest

/// L3 exercises built from the compiled audio clips, Quran words and stroke guides.
final class LetterMediaExerciseTests: XCTestCase {
    private func generator() async throws -> ExerciseGenerator {
        let store = LearningContentStore()
        return try await ExerciseGenerator(
            letters: store.letters(),
            clips: store.audioClips(),
            strokes: store.strokeGuides(),
            words: store.wordLetters()
        )
    }

    func test_letterSoundIsAListeningExerciseWithTheFathaRecording() async throws {
        let generator = try await generator()
        let exercise = try XCTUnwrap(generator.exercise(for: SkillID("letter.sound.ب")!, seed: 3))
        XCTAssertEqual(exercise.prompt, .listenForLetter)
        XCTAssertEqual(exercise.audio?.letter, .ba)
        XCTAssertEqual(exercise.audio?.kind, .fatha)
        guard case .choice(let options, let answer) = exercise.kind else { return XCTFail("expected choice") }
        XCTAssertEqual(options[answer], "ب")
        XCTAssertTrue(Set(options).isSuperset(of: ["ب", "ت", "ث"]), "ba's family: \(options)")
    }

    func test_alifKeepsTheTextPromptBecauseItHasNoFathaRecording() async throws {
        let generator = try await generator()
        let exercise = try XCTUnwrap(generator.exercise(for: SkillID("letter.sound.ا")!, seed: 3))
        XCTAssertEqual(exercise.prompt, .soundOfLetter(.alif))
        XCTAssertNil(exercise.audio)
    }

    func test_soundContrastsPlayTheTargetsRecording() async throws {
        let generator = try await generator()
        for seed in 0 ..< 10 as Range<UInt64> {
            let exercise = try XCTUnwrap(generator.exercise(for: SkillID("sound.discriminate.ذ-ز-ظ")!, seed: seed))
            guard case .choice(let options, let answer) = exercise.kind else { return XCTFail("expected choice") }
            XCTAssertEqual(exercise.prompt, .listenForLetter)
            XCTAssertEqual(Set(options), ["ذ", "ز", "ظ"])
            XCTAssertEqual(exercise.audio?.letter.rawValue, options[answer])
        }
    }

    func test_recognitionPlaysTheLettersName() async throws {
        let generator = try await generator()
        let exercise = try XCTUnwrap(generator.exercise(for: SkillID("letter.recognize.ع")!, seed: 1))
        XCTAssertEqual(exercise.audio?.kind, .name)
        XCTAssertEqual(exercise.audio?.letter, .ayn)
    }

    func test_findInWordAsksForALetterThePlainWordWritesAndOffersOnlyAbsentLetters() async throws {
        let store = LearningContentStore()
        let words = try await store.wordLetters()
        let generator = try await generator()
        for letter in ArabicLetter.allCases {
            for seed in 0 ..< 5 as Range<UInt64> {
                let exercise = try XCTUnwrap(generator.exercise(for: SkillID("letter.inword.\(letter.rawValue)")!, seed: seed))
                guard case .letterInWord(let word) = exercise.prompt, case .choice(let options, let answer) = exercise.kind else {
                    return XCTFail("expected a find-in-word choice")
                }
                let entry = try XCTUnwrap(words.first { $0.word == word })
                XCTAssertEqual(options[answer], letter.rawValue)
                XCTAssertTrue(word.text.text.unicodeScalars.contains(letter.scalar), "\(word.text.text) plainly writes \(letter.rawValue)")
                XCTAssertEqual(options.count, 4)
                for (index, option) in options.enumerated() where index != answer {
                    XCTAssertFalse(entry.holds(ArabicLetter(rawValue: option)!), "\(option) is in \(word.text.text)")
                }
            }
        }
    }

    func test_writingTracesTheIsolatedFormAndPlaysTheName() async throws {
        let generator = try await generator()
        let exercise = try XCTUnwrap(generator.exercise(for: SkillID("letter.write.ش")!, seed: 1))
        XCTAssertEqual(exercise.prompt, .traceLetter(.shin))
        XCTAssertEqual(exercise.audio?.kind, .name)
        guard case .trace(let guide) = exercise.kind else { return XCTFail("expected trace") }
        XCTAssertEqual(guide.map(\.kind), [.path, .dot, .dot, .dot])
    }

    func test_everyTaughtSkillHasAnExercise() async throws {
        let store = LearningContentStore()
        let generator = try await ExerciseGenerator(
            letters: store.letters(),
            skillTitles: store.skillTitles(),
            clips: store.audioClips(),
            strokes: store.strokeGuides(),
            words: store.wordLetters(),
            checks: store.curriculum().checkRequirements,
            bridges: store.bridgeSuras(),
            lemmas: store.lemmas()
        )
        for seed in [1, 3] as [UInt64] {
            let missing = try await store.curriculum().taughtSkills.filter { generator.exercise(for: $0, seed: seed) == nil }
            XCTAssertEqual(missing, [], "seed \(seed)")
        }
    }
}
