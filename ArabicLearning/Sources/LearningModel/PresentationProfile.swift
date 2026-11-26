//
//  PresentationProfile.swift
//  ArabicLearning (Arabican app)
//

/// How lessons are presented. Child and adult learners share one curriculum, one set of items
/// and answers, and one progress model; only presentation differs (ADR-0001 §4.4).
public enum PresentationProfile: String, CaseIterable, Sendable, Codable {
    case child
    case adult

    // MARK: Public

    /// Target session length in minutes.
    public var sessionMinutes: ClosedRange<Int> {
        switch self {
        case .child: 3 ... 7
        case .adult: 5 ... 20
        }
    }

    /// Items shown in one lesson step.
    public var itemsPerStep: ClosedRange<Int> {
        switch self {
        case .child: 4 ... 6
        case .adult: 6 ... 10
        }
    }

    /// Children never see countdown timers.
    public var allowsTimers: Bool {
        self == .adult
    }
}
