//
//  LearnerProfile.swift
//  ArabicLearning (Arabican app)
//

import Foundation

/// A local learner. Each profile's progress lives in its own database file; profiles never share
/// progress (spec 03 §1: same curriculum, separate local profiles).
public struct LearnerProfile: Identifiable, Hashable, Sendable, Codable {
    public init(id: UUID, name: String, presentation: PresentationProfile, createdAt: Date) {
        self.id = id
        self.name = name
        self.presentation = presentation
        self.createdAt = createdAt
    }

    public let id: UUID
    public var name: String
    public var presentation: PresentationProfile
    public let createdAt: Date
}
