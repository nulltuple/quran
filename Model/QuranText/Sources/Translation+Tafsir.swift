//
//  Translation+Tafsir.swift
//

import QuranKit

extension Translation {
    /// The Quran.app translations feed (`/data/translations.php?v=5`) lists tafsirs as ordinary
    /// translations, with no type field; these are its tafsir ids, read from the feed on 2026-11-26.
    public static let tafsirIDs: Set<ID> = [
        58, // Ibn Kathir
        59, // Sa'di
        60, // Baghawi
        61, // Qurtubi
        62, // Tabari
        63, // Tanweer (Ibn Ashur)
        64, // Muyassar
        92, // Jalalayn
        95, // Waseet
        99, // I'rab (Tafsir Center)
        113, // Mukhtasar
    ]

    /// Whether this entry is a tafsir (commentary) rather than a translation.
    public var isTafsir: Bool {
        Self.tafsirIDs.contains(id)
    }
}

/// A tafsir's explanation of one ayah. Tafsirs often explain a passage of several ayahs once:
/// `verses` lists every ayah the text explains, in order, and always contains the requested ayah.
public struct TafsirText: Equatable {
    // MARK: Lifecycle

    public init(verses: [AyahNumber], text: TranslationString?) {
        self.verses = verses
        self.text = text
    }

    // MARK: Public

    public let verses: [AyahNumber]
    /// Nil when the tafsir has no text for these ayahs.
    public let text: TranslationString?

    public var firstVerse: AyahNumber { verses[0] }
    public var lastVerse: AyahNumber { verses[verses.count - 1] }
    public var coversSeveralVerses: Bool { verses.count > 1 }
}
