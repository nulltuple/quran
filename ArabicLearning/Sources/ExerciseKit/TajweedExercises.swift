//
//  TajweedExercises.swift
//  ArabicLearning (Arabican app)
//

import LearningModel

/// Tajweed exercises (U9), milestone L6. Each rule has two skills: `tajweed.spot.<rule>` colors the
/// rule's letters in an ayah of a bridge sura, and `tajweed.listen.<rule>` plays those words with
/// the text hidden. Both ask which rule applies; the options are rule names. A rule that also
/// applies to the colored letters (spot) or to the played words (listen) is never a distractor,
/// so exactly one option is right.
extension ExerciseGenerator {
    func tajweedExercise(_ skill: SkillID, rule: String, listening: Bool, _ random: inout SeededRandom) -> Exercise? {
        guard let example = (tajweedByRule[rule] ?? []).randomElement(using: &random) else { return nil }
        let neighbors = tajweedByAyah[example.ayah] ?? []
        let applies = Set(neighbors.filter { other in
            listening ? example.sharesWords(with: other) : example.overlaps(other)
        }.map(\.rule.id))
        let candidates = tajweedRules.filter { !applies.contains($0.id) && $0.id != example.rule.id }
        let sameGroup = candidates.filter { $0.group == example.rule.group }.shuffled(using: &random)
        let others = candidates.filter { $0.group != example.rule.group }.shuffled(using: &random)
        let distractors = Self.unique((sameGroup + others).map(\.name).filter { $0 != example.rule.name }).prefix(optionCount - 1)
        guard !distractors.isEmpty else { return nil }
        return choice(
            skill,
            listening ? .tajweedListen(example) : .tajweedSpot(example),
            [example.rule.name] + distractors,
            example.rule.name,
            &random,
            recitation: example.recitation
        )
    }
}
