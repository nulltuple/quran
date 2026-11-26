//
//  ProgressiveSubstitution.swift
//  ArabicLearning (Arabican app)
//

import LearningModel

/// Progressive-substitution reading (milestone L7, inventory #19; the idea of ayyat's
/// `VocabularyStore` display modes, reimplemented on our mastery model): the reader shows an
/// ayah's meaning word by word, and a word the learner knows appears in Arabic instead of its
/// meaning. As vocabulary is mastered, more of the meaning line becomes Arabic.
public enum ProgressiveSubstitution {
    /// The skill whose mastery means the learner knows `lemma`'s meaning.
    public static func skill(for lemma: Lemma) -> SkillID? {
        SkillID("lemma.meaning.\(lemma.text)")
    }

    /// The words the learner knows: every lemma in the word (prefixes such as `بِ` and `وَ`
    /// included) has a mastered meaning skill. Pronoun suffixes have no lemma and need nothing.
    /// A word without any lemma, or with a lemma outside the vocabulary (no evidence), is never
    /// known. Mastery decays (`SkillEvidence`), so a word can return to its meaning.
    public static func knownWords<Key: Hashable>(
        segments: [Key: [WordSegment]],
        evidence: [SkillID: SkillEvidence]
    ) -> Set<Key> {
        Set(segments.compactMap { key, segments in
            let lemmas = segments.compactMap(\.lemma)
            guard !lemmas.isEmpty else { return nil }
            let known = lemmas.allSatisfy { lemma in
                guard let skill = skill(for: lemma), let evidence = evidence[skill] else { return false }
                return evidence.state(for: skill) == .mastered
            }
            return known ? key : nil
        })
    }
}
