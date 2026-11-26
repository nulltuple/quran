//
//  SkillGraph.swift
//  ArabicLearning (Arabican app)
//

import LearningModel

/// Unlocking and lesson order over the curriculum's prerequisite DAG (validated at compile time).
public struct SkillGraph: Sendable {
    // MARK: Lifecycle

    public init(curriculum: Curriculum) {
        self.curriculum = curriculum
    }

    // MARK: Public

    public let curriculum: Curriculum

    /// A skill is unlocked when every direct prerequisite is mastered.
    public func isUnlocked(_ skill: SkillID, mastery: [SkillID: MasteryState]) -> Bool {
        (curriculum.prerequisites[skill] ?? []).allSatisfy { mastery[$0] == .mastered }
    }

    /// Taught skills that are unlocked and not yet mastered, in lesson order.
    public func unlockedUnmastered(mastery: [SkillID: MasteryState]) -> [SkillID] {
        curriculum.taughtSkills.filter { mastery[$0] != .mastered && isUnlocked($0, mastery: mastery) }
    }

    /// The first lesson with an unmastered skill whose requirements are all mastered.
    public func nextLesson(mastery: [SkillID: MasteryState]) -> Lesson? {
        curriculum.lessons.first { lesson in
            lesson.teaches.contains { mastery[$0] != .mastered }
                && lesson.requires.allSatisfy { mastery[$0] == .mastered }
        }
    }

    /// Whether every skill of `lesson` is mastered.
    public func isComplete(_ lesson: Lesson, mastery: [SkillID: MasteryState]) -> Bool {
        lesson.teaches.allSatisfy { mastery[$0] == .mastered }
    }
}
