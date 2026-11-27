//
//  HifzReviewFormatting.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import Localization
import MemorizationService
import SwiftUI

enum HifzReviewFormatting {
    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .fixedCurrentLocaleNumbers
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func bucketName(_ bucket: ReviewBucket) -> String {
        switch bucket {
        case .sabaq: l("hifz_review.bucket.sabaq")
        case .sabqi: l("hifz_review.bucket.sabqi")
        case .manzil: l("hifz_review.bucket.manzil")
        }
    }

    static func bucketDescription(_ bucket: ReviewBucket) -> String {
        switch bucket {
        case .sabaq: l("hifz_review.bucket.sabaq.description")
        case .sabqi: l("hifz_review.bucket.sabqi.description")
        case .manzil: l("hifz_review.bucket.manzil.description")
        }
    }

    static func bucketColor(_ bucket: ReviewBucket) -> Color {
        switch bucket {
        case .sabaq: .orange
        case .sabqi: .red
        case .manzil: .blue
        }
    }

    static func stateLabel(_ state: AyahMemorizationState) -> String {
        switch state {
        case .notMemorized: l("hifz_review.state.not_memorized")
        case .declaredUnassessed: l("hifz_review.state.declared")
        case .learning: l("hifz_review.state.learning")
        case .weak: l("hifz_review.state.weak")
        case .strong: l("hifz_review.state.strong")
        }
    }

    static func stateColor(_ state: AyahMemorizationState) -> Color {
        switch state {
        case .notMemorized: Color(.systemGray4)
        case .declaredUnassessed: .blue
        case .learning: .orange
        case .weak: .red
        case .strong: .green
        }
    }

    static func strengthLabel(_ strength: PassageStrength, isDeclared: Bool) -> String {
        switch strength {
        case .unassessed: isDeclared ? l("hifz_review.state.declared") : l("hifz_review.state.not_memorized")
        case .learning: l("hifz_review.state.learning")
        case .weak: l("hifz_review.state.weak")
        case .strong: l("hifz_review.state.strong")
        }
    }

    static func strengthColor(_ strength: PassageStrength, isDeclared: Bool) -> Color {
        switch strength {
        case .unassessed: isDeclared ? .blue : .secondary
        case .learning: .orange
        case .weak: .red
        case .strong: .green
        }
    }

    static func reasonText(_ reason: ReviewReason) -> String {
        switch reason {
        case .weakSessions(let count):
            if count <= 1 {
                return l("hifz_review.reason.weak_one")
            }
            return lFormat("hifz_review.reason.weak_many", NumberFormatter.shared.format(count))
        case .overdueDays(let days):
            if days <= 1 {
                return l("hifz_review.reason.overdue_one")
            }
            return lFormat("hifz_review.reason.overdue_many", NumberFormatter.shared.format(days))
        case .dueToday:
            return l("hifz_review.reason.due_today")
        case .learning:
            return l("hifz_review.reason.learning")
        case .declaredUnassessed:
            return l("hifz_review.reason.declared_unassessed")
        case .snoozedUntil(let date):
            return lFormat("hifz_review.reason.snoozed", shortDateFormatter.string(from: date))
        case .scheduledInDays(let days):
            if days <= 1 {
                return l("hifz_review.reason.in_one_day")
            }
            return lFormat("hifz_review.reason.in_many_days", NumberFormatter.shared.format(days))
        }
    }
}
