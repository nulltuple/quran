//
//  LearnViewModel.swift
//  ArabicLearning (Arabican app)
//

import LearningContent
import LearningModel
import Observation

/// The Learn tab: the curriculum's units and lessons from the compiled content.
@MainActor
@Observable
public final class LearnViewModel {
    // MARK: Lifecycle

    public init(content: LearningContentStore) {
        self.content = content
    }

    // MARK: Public

    public enum State: Equatable {
        case loading
        case loaded(Curriculum)
        case failed
    }

    public private(set) var state: State = .loading

    public func load() async {
        do {
            state = .loaded(try await content.curriculum())
        } catch {
            state = .failed
        }
    }

    // MARK: Private

    private let content: LearningContentStore
}
