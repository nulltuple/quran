//
//  ArabicanRootViewModel.swift
//  ArabicLearning (Arabican app)
//

import LearningContent
import LearningModel
import LearningPersistence
import Observation

/// Chooses the active local profile and builds the per-profile screens' view models.
@MainActor
@Observable
public final class ArabicanRootViewModel {
    // MARK: Lifecycle

    public init(content: LearningContentStore, profiles: ProfileStore) {
        self.content = content
        self.profiles = profiles
        learn = LearnViewModel(content: content)
        bridge = BridgeViewModel(content: content)
    }

    // MARK: Public

    public struct Session {
        public let profile: LearnerProfile
        public let practice: PracticeViewModel
        public let progress: ProgressViewModel
    }

    public enum State {
        case loading
        case needsProfile
        case ready(Session)
        case failed
    }

    public let learn: LearnViewModel
    public let bridge: BridgeViewModel
    public private(set) var state: State = .loading
    public private(set) var allProfiles: [LearnerProfile] = []

    public func load() async {
        do {
            allProfiles = try await profiles.profiles()
            if let active = try await profiles.activeProfile() {
                try open(active)
            } else {
                state = .needsProfile
            }
        } catch {
            state = .failed
        }
    }

    public func createProfile(name: String, presentation: PresentationProfile) async {
        do {
            let profile = try await profiles.create(name: name, presentation: presentation)
            allProfiles = try await profiles.profiles()
            try open(profile)
        } catch {
            state = .failed
        }
    }

    public func switchTo(_ profile: LearnerProfile) async {
        do {
            try await profiles.setActive(profile.id)
            try open(profile)
        } catch {
            state = .failed
        }
    }

    /// Shows profile setup again, keeping existing profiles to pick from.
    public func requestProfileChoice() {
        state = .needsProfile
    }

    // MARK: Private

    private let content: LearningContentStore
    private let profiles: ProfileStore

    private func open(_ profile: LearnerProfile) throws {
        let progress = try profiles.progress(for: profile.id)
        state = .ready(Session(
            profile: profile,
            practice: PracticeViewModel(profile: profile, content: content, progress: progress),
            progress: ProgressViewModel(content: content, progress: progress)
        ))
    }
}
