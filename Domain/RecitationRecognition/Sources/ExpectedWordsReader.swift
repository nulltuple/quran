//
//  ExpectedWordsReader.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import QuranKit
import VerseTextPersistence
import WordTextService

/// Reads the canonical words of verses with their Uthmani text, for `WordAligner`.
///
/// The bundled Uthmani text (`arabic_text`) writes one token per canonical word in all but six
/// ayahs; `WordByWordService.textLayouts` maps those six (15:7, 27:20, 36:22, 37:130, 37:164, 41:47),
/// as the translation view's word-by-word line does. Words are numbered as `word_by_word.db`
/// numbers them, the numbering the word study, word pointer and recitation highlight use.
public struct ExpectedWordsReader: Sendable {
    // MARK: Lifecycle

    /// `uthmaniText`: the bundled `quran.ar.uthmani.v2.db` in `.arabic` mode.
    public init(uthmaniText: GRDBQuranVerseTextPersistence, wordByWord: WordByWordService) {
        self.uthmaniText = uthmaniText
        self.wordByWord = wordByWord
    }

    // MARK: Public

    /// The expected words of `verses`, in Quran order.
    public func expectedWords(for verses: [AyahNumber]) async throws -> [ExpectedWordText] {
        let verses = verses.sorted()
        async let texts = uthmaniText.textForVerses(verses)
        async let layouts = wordByWord.textLayouts(for: verses)
        let (verseTexts, verseLayouts) = try await (texts, layouts)
        return try verses.flatMap { verse -> [ExpectedWordText] in
            guard let text = verseTexts[verse]?.text else {
                throw ExpectedWordsError.noText(verse)
            }
            let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let units = verseLayouts[verse]?.units(tokenCount: tokens.count) else {
                throw ExpectedWordsError.noWordLayout(verse)
            }
            return units.map { unit in
                ExpectedWordText(
                    words: unit.words.map { Word(verse: verse, wordNumber: $0) },
                    text: tokens[unit.tokens.lowerBound - 1 ... unit.tokens.upperBound - 1].joined(separator: " ")
                )
            }
        }
    }

    // MARK: Private

    private let uthmaniText: GRDBQuranVerseTextPersistence
    private let wordByWord: WordByWordService
}

public enum ExpectedWordsError: Error, Equatable {
    /// The Uthmani text has no row for the verse.
    case noText(AyahNumber)
    /// The word database has no words for the verse, or they don't line up with its tokens.
    case noWordLayout(AyahNumber)
}
