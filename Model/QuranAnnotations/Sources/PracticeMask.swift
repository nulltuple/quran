//
//  PracticeMask.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranKit

/// The words Hifz practice hides on the page (roadmap H2): every word of `hiddenVerses`, and the
/// words of `partialVerse` after its first `revealedWords` (QUL word numbering).
public struct PracticeMask: Hashable, Sendable {
    // MARK: Lifecycle

    public init(hiddenVerses: Set<AyahNumber>, partialVerse: AyahNumber?, revealedWords: Int) {
        self.hiddenVerses = hiddenVerses
        self.partialVerse = partialVerse
        self.revealedWords = revealedWords
    }

    // MARK: Public

    public var hiddenVerses: Set<AyahNumber>
    public var partialVerse: AyahNumber?
    public var revealedWords: Int

    /// Whether any word of `verse` is hidden.
    public func hides(_ verse: AyahNumber) -> Bool {
        hiddenVerses.contains(verse) || partialVerse == verse
    }

    func restricted(to page: Page) -> Self {
        PracticeMask(
            hiddenVerses: hiddenVerses.filter { $0.page == page },
            partialVerse: partialVerse.flatMap { $0.page == page ? $0 : nil },
            revealedWords: revealedWords
        )
    }
}
