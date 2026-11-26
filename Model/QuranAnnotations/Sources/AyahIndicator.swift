//
//  AyahIndicator.swift
//

/// A mark next to an ayah number. Collections and notes exist in both builds; reading bookmarks
/// need Quran.com sync.
public enum AyahIndicator: Hashable, Sendable, Identifiable {
    #if QURAN_SYNC
    case readingBookmark(ReadingBookmarkSlot)
    #endif
    case collection
    case note

    public var id: AyahIndicator {
        return self
    }
}
