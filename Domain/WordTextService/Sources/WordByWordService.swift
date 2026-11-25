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

/// Word-by-word meanings and page-image word positions, with words numbered as in the ayah's
/// text (QUL word numbers), the numbering recited words use.
public struct WordByWordService: Sendable {
    // MARK: Lifecycle

    public init(fileURL: URL) {
        persistence = GRDBWordByWordPersistence(fileURL: fileURL)
    }

    // MARK: Public

    /// The meaning of each word in `verses` in `language`; empty when `language` is `.off`.
    public func meanings(for verses: [AyahNumber], language: WordByWordLanguage) async throws -> [Word: String] {
        let column: WordMeaningLanguage
        switch language {
        case .off: return [:]
        case .english: column = .english
        case .bengali: column = .bengali
        }
        return try await persistence.meanings(for: verses, language: column)
    }

    /// The number of words in each of `verses`, as recited words number them.
    public func wordCounts(for verses: [AyahNumber]) async throws -> [AyahNumber: Int] {
        try await persistence.wordCounts(for: verses)
    }

    /// The page-image word (glyph position) of each word in `verses`, for readings whose images
    /// have a word mapping; empty for other readings, which then highlight whole ayahs only.
    public func imageWords(for verses: [AyahNumber], reading: Reading) async throws -> [Word: Word] {
        guard reading == .hafs_1405 else {
            return [:]
        }
        let positions = try await persistence.hafs1405GlyphPositions(for: verses)
        var words: [Word: Word] = [:]
        for (word, position) in positions {
            words[word] = Word(verse: word.verse, wordNumber: position)
        }
        return words
    }

    // MARK: Private

    private let persistence: GRDBWordByWordPersistence
}
