//
//  ProgressViewModel.swift
//  ArabicLearning (Arabican app)
//

import LearningContent
import LearningEngine
import LearningModel
import LearningPersistence
import Observation

/// The Progress tab: per unit, how many skills are mastered. Counts only, never "% understood"
/// (spec 03 risk 8).
@MainActor
@Observable
public final class ProgressViewModel {
    // MARK: Lifecycle

    public init(content: LearningContentStore, progress: ProgressStore) {
        self.content = content
        self.progress = progress
    }

    // MARK: Public

    public struct UnitProgress: Identifiable, Equatable, Sendable {
        public let unit: LearningUnit
        public let mastered: Int
        public let practicing: Int
        public let total: Int
        public var id: String { unit.id }
    }

    public private(set) var units: [UnitProgress] = []
    public private(set) var failed = false

    public func load() async {
        do {
            async let curriculum = content.curriculum()
            async let evidence = progress.evidence()
            let (loadedCurriculum, loadedEvidence) = try await (curriculum, evidence)
            units = loadedCurriculum.units.map { unit in
                let skills = loadedCurriculum.lessons(in: unit).flatMap(\.teaches)
                let states = skills.map { loadedEvidence[$0]?.state(for: $0) ?? .notAssessed }
                return UnitProgress(
                    unit: unit,
                    mastered: states.filter { $0 == .mastered }.count,
                    practicing: states.filter { $0 == .learning || $0 == .uncertain }.count,
                    total: skills.count
                )
            }
            failed = false
        } catch {
            failed = true
        }
    }

    // MARK: Private

    private let content: LearningContentStore
    private let progress: ProgressStore
}
