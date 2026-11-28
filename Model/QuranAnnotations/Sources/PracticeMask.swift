//
//  PracticeMask.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranKit

/// The words Hifz practice hides on the page (roadmap H2): every word of `hiddenVerses`, and the
/// words of `partialVerse` after its first `revealedWords` (QUL word numbering), except `cueWords`,
/// which stay visible as cues (progressive masking).
public struct PracticeMask: Hashable, Sendable {
    // MARK: Lifecycle

    public init(
        hiddenVerses: Set<AyahNumber>,
        partialVerse: AyahNumber?,
        revealedWords: Int,
        cueWords: Set<Word> = [],
        mistakeWords: Set<Word> = [],
        activeWord: Word? = nil,
        pendingMistakeWord: Word? = nil
    ) {
        self.hiddenVerses = hiddenVerses
        self.partialVerse = partialVerse
        self.revealedWords = revealedWords
        self.cueWords = cueWords
        self.mistakeWords = mistakeWords
        self.activeWord = activeWord
        self.pendingMistakeWord = pendingMistakeWord
    }

    // MARK: Public

    public var hiddenVerses: Set<AyahNumber>
    public var partialVerse: AyahNumber?
    public var revealedWords: Int
    public var cueWords: Set<Word>
    /// Revealed canonical words (QUL numbering) flagged as live mistakes during recitation practice.
    public var mistakeWords: Set<Word>
    /// The latest recited/revealed canonical word, highlighted as the live moving cursor.
    public var activeWord: Word?
    /// The next still-hidden canonical word when a live stumble/hesitation was detected on it.
    public var pendingMistakeWord: Word?

    /// The ayah being compared after Check; translation readers may normally hide all Arabic.
    public var checkedVerse: AyahNumber?
    /// An explicit request to see the current ayah's selected translations during recall.
    public var showsMeaning = false

    public func showsWord(_ word: Word) -> Bool {
        cueWords.contains(word) || (partialVerse == word.verse && word.wordNumber <= revealedWords)
    }

    /// Whether any word of `verse` is hidden.
    public func hides(_ verse: AyahNumber) -> Bool {
        hiddenVerses.contains(verse) || partialVerse == verse
    }

    public func restricted(to page: Page) -> Self {
        var mask = PracticeMask(
            hiddenVerses: hiddenVerses.filter { $0.page == page },
            partialVerse: partialVerse.flatMap { $0.page == page ? $0 : nil },
            revealedWords: revealedWords,
            cueWords: cueWords.filter { $0.verse.page == page },
            mistakeWords: mistakeWords.filter { $0.verse.page == page },
            activeWord: activeWord.flatMap { $0.verse.page == page ? $0 : nil },
            pendingMistakeWord: pendingMistakeWord.flatMap { $0.verse.page == page ? $0 : nil }
        )
        mask.checkedVerse = checkedVerse.flatMap { $0.page == page ? $0 : nil }
        mask.showsMeaning = showsMeaning && mask.partialVerse != nil
        return mask
    }
}
