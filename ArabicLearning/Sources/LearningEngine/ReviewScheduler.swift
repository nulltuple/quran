//
//  ReviewScheduler.swift
//  ArabicLearning (Arabican app)
//

import Foundation
import FSRS
import LearningModel

/// Schedules recall reviews with FSRS (open-spaced-repetition/swift-fsrs). Fuzz is off so the same
/// history always gives the same due dates. Only recall skills are scheduled (letters, forms,
/// lemma meanings); unscorable attempts leave the card untouched.
public struct ReviewScheduler: Sendable {
    // MARK: Lifecycle

    public init(parameters: FSRSParameters = FSRSParameters(enableFuzz: false)) {
        fsrs = FSRS(parameters: parameters)
    }

    // MARK: Public

    /// A card for a skill never reviewed, due now.
    public func newCard(now: Date) -> Card {
        Card(due: now)
    }

    /// The card after an attempt: correct is FSRS "good", incorrect is "again", unscorable is no review.
    public func review(_ card: Card, outcome: AttemptOutcome, at date: Date) throws -> Card {
        switch outcome {
        case .correct: try fsrs.next(card: card, now: date, grade: .good).card
        case .incorrect: try fsrs.next(card: card, now: date, grade: .again).card
        case .unscorable: card
        }
    }

    /// Skills whose recall the scheduler tracks.
    public static func isScheduled(_ skill: SkillID) -> Bool {
        skill.rawValue.hasPrefix("letter.") || skill.rawValue.hasPrefix("lemma.")
    }

    // MARK: Private

    private let fsrs: FSRS
}
