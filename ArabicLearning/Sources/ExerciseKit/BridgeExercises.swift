//
//  BridgeExercises.swift
//  ArabicLearning (Arabican app)
//

import LearningModel

/// Quran bridge (U8) and vocabulary (U9) exercises, milestone L5. Bridge exercises use the bundled
/// recitation of practice suras; options always come from the same sura, so the learner chooses
/// among words they just heard in context.
extension ExerciseGenerator {
    /// `bridge.listen.<sura>`: hear one word of the recitation, pick it among other words of the
    /// sura written differently.
    func listenForWord(_ skill: SkillID, _ sura: BridgeSura, _ random: inout SeededRandom) -> Exercise? {
        guard let target = sura.words.randomElement(using: &random) else { return nil }
        let others = Self.unique(sura.words.map(\.word.text.text).filter { $0 != target.word.text.text })
            .shuffled(using: &random)
            .prefix(optionCount - 1)
        guard !others.isEmpty else { return nil }
        return choice(skill, .listenForWord, [target.word.text.text] + others, target.word.text.text, &random, recitation: sura.segment(target))
    }

    /// `bridge.meaning.<sura>`: a word shown in its ayah (and recited), pick its meaning among
    /// other meanings from the sura.
    func meaningInAyah(_ skill: SkillID, _ sura: BridgeSura, _ random: inout SeededRandom) -> Exercise? {
        let candidates = sura.ayahs.flatMap { ayah in ayah.words.map { (ayah, $0) } }.filter { !$0.1.meaning.english.isEmpty }
        guard let (ayah, target) = candidates.randomElement(using: &random) else { return nil }
        let answer = target.meaning.english
        let others = Self.unique(sura.words.map(\.meaning.english).filter { !$0.isEmpty && !Self.sameMeaning($0, answer) })
            .shuffled(using: &random)
            .prefix(optionCount - 1)
        guard !others.isEmpty else { return nil }
        return choice(
            skill,
            .meaningInAyah(target.word, ayah: ayah.words.map(\.word)),
            [answer] + others,
            answer,
            &random,
            recitation: sura.segment(target)
        )
    }

    /// `lemma.meaning.<lemma>`: a frequent lemma, pick its gloss. Distractors are glossed lemmas
    /// of the same part of speech close in rank (similarly common words), then any others.
    func meaningOfLemma(_ skill: SkillID, _ text: String, _ random: inout SeededRandom) -> Exercise? {
        guard let index = lemmaIndex[text] else { return nil }
        let target = lemmas[index]
        let nearby = lemmas[max(0, index - 30) ..< min(lemmas.count, index + 31)]
        let kind = target.partOfSpeech.prefix { $0 != "," }
        let sameKind = nearby.filter { $0.partOfSpeech.prefix { $0 != "," } == kind }.map(\.english).shuffled(using: &random)
        let rest = nearby.map(\.english).shuffled(using: &random)
        let others = Self.unique((sameKind + rest).filter { !Self.sameMeaning($0, target.english) }).prefix(optionCount - 1)
        guard !others.isEmpty else { return nil }
        return choice(skill, .meaningOfLemma(target.text), [target.english] + others, target.english, &random)
    }

    /// Meanings that share a word ("Lord" and "the Lord", "said" and "say / said") could both be
    /// right; never offer one as a distractor for the other.
    static func sameMeaning(_ first: String, _ second: String) -> Bool {
        let words = { (text: String) in
            Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter { !["the", "a", "an", "to", "of"].contains($0) })
        }
        let a = words(first)
        let b = words(second)
        return a == b || !a.isDisjoint(with: b)
    }

    /// Keeps the first of equal strings, in order.
    static func unique(_ strings: [String]) -> [String] {
        var seen: Set<String> = []
        return strings.filter { seen.insert($0).inserted }
    }
}
