//
//  WordByWordPreferences.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import Preferences
import QuranText

public struct WordByWordPreferences {
    // MARK: Lifecycle

    private init() {}

    // MARK: Public

    public static let shared = WordByWordPreferences()

    /// The language of the meaning shown under each word; off until the reader picks one.
    @TransformedPreference(language, transformer: .rawRepresentable(defaultValue: .off))
    public var language: WordByWordLanguage

    /// Whether each word's transliteration shows between it and its meaning in the translation
    /// view; off until the reader turns it on.
    @Preference(showsTransliteration)
    public var showsTransliteration: Bool

    // MARK: Private

    private static let language = PreferenceKey<Int>(key: "wordByWordLanguage", defaultValue: WordByWordLanguage.off.rawValue)
    private static let showsTransliteration = PreferenceKey<Bool>(key: "wordByWordTransliteration", defaultValue: false)
}
