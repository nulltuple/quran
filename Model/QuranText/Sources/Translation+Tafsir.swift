//
//  Translation+Tafsir.swift
//

import Foundation
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
        supplementaryTafsirIDBase + 169, // English Ibn Kathir (Abridged), supplementary
        supplementaryTafsirIDBase + 165, // Bengali Ahsanul Bayaan, supplementary
    ]

    /// Supplementary ids are this plus the tafsir's Quran.com API v4 resource id, far above the feed's
    /// ids (at most 122 on 2026-11-26), so the two never collide.
    public static let supplementaryTafsirIDBase: ID = 10000

    /// Tafsirs the feed lacks, listed after the feed's entries. Their packs are built by
    /// `Tools/build-tafsir-pack.py` from Quran.com API v4 and published on this repository's
    /// `tafsir-packs-1` GitHub release (2026-11-26); the zips' sha256 are in the C1 English/Bengali
    /// trail entry. Bump `version` together with the pack's `text_version` when a pack is rebuilt.
    public static let supplementaryTafsirs: [Translation] = [
        Translation(
            id: supplementaryTafsirIDBase + 169,
            displayName: "English Ibn Kathir Tafseer (Abridged)",
            translator: "Hafiz Ibn Kathir",
            translatorForeign: nil,
            fileURL: supplementaryPackURL("quran.en.ibnkathir.zip"),
            fileName: "quran.en.ibnkathir.db",
            languageCode: "en",
            version: 1
        ),
        Translation(
            id: supplementaryTafsirIDBase + 165,
            displayName: "Bengali Ahsanul Bayaan Tafseer",
            translator: "Bayaan Foundation",
            translatorForeign: "তাফসীরে আহসানুল বায়ান",
            fileURL: supplementaryPackURL("quran.bn.ahsanulbayaan.zip"),
            fileName: "quran.bn.ahsanulbayaan.db",
            languageCode: "bn",
            version: 1
        ),
    ]

    /// Whether this entry is a tafsir (commentary) rather than a translation.
    public var isTafsir: Bool {
        Self.tafsirIDs.contains(id)
    }
}

private func supplementaryPackURL(_ fileName: String) -> URL {
    URL(string: "https://github.com/nulltuple/quran/releases/download/tafsir-packs-1/\(fileName)")!
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
