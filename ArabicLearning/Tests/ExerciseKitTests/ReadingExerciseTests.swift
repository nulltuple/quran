import ArabicScript
import ExerciseKit
import LearningContent
import LearningModel
import XCTest

/// L4 exercises (vowels, marks, decoding) and unit checks, built from the compiled content.
final class ReadingExerciseTests: XCTestCase {
    private nonisolated(unsafe) static var cached: (ExerciseGenerator, [WordLetters], Curriculum)?

    private let seeds = 0 ..< 25 as Range<UInt64>

    private func content() async throws -> (generator: ExerciseGenerator, words: [WordLetters], curriculum: Curriculum) {
        if let cached = Self.cached { return cached }
        let store = LearningContentStore()
        let curriculum = try await store.curriculum()
        let words = try await store.wordLetters()
        let generator = try await ExerciseGenerator(
            letters: store.letters(),
            skillTitles: store.skillTitles(),
            clips: store.audioClips(),
            strokes: store.strokeGuides(),
            words: words,
            checks: curriculum.checkRequirements
        )
        Self.cached = (generator, words, curriculum)
        return (generator, words, curriculum)
    }

    func test_listeningForASyllableOffersTheSameLetterWithEachVowel() async throws {
        let generator = try await content().generator
        for vowel in ["fatha", "kasra", "damma", "sukun"] {
            for seed in seeds {
                let exercise = try XCTUnwrap(generator.exercise(for: SkillID("vowel.listen.\(vowel)")!, seed: seed))
                guard case .choice(let options, let answer) = exercise.kind, let audio = exercise.audio else {
                    return XCTFail("expected a choice with audio")
                }
                XCTAssertEqual(exercise.prompt, .listenForSyllable)
                XCTAssertEqual(audio.kind.rawValue, vowel)
                XCTAssertEqual(options.count, vowel == "sukun" ? 4 : 3)
                XCTAssertTrue(options.allSatisfy { $0.unicodeScalars.first == audio.letter.scalar }, "\(options)")
                XCTAssertEqual(options[answer].unicodeScalars.count, 2)
                let mark = options[answer].unicodeScalars.last.flatMap(ArabicMark.init(scalar:))
                XCTAssertEqual(mark, vowel == "sukun" ? .quranicSukun : ArabicMark.allCases.first { vowel == "\($0)" })
            }
        }
    }

    func test_readingASyllableOffersItsLettersRecordings() async throws {
        let generator = try await content().generator
        for vowel in ["fatha", "kasra", "damma", "sukun"] {
            for seed in seeds {
                let exercise = try XCTUnwrap(generator.exercise(for: SkillID("vowel.read.\(vowel)")!, seed: seed))
                guard case .readSyllable(let text) = exercise.prompt, case .audioChoice(let clips, let answer) = exercise.kind else {
                    return XCTFail("expected a recording choice")
                }
                XCTAssertEqual(Set(clips.map(\.letter)).count, 1)
                XCTAssertEqual(clips[answer].kind.rawValue, vowel)
                XCTAssertEqual(text.unicodeScalars.first, clips[answer].letter.scalar)
                XCTAssertEqual(clips.count, vowel == "sukun" ? 4 : 3)
                XCTAssertEqual(ExerciseGrader.grade(exercise, .choice(answer)), [.correct])
                XCTAssertEqual(ExerciseGrader.grade(exercise, .choice((answer + 1) % clips.count)), [.incorrect])
            }
        }
    }

    func test_markSpottingAsksForTheOnlyGraphemeWithTheFeatureInAPracticeWord() async throws {
        let (generator, words, _) = try await content()
        let practice = Set(words.filter { $0.pool == .practice }.map(\.word))
        let features: [ReadingFeature] = [.longVowel, .sukun, .shadda, .tanwin, .silentLetter]
        for feature in features {
            for seed in seeds {
                let exercise = try XCTUnwrap(generator.exercise(for: SkillID("mark.spot.\(feature.rawValue)")!, seed: seed), "\(feature)")
                guard case .markInWord(let word, feature) = exercise.prompt, case .choice(let options, let answer) = exercise.kind else {
                    return XCTFail("expected a mark question")
                }
                XCTAssertTrue(practice.contains(word), word.text.text)
                let reading = try XCTUnwrap(ReadableWord(word.text.text))
                let marked = reading.graphemes.indices.filter { index in
                    feature == .silentLetter ? reading.isSilent(at: index) : reading.features[index].contains(feature)
                }.map { reading.graphemes[$0].text }
                XCTAssertEqual(marked, [options[answer]], "\(feature) in \(word.text.text)")
                XCTAssertEqual(Set(options).count, options.count)
                XCTAssertTrue(options.allSatisfy { option in reading.graphemes.contains { $0.text == option } })
                if feature == .longVowel {
                    XCTAssertTrue(reading.allFeatures.isSubset(of: [.shortVowel, .longVowel]), "nothing U6 teaches yet")
                }
            }
        }
    }

    func test_decodingUsesStageWordsAndHasExactlyOneRightAnswer() async throws {
        let (generator, words, _) = try await content()
        let practice = Set(words.filter { $0.pool == .practice }.map(\.word.text.text))
        var prompts: Set<String> = []
        for stage in ["short", "long", "marks", "full"] {
            for seed in seeds {
                let exercise = try XCTUnwrap(generator.exercise(for: SkillID("decode.words.\(stage)")!, seed: seed), stage)
                switch (exercise.prompt, exercise.kind) {
                case (.wordStartingWithSound, .choice(let options, let answer)):
                    prompts.insert("hear")
                    let audio = try XCTUnwrap(exercise.audio)
                    XCTAssertTrue(options.allSatisfy(practice.contains))
                    let matching = options.filter { option in
                        ReadableWord(option)?.onset.map { $0.letter == audio.letter && audio.kind.rawValue == "\($0.vowel)" } ?? false
                    }
                    XCTAssertEqual(matching, [options[answer]], "\(options) for \(audio.letter.rawValue) \(audio.kind)")
                    try assertStage(stage, options[answer])
                case (.firstSoundOfWord(let word), .audioChoice(let clips, let answer)):
                    prompts.insert("see")
                    XCTAssertTrue(practice.contains(word.text.text))
                    let onset = try XCTUnwrap(ReadableWord(word.text.text)?.onset)
                    XCTAssertEqual(clips[answer].letter, onset.letter)
                    XCTAssertEqual(clips[answer].kind.rawValue, "\(onset.vowel)")
                    try assertStage(stage, word.text.text)
                default:
                    XCTFail("unexpected \(exercise.prompt)")
                }
            }
        }
        XCTAssertEqual(prompts, ["hear", "see"])
    }

    /// Spec 03 §5.2 L4 gate: an unseen-item assessment for every unit, with no transliteration.
    func test_everyUnitCheckAsksUnseenItemsWithoutTransliteration() async throws {
        let (generator, words, curriculum) = try await content()
        let check = Set(words.filter { $0.pool == .check }.map(\.word))
        let checkTexts = Set(check.map(\.text.text))
        let practiceTexts = Set(words.filter { $0.pool == .practice }.map(\.word.text.text))
        XCTAssertEqual(curriculum.checkRequirements.count, 6)
        for (skill, required) in curriculum.checkRequirements {
            var asked: Set<String> = []
            for seed in 0 ..< 60 as Range<UInt64> {
                let exercise = try XCTUnwrap(generator.exercise(for: skill, seed: seed), "\(skill) seed \(seed)")
                XCTAssertEqual(exercise.skills, [skill])
                switch exercise.prompt {
                case .findLetterNamed, .soundOfLetter, .letterForSound, .traceLetter, .explanation, .matchLettersToNames:
                    XCTFail("\(skill) asked \(exercise.prompt)")
                case .letterInWord(let word), .firstSoundOfWord(let word), .markInWord(let word, _):
                    XCTAssertTrue(check.contains(word), "\(skill): \(word.text.text) is a practice word")
                case .wordStartingWithSound:
                    guard case .choice(let options, _) = exercise.kind else { return XCTFail("expected choice") }
                    XCTAssertTrue(options.allSatisfy(checkTexts.contains), "\(skill): \(options)")
                    XCTAssertTrue(options.allSatisfy { !practiceTexts.contains($0) })
                default:
                    break
                }
                if case .choice(let options, _) = exercise.kind {
                    XCTAssertFalse(options.contains { $0.unicodeScalars.contains(where: \.isASCII) }, "\(skill): transliterated \(options)")
                }
                asked.insert("\(exercise.prompt)".components(separatedBy: "(").first ?? "")
            }
            // U2 checks letters by ear only (their names and sounds); later units mix exercise types.
            if skill.rawValue != "check.U2" {
                XCTAssertGreaterThan(asked.count, 1, "\(skill) mixes exercise types: \(asked)")
            }
            XCTAssertFalse(required.contains { $0.rawValue.hasPrefix("letter.write.") || $0.family == "orientation" })
        }
    }

    private func assertStage(_ stage: String, _ text: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let features = try XCTUnwrap(ReadableWord(text), text, file: file, line: line).allFeatures
        switch stage {
        case "short": XCTAssertEqual(features, [.shortVowel], text, file: file, line: line)
        case "long": XCTAssertTrue(features.contains(.longVowel) && features.isSubset(of: [.shortVowel, .longVowel]), text, file: file, line: line)
        default: break
        }
    }
}
