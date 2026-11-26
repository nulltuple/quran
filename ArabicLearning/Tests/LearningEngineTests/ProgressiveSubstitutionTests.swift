import LearningEngine
import LearningModel
import XCTest

final class ProgressiveSubstitutionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let bi = Lemma(text: "بِ", rank: 3, root: "", partOfSpeech: "preposition", occurrences: 1000, english: "with", bengali: "দিয়ে")
    private let ism = Lemma(text: "ٱسْم", rank: 90, root: "سمو", partOfSpeech: "noun", occurrences: 22, english: "name", bengali: "নাম")
    private let rare = Lemma(text: "صَمَد", rank: 2000, root: "صمد", partOfSpeech: "noun", occurrences: 1, english: "", bengali: "")

    private func segment(_ lemma: Lemma?, _ role: WordSegment.Role = .stem) -> WordSegment {
        WordSegment(text: lemma?.text ?? "هُ", role: role, lemma: lemma, root: lemma?.root ?? "", partOfSpeech: "")
    }

    private func mastered(_ count: Int = 4) -> SkillEvidence {
        var evidence = SkillEvidence()
        for _ in 0 ..< count {
            evidence.record(.correct, at: now)
        }
        return evidence
    }

    private func evidence(_ lemmas: [Lemma], _ value: SkillEvidence) -> [SkillID: SkillEvidence] {
        Dictionary(uniqueKeysWithValues: lemmas.map { (ProgressiveSubstitution.skill(for: $0)!, value) })
    }

    func test_aWordIsKnownOnlyWhenEveryLemmaInItIsMastered() {
        let segments = ["bismi": [segment(bi, .prefix), segment(ism)], "ismuhu": [segment(ism), segment(nil, .suffix)]]
        XCTAssertEqual(ProgressiveSubstitution.knownWords(segments: segments, evidence: evidence([ism], mastered())), ["ismuhu"])
        XCTAssertEqual(ProgressiveSubstitution.knownWords(segments: segments, evidence: evidence([bi, ism], mastered())), ["bismi", "ismuhu"])
    }

    func test_practicingIsNotKnowingAndWordsOutsideTheVocabularyStayGlossed() {
        let segments = ["ismuhu": [segment(ism)], "samad": [segment(rare)], "huwa": [segment(nil)]]
        XCTAssertEqual(ProgressiveSubstitution.knownWords(segments: segments, evidence: evidence([ism], mastered(3))), [])
        XCTAssertEqual(ProgressiveSubstitution.knownWords(segments: segments, evidence: evidence([ism], mastered())), ["ismuhu"])
        XCTAssertEqual(ProgressiveSubstitution.knownWords(segments: segments, evidence: [:]), [])
    }

    func test_theSkillIsTheVocabularyLessonsSkill() {
        XCTAssertEqual(ProgressiveSubstitution.skill(for: ism)?.rawValue, "lemma.meaning.ٱسْم")
    }
}
