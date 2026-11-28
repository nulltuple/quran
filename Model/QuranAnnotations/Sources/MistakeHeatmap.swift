//
//  MistakeHeatmap.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import QuranKit

/// Relative intensity of decayed recall mistakes for a word or ayah (roadmap H7).
public enum MistakeHeatLevel: Int, Hashable, Comparable, Codable, Sendable, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Reader-facing heatmap overlay of active mistakes across sessions (roadmap H7).
///
/// Kept strictly separate from tajweed coloring and inline similar-verse markers:
/// readers suppress this overlay during H2 Practice and on Tajweed Mushaf pages.
public struct MistakeHeatmapOverlay: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        verseLevels: [AyahNumber: MistakeHeatLevel] = [:],
        wordLevels: [Word: MistakeHeatLevel] = [:]
    ) {
        self.verseLevels = verseLevels
        self.wordLevels = wordLevels
    }

    // MARK: Public

    /// Overall decayed heat level per ayah (used by ayah-only renderers and ayahs without word breakdown).
    public var verseLevels: [AyahNumber: MistakeHeatLevel]
    /// Decayed heat level per canonical word (QUL numbering).
    public var wordLevels: [Word: MistakeHeatLevel]

    public var isEmpty: Bool {
        verseLevels.isEmpty && wordLevels.isEmpty
    }

    /// Word heat entries belonging to `verse`.
    public func wordLevels(for verse: AyahNumber) -> [Word: MistakeHeatLevel] {
        wordLevels.filter { $0.key.verse == verse }
    }

    /// Whether `verse` has word-level heat entries.
    public func hasWordHeat(for verse: AyahNumber) -> Bool {
        wordLevels.keys.contains { $0.verse == verse }
    }

    public func restricted(to page: Page) -> Self {
        MistakeHeatmapOverlay(
            verseLevels: verseLevels.filter { $0.key.page == page },
            wordLevels: wordLevels.filter { $0.key.verse.page == page }
        )
    }
}
