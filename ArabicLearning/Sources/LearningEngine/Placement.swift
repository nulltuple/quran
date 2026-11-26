//
//  Placement.swift
//  ArabicLearning (Arabican app)
//

import Foundation
import LearningModel

/// The placement check for learners who can already read (spec 03 §2): it asks each unit's check
/// skill (`check.<unit>`) in unit order and stops at the first unit the learner does not pass.
/// Passing a unit places the learner past it and every unit before it. Deterministic and pure; the
/// caller asks `current`, shows an exercise for its skill and calls `record` with the outcome.
public struct PlacementTest: Hashable, Sendable {
    // MARK: Lifecycle

    /// `units` in curriculum order with their check skill, nil for a unit without a check (U1).
    public init(units: [(id: String, check: SkillID?)], itemsPerUnit: Int = 4, passMark: Int = 3) {
        self.units = units.map { Unit(id: $0.id, check: $0.check) }
        self.itemsPerUnit = itemsPerUnit
        self.passMark = passMark
        index = self.units.firstIndex { $0.check != nil } ?? self.units.count
    }

    /// A placement over every unit of `curriculum`, using the check lessons the compiler adds.
    public init(curriculum: Curriculum, itemsPerUnit: Int = 4, passMark: Int = 3) {
        let units = curriculum.units.map { unit in
            (id: unit.id, check: curriculum.lessons(in: unit).flatMap(\.teaches).first { $0.family == "check" })
        }
        self.init(units: units, itemsPerUnit: itemsPerUnit, passMark: passMark)
    }

    // MARK: Public

    /// Units passed so far, with every unit before them, in curriculum order.
    public private(set) var placedUnits: [String] = []

    /// The check skill to ask next, or nil when the placement is over.
    public var current: SkillID? {
        units.indices.contains(index) ? units[index].check : nil
    }

    public var isFinished: Bool {
        current == nil
    }

    /// Counts one answer to `current`. Skipped and unscorable answers are not correct.
    public mutating func record(_ outcome: AttemptOutcome) {
        guard !isFinished else { return }
        asked += 1
        if outcome == .correct {
            correct += 1
        }
        if correct >= passMark {
            placedUnits = units[...index].map(\.id)
            moveToNextCheckedUnit()
        } else if correct + (itemsPerUnit - asked) < passMark {
            index = units.count
        }
    }

    // MARK: Private

    private struct Unit: Hashable, Sendable {
        let id: String
        let check: SkillID?
    }

    private let units: [Unit]
    private let itemsPerUnit: Int
    private let passMark: Int
    private var index: Int
    private var asked = 0
    private var correct = 0

    private mutating func moveToNextCheckedUnit() {
        asked = 0
        correct = 0
        index = units[(index + 1)...].firstIndex { $0.check != nil } ?? units.count
    }
}

public enum PlacementMastery {
    /// Mastery from evidence, with every skill of a placed unit counted as mastered unless the
    /// learner practiced it after the placement (then the newer evidence decides).
    /// `placements`: unit id → when the learner placed past it.
    public static func mastery(
        evidence: [SkillID: SkillEvidence],
        placements: [String: Date],
        curriculum: Curriculum
    ) -> [SkillID: MasteryState] {
        var mastery = Dictionary(uniqueKeysWithValues: evidence.map { ($0.key, $0.value.state(for: $0.key)) })
        for lesson in curriculum.lessons {
            guard let placedAt = placements[lesson.unit] else { continue }
            for skill in lesson.teaches {
                if let last = evidence[skill]?.lastAttempt, last > placedAt {
                    continue
                }
                mastery[skill] = .mastered
            }
        }
        return mastery
    }
}
