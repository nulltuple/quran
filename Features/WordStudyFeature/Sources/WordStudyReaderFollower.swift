//
//  WordStudyReaderFollower.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import QuranKit

/// Keeps the reader behind the word study sheet on the ayah of the word being studied: opening
/// another word from an occurrence list jumps the reader to its ayah, going back follows, and
/// closing the sheet returns the reader to the ayah the study started from.
@MainActor
public final class WordStudyReaderFollower {
    // MARK: Lifecycle

    /// `showVerse` moves the reader to an ayah; it is called only when the ayah changes.
    public init(origin: AyahNumber, showVerse: @escaping (AyahNumber) -> Void) {
        self.origin = origin
        shownVerse = origin
        self.showVerse = showVerse
    }

    // MARK: Public

    public let origin: AyahNumber

    /// The ayah the reader shows now.
    public private(set) var shownVerse: AyahNumber

    /// Returns the reader to the ayah the study started from, when it moved.
    public func returnToOrigin() {
        show(origin)
    }

    // MARK: Internal

    /// Moves the reader to `verse`, when it shows another ayah.
    func show(_ verse: AyahNumber) {
        guard verse != shownVerse else {
            return
        }
        shownVerse = verse
        showVerse(verse)
    }

    // MARK: Private

    private let showVerse: (AyahNumber) -> Void
}
