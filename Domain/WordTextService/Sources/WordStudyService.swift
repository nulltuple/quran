//
//  WordStudyService.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Foundation
import QuranKit
import QuranText
import WordTextPersistence

/// A word with what the word study sheet shows about it.
public struct WordStudy: Hashable, Sendable {
    public init(morphology: WordMorphology, meaning: String?, transliteration: String?) {
        self.morphology = morphology
        self.meaning = meaning
        self.transliteration = transliteration
    }

    public let morphology: WordMorphology
    /// The word's meaning in the reader's word-by-word language, or English when meanings are off.
    public let meaning: String?
    public let transliteration: String?

    public var word: Word { morphology.word }

    /// The word's Arabic text, its segments joined.
    public var arabic: String { morphology.segments.map(\.text).joined() }
}

/// One word in an occurrence list.
public struct WordOccurrence: Hashable, Sendable {
    public init(word: Word, arabic: String, meaning: String?) {
        self.word = word
        self.arabic = arabic
        self.meaning = meaning
    }

    public let word: Word
    public let arabic: String
    public let meaning: String?
}

/// Word study (roadmap C2): a word's segments, grammar, lemma and root from the bundled corpus
/// morphology, its meaning and transliteration from the word-by-word data, and every word in the
/// Quran that shares its lemma or root, in pages.
public struct WordStudyService: Sendable {
    // MARK: Lifecycle

    public init(morphologyFileURL: URL, wordByWordFileURL: URL) {
        morphology = GRDBWordMorphologyPersistence(fileURL: morphologyFileURL)
        words = GRDBWordByWordPersistence(fileURL: wordByWordFileURL)
    }

    // MARK: Public

    /// `word`'s study, or `nil` when the corpus has no such word.
    public func study(of word: Word, language: WordByWordLanguage) async throws -> WordStudy? {
        async let segments = morphology.segments(of: word)
        async let meaning = words.text(for: word, column: language.meaningColumn)
        async let transliteration = words.text(for: word, column: .transliteration)
        let loadedSegments = try await segments
        guard !loadedSegments.isEmpty else {
            return nil
        }
        return try await WordStudy(
            morphology: WordMorphology(word: word, segments: loadedSegments),
            meaning: meaning,
            transliteration: transliteration
        )
    }

    /// Up to `limit` words with `term` after `after` (from the first when `nil`), in Quran order.
    public func occurrences(
        of term: WordStudyTerm,
        quran: Quran,
        after: Word?,
        limit: Int,
        language: WordByWordLanguage
    ) async throws -> [WordOccurrence] {
        let found = try await morphology.occurrences(of: term, quran: quran, after: after, limit: limit)
        try Task.checkCancellation()
        let meanings = try await words.texts(for: found.map(\.0), column: language.meaningColumn)
        return found.map { WordOccurrence(word: $0.0, arabic: $0.1, meaning: meanings[$0.0]) }
    }

    // MARK: Private

    private let morphology: GRDBWordMorphologyPersistence
    private let words: GRDBWordByWordPersistence
}

private extension WordByWordLanguage {
    /// The sheet always shows a meaning: the chosen language, or English when meanings are off.
    var meaningColumn: WordTextColumn {
        switch self {
        case .off, .english: .english
        case .bengali: .bengali
        }
    }
}
