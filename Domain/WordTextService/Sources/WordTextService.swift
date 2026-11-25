//
//  WordTextService.swift
//
//
//  Created by Mohamed Afifi on 2021-12-17.
//

import Foundation
import QuranKit
import QuranText

/// The text the word pointer shows for a page-image word: its meaning or its transliteration,
/// from the same word-by-word data the reader's meanings use.
public struct WordTextService: Sendable {
    // MARK: Lifecycle

    public init(fileURL: URL) {
        service = WordByWordService(fileURL: fileURL)
    }

    // MARK: Public

    /// The text for the page-image word (glyph) `glyph` of `reading`; `nil` for a mark glyph, or
    /// for a reading without a verified word mapping.
    public func textForWord(_ glyph: Word, reading: Reading) async throws -> String? {
        guard let word = try await service.word(atImageGlyph: glyph, reading: reading) else {
            return nil
        }
        return try await service.text(for: word, type: preferences.wordTextType, language: Self.pointerLanguage)
    }

    // MARK: Internal

    /// The pointer shows meanings in the reader's word-by-word language, and in English (its only
    /// language before Bengali existed) while word-by-word meanings are off.
    static var pointerLanguage: WordByWordLanguage {
        switch WordByWordPreferences.shared.language {
        case .bengali: .bengali
        case .english, .off: .english
        }
    }

    // MARK: Private

    private let preferences = WordTextPreferences.shared
    private let service: WordByWordService
}
