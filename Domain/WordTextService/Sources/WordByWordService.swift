//
//  WordByWordService.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import Foundation
import QuranKit
import QuranText
import WordTextPersistence

/// Word-by-word meanings, transliterations and page-image word positions, with words numbered
/// as QUL numbers them (canonical word numbers), the numbering recited words use.
public struct WordByWordService: Sendable {
    // MARK: Lifecycle

    public init(fileURL: URL) {
        persistence = GRDBWordByWordPersistence(fileURL: fileURL)
    }

    // MARK: Public

    /// The meaning of each word in `verses` in `language`; empty when `language` is `.off`.
    public func meanings(for verses: [AyahNumber], language: WordByWordLanguage) async throws -> [Word: String] {
        guard let column = language.column else {
            return [:]
        }
        return try await persistence.texts(for: verses, column: column)
    }

    /// The meaning of `word` in `language`, or its transliteration; `nil` when it has none or
    /// `language` is `.off`.
    public func text(for word: Word, type: WordTextType, language: WordByWordLanguage) async throws -> String? {
        let column: WordTextColumn
        switch type {
        case .transliteration: column = .transliteration
        case .translation:
            guard let languageColumn = language.column else {
                return nil
            }
            column = languageColumn
        }
        return try await persistence.text(for: word, column: column)
    }

    /// The number of words in each of `verses`, as recited words number them.
    public func wordCounts(for verses: [AyahNumber]) async throws -> [AyahNumber: Int] {
        try await persistence.wordCounts(for: verses)
    }

    /// The page-image glyphs of each word in `verses`, for readings whose images have a verified
    /// word mapping; empty for other readings, which then highlight whole ayahs only. Usually one
    /// glyph; a word the image draws in two parts has two.
    public func imageWords(for verses: [AyahNumber], reading: Reading) async throws -> [Word: ImageWordGlyphs] {
        guard reading == .hafs_1405 else {
            return [:]
        }
        let positions = try await persistence.hafs1405GlyphPositions(for: verses)
        return positions.reduce(into: [:]) { words, entry in
            words[entry.key] = ImageWordGlyphs(
                first: Word(verse: entry.key.verse, wordNumber: entry.value.lowerBound),
                last: Word(verse: entry.key.verse, wordNumber: entry.value.upperBound)
            )
        }
    }

    /// The word a page-image glyph draws; `nil` for a mark (pause sign, ۞, ۩, ayah number) and
    /// for readings without a word mapping, so nothing unverified is shown for them.
    public func word(atImageGlyph glyph: Word, reading: Reading) async throws -> Word? {
        guard reading == .hafs_1405 else {
            return nil
        }
        return try await persistence.hafs1405Word(atGlyph: glyph)
    }

    /// How each of `verses`' canonical words line up with the bundled Uthmani text's tokens.
    public func textLayouts(for verses: [AyahNumber]) async throws -> [AyahNumber: UthmaniWordLayout] {
        async let counts = persistence.wordCounts(for: verses)
        async let tokenWords = persistence.uthmaniTokenWords(for: verses)
        let (wordCounts, regrouped) = try await (counts, tokenWords)
        return wordCounts.reduce(into: [:]) { layouts, entry in
            layouts[entry.key] = UthmaniWordLayout(wordCount: entry.value, tokenWords: regrouped[entry.key])
        }
    }

    // MARK: Private

    private let persistence: GRDBWordByWordPersistence
}

/// The glyphs a page image draws a word with, as page-image words (glyph positions).
public struct ImageWordGlyphs: Hashable, Sendable {
    public init(first: Word, last: Word) {
        self.first = first
        self.last = last
    }

    public let first: Word
    public let last: Word
}

private extension WordByWordLanguage {
    var column: WordTextColumn? {
        switch self {
        case .off: nil
        case .english: .english
        case .bengali: .bengali
        }
    }
}
