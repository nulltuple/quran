//
//  SessionPlanner.swift
//  ArabicLearning (Arabican app)
//

import Foundation
import LearningModel

/// One planned practice item: a skill and why it was chosen.
public struct PlannedItem: Hashable, Sendable {
    public enum Reason: String, Hashable, Sendable {
        case dueReview
        case weakSkill
        case newLesson
    }

    public init(skill: SkillID, reason: Reason) {
        self.skill = skill
        self.reason = reason
    }

    public let skill: SkillID
    public let reason: Reason
}

/// Plans a session: due reviews first, then the weakest unlocked skills, then the next lesson's new
/// skills, capped by the presentation profile (ADR-0001 §4.4). Deterministic for the same inputs.
public struct SessionPlanner: Sendable {
    // MARK: Lifecycle

    public init(graph: SkillGraph) {
        self.graph = graph
    }

    // MARK: Public

    public let graph: SkillGraph

    /// The number of items in a session for `profile`.
    public static func itemCap(for profile: PresentationProfile) -> Int {
        profile.itemsPerStep.upperBound * 2
    }

    /// A unit check is asked this many times when its lesson is new, enough to master it in one
    /// session when every answer is right.
    public static let checkItems = 5

    /// `placements`: unit id → when the learner placed past it (see `PlacementMastery`).
    public func plan(
        profile: PresentationProfile,
        evidence: [SkillID: SkillEvidence],
        dueReviews: [SkillID: Date],
        placements: [String: Date] = [:],
        now: Date
    ) -> [PlannedItem] {
        let cap = Self.itemCap(for: profile)
        let mastery = PlacementMastery.mastery(evidence: evidence, placements: placements, curriculum: graph.curriculum)
        var items: [PlannedItem] = []
        var used: Set<SkillID> = []
        func add(_ skill: SkillID, _ reason: PlannedItem.Reason, repeating: Bool = false) {
            guard items.count < cap, used.insert(skill).inserted || repeating else {
                return
            }
            items.append(PlannedItem(skill: skill, reason: reason))
        }

        let due = dueReviews.filter { $0.value <= now }.sorted { ($0.value, $0.key.rawValue) < ($1.value, $1.key.rawValue) }
        due.prefix(cap / 2).forEach { add($0.key, .dueReview) }

        let weak = graph.unlockedUnmastered(mastery: mastery)
            .filter { evidence[$0].map { $0.scoredAttempts > 0 || $0.unscorableAttempts > 0 } ?? false }
            .sorted { (evidence[$0]?.successRate ?? 0, $0.rawValue) < (evidence[$1]?.successRate ?? 0, $1.rawValue) }
        weak.prefix(cap / 4).forEach { add($0, .weakSkill) }

        // A lesson's skills may build on each other (a letter's sound on its shape); they are
        // listed in teaching order, so practicing them in order respects that.
        // New recall skills get a second round, since mastery needs several correct answers; a
        // unit check gets `checkItems` rounds.
        if let lesson = graph.nextLesson(mastery: mastery) {
            let fresh = lesson.teaches.filter { mastery[$0] != .mastered }
            fresh.forEach { add($0, .newLesson) }
            fresh.filter { $0.family != "orientation" }.forEach { skill in
                let rounds = skill.family == "check" ? Self.checkItems - 1 : 1
                (0 ..< rounds).forEach { _ in add(skill, .newLesson, repeating: true) }
            }
        }
        return items
    }
}
