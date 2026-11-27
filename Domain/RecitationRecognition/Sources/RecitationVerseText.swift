//
//  RecitationVerseText.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import QuranKit
import VerseTextPersistence
import WordTextService

/// The Quran text recognition compares with, from the bundled databases: every verse's plain text
/// for `VerseMatcher`, and canonical words with their Uthmani text for `WordAligner`.
public struct RecitationVerseText: Sendable {
    // MARK: Lifecycle

    public init(quranUthmaniV2Database: URL, wordByWordDatabase: URL, quran: Quran = .hafsMadani1405) {
        verseText = GRDBQuranVerseTextPersistence(fileURL: quranUthmaniV2Database)
        expectedWords = ExpectedWordsReader(uthmaniText: verseText, wordByWord: WordByWordService(fileURL: wordByWordDatabase))
        self.quran = quran
    }

    // MARK: Public

    public let expectedWords: ExpectedWordsReader

    /// A matcher over all 6,236 verses (about a second to build; build it once and keep it).
    public func makeMatcher() async throws -> VerseMatcher {
        try await VerseMatcher(verses: verseText.searchTextOfAllVerses(quran: quran))
    }

    // MARK: Private

    private let verseText: GRDBQuranVerseTextPersistence
    private let quran: Quran
}
