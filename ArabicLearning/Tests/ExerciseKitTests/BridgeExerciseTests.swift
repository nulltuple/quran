import ExerciseKit
import LearningContent
import LearningModel
import XCTest

/// L5 exercises: hearing a recited word, a word's meaning in its ayah, and lemma meanings.
final class BridgeExerciseTests: XCTestCase {
    private nonisolated(unsafe) static var cached: (ExerciseGenerator, [BridgeSura], [Lemma])?

    private let seeds = 0 ..< 25 as Range<UInt64>

    private func content() async throws -> (generator: ExerciseGenerator, suras: [BridgeSura], lemmas: [Lemma]) {
        if let cached = Self.cached { return cached }
        let store = LearningContentStore()
        let suras = try await store.bridgeSuras()
        let lemmas = try await store.lemmas()
        let generator = try await ExerciseGenerator(letters: store.letters(), bridges: suras, lemmas: lemmas)
        Self.cached = (generator, suras, lemmas)
        return (generator, suras, lemmas)
    }

    func test_listeningPlaysOneWordAndOffersDifferentWordsOfTheSameSura() async throws {
        let (generator, suras, _) = try await content()
        for sura in suras {
            let texts = Set(sura.words.map(\.word.text.text))
            for seed in seeds {
                let exercise = try XCTUnwrap(generator.exercise(for: SkillID("bridge.listen.\(sura.sura)")!, seed: seed))
                guard case .choice(let options, let answer) = exercise.kind, let segment = exercise.recitation else {
                    return XCTFail("expected a choice with a recitation")
                }
                XCTAssertEqual(exercise.prompt, .listenForWord)
                XCTAssertEqual(Set(options).count, options.count, "\(options)")
                XCTAssertTrue(options.allSatisfy(texts.contains))
                XCTAssertGreaterThanOrEqual(options.count, 2)
                XCTAssertEqual(segment.url, sura.recording)
                let played = try XCTUnwrap(sura.words.first { $0.start == segment.start && $0.end == segment.end })
                XCTAssertEqual(options[answer], played.word.text.text)
            }
        }
    }

    func test_meaningInAyahShowsTheWordInItsAyahAndOffersDistinctMeanings() async throws {
        let (generator, suras, _) = try await content()
        for sura in suras {
            for seed in seeds {
                let exercise = try XCTUnwrap(generator.exercise(for: SkillID("bridge.meaning.\(sura.sura)")!, seed: seed))
                guard case .choice(let options, let answer) = exercise.kind,
                      case .meaningInAyah(let word, let ayahWords) = exercise.prompt
                else {
                    return XCTFail("expected a meaning choice")
                }
                let ayah = try XCTUnwrap(sura.ayahs.first { $0.ayah == word.word.verse })
                XCTAssertEqual(ayahWords, ayah.words.map(\.word))
                let target = try XCTUnwrap(ayah.words.first { $0.word == word })
                XCTAssertEqual(options[answer], target.meaning.english)
                XCTAssertEqual(Set(options).count, options.count)
                XCTAssertEqual(exercise.recitation?.start, target.start)
                let answerWords = Self.words(options[answer])
                for (index, option) in options.enumerated() where index != answer {
                    XCTAssertTrue(Self.words(option).isDisjoint(with: answerWords), "\(option) vs \(options[answer])")
                }
            }
        }
    }

    func test_lemmaMeaningOffersTheGlossAndUnrelatedGlosses() async throws {
        let (generator, _, lemmas) = try await content()
        for lemma in lemmas.prefix(300) {
            let exercise = try XCTUnwrap(generator.exercise(for: SkillID("lemma.meaning.\(lemma.text)")!, seed: 7), lemma.text)
            guard case .choice(let options, let answer) = exercise.kind else { return XCTFail("expected a choice") }
            XCTAssertEqual(exercise.prompt, .meaningOfLemma(lemma.text))
            XCTAssertEqual(options[answer], lemma.english)
            XCTAssertEqual(options.count, 4)
            XCTAssertEqual(Set(options).count, 4)
        }
        XCTAssertNil(generator.exercise(for: SkillID("lemma.meaning.unknown")!, seed: 1))
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter { !["the", "a", "an", "to", "of"].contains($0) })
    }
}
