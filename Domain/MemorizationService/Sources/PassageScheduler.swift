//
//  PassageScheduler.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import FSRS

/// Schedules a passage's next review with FSRS (swift-fsrs, D2) by replaying its graded sessions.
/// The card is never stored: it is recomputed from evidence, so sync and backup carry evidence only.
public struct PassageScheduler: Sendable {
    // MARK: Lifecycle

    public init() {
        fsrs = FSRS(parameters: FSRSParameters(enableFuzz: false))
    }

    // MARK: Public

    public struct Review: Hashable, Sendable {
        public init(date: Date, grade: SessionGrade) {
            self.date = date
            self.grade = grade
        }

        public let date: Date
        public let grade: SessionGrade
    }

    /// The passage's state after `reviews` (any order); `.unassessed` with no due date when empty.
    public func schedule(_ reviews: [Review]) -> (strength: PassageStrength, due: Date?) {
        let reviews = reviews.sorted { $0.date < $1.date }
        guard let first = reviews.first, let last = reviews.last else {
            return (.unassessed, nil)
        }
        var card = Card(due: first.date)
        for review in reviews {
            // `next` throws only for a review dated before the card's last one, which sorting prevents.
            card = (try? fsrs.next(card: card, now: review.date, grade: Self.rating(review.grade)).card) ?? card
        }
        let strength: PassageStrength = switch (card.state, last.grade) {
        case (.review, .good): .strong
        case (.review, _): .weak
        default: .learning
        }
        return (strength, card.due)
    }

    // MARK: Private

    private let fsrs: FSRS

    private static func rating(_ grade: SessionGrade) -> Rating {
        switch grade {
        case .again: .again
        case .hard: .hard
        case .good: .good
        }
    }
}
