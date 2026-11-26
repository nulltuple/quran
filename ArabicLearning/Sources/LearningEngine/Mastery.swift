//
//  Mastery.swift
//  ArabicLearning (Arabican app)
//

import Foundation
import LearningModel

/// What one attempt at a skill showed. An unscorable attempt (no audio, skipped, self-assessed
/// "not sure") is never counted as wrong (spec 03 §7).
public enum AttemptOutcome: String, Codable, Sendable, CaseIterable {
    case correct
    case incorrect
    case unscorable
}

/// A skill's mastery state (ADR-0001 §4.4).
public enum MasteryState: String, Codable, Sendable, CaseIterable, Comparable {
    case notAssessed
    case uncertain
    case learning
    case mastered

    // MARK: Public

    public static func < (lhs: MasteryState, rhs: MasteryState) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Beta-style evidence for one skill: decayed successes and scored attempts, plus unscorable ones.
/// Older evidence counts less (half-life `MasteryPolicy.halfLife`), so mastery can fade.
public struct SkillEvidence: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(successes: Double = 0, scoredAttempts: Double = 0, unscorableAttempts: Int = 0, lastAttempt: Date? = nil) {
        self.successes = successes
        self.scoredAttempts = scoredAttempts
        self.unscorableAttempts = unscorableAttempts
        self.lastAttempt = lastAttempt
    }

    // MARK: Public

    public private(set) var successes: Double
    public private(set) var scoredAttempts: Double
    public private(set) var unscorableAttempts: Int
    public private(set) var lastAttempt: Date?

    /// Adds one attempt at `date`, first decaying the existing evidence by the time since the last one.
    public mutating func record(_ outcome: AttemptOutcome, at date: Date, policy: MasteryPolicy = .standard) {
        decay(to: date, policy: policy)
        switch outcome {
        case .correct:
            successes += 1
            scoredAttempts += 1
        case .incorrect:
            scoredAttempts += 1
        case .unscorable:
            unscorableAttempts += 1
        }
        lastAttempt = max(lastAttempt ?? date, date)
    }

    /// The estimated chance of a correct answer: the Beta(1, 1) posterior mean.
    public var successRate: Double {
        (successes + 1) / (scoredAttempts + 2)
    }

    /// The state under the policy for `skill` (explanations are mastered once read).
    public func state(for skill: SkillID) -> MasteryState {
        state(policy: .policy(for: skill))
    }

    public func state(policy: MasteryPolicy = .standard) -> MasteryState {
        if scoredAttempts == 0 {
            return unscorableAttempts > 0 ? .uncertain : .notAssessed
        }
        if scoredAttempts >= policy.minimumEvidence, successRate >= policy.masteryRate {
            return .mastered
        }
        return .learning
    }

    // MARK: Private

    private mutating func decay(to date: Date, policy: MasteryPolicy) {
        guard let lastAttempt, date > lastAttempt else {
            return
        }
        let factor = pow(0.5, date.timeIntervalSince(lastAttempt) / policy.halfLife)
        successes *= factor
        scoredAttempts *= factor
    }
}

/// Thresholds for mastery. Values are first estimates, to be tuned with real learners (UNVERIFIED).
public struct MasteryPolicy: Hashable, Sendable {
    public init(minimumEvidence: Double, masteryRate: Double, halfLife: TimeInterval) {
        self.minimumEvidence = minimumEvidence
        self.masteryRate = masteryRate
        self.halfLife = halfLife
    }

    /// At least about four recent scored attempts, posterior mean ≥ 0.8, evidence halves every 30 days.
    public static let standard = MasteryPolicy(minimumEvidence: 3.5, masteryRate: 0.8, halfLife: 30 * 24 * 3600)

    /// Orientation topics are explanations: reading one (a correct "continue") masters it.
    public static let explanation = MasteryPolicy(minimumEvidence: 1, masteryRate: 0.6, halfLife: 10 * 365 * 24 * 3600)

    public static func policy(for skill: SkillID) -> MasteryPolicy {
        skill.family == "orientation" ? .explanation : .standard
    }

    public let minimumEvidence: Double
    public let masteryRate: Double
    public let halfLife: TimeInterval
}
