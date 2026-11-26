//
//  TafsirPreferences.swift
//

import Preferences
import QuranText

/// The tafsir the tafsir sheet shows, kept apart from the translations the reader shows.
public final class TafsirPreferences {
    // MARK: Lifecycle

    private init() {}

    // MARK: Public

    public static let shared = TafsirPreferences()

    @Preference(selectedTafsir)
    public var selectedTafsirId: Translation.ID?

    /// The selected tafsir among `tafsirs`, or the first one when none is selected or the selected one is gone.
    public func selectedTafsir(from tafsirs: [Translation]) -> Translation? {
        tafsirs.first { $0.id == selectedTafsirId } ?? tafsirs.first
    }

    // MARK: Internal

    func reset() {
        Preferences.shared.removeValueForKey(Self.selectedTafsir)
    }

    // MARK: Private

    private static let selectedTafsir = PreferenceKey<Translation.ID?>(key: "tafsir.selected", defaultValue: nil)
}
