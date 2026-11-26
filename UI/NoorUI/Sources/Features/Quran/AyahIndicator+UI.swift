import Localization
import QuranAnnotations

extension Set<AyahIndicator> {
    var ordered: [AyahIndicator] {
        var result: [AyahIndicator] = []
        #if QURAN_SYNC
        for slot in ReadingBookmarkSlot.allCases {
            result += filter {
                if case .readingBookmark(let bookmark) = $0 {
                    return bookmark == slot
                }
                return false
            }
        }
        #endif
        result += [.collection, .note]
        return result.filter(contains)
    }
}

extension AyahIndicator {
    var accessibilityLabel: String {
        switch self {
        #if QURAN_SYNC
        case .readingBookmark(let bookmark):
            lFormat("ayah.indicator.reading-bookmark", l("ayah.menu.reading-bookmark.title"), bookmark.displayName)
        #endif
        case .collection:
            l("bookmarks.collections")
        case .note:
            l("tab.notes")
        }
    }
}

#if QURAN_SYNC
extension [ReadingBookmarkSlot] {
    /// `name` followed by each slot's reading bookmark label, as one accessibility label.
    func accessibilityLabel(prefixedBy name: String) -> String {
        ([name] + map { AyahIndicator.readingBookmark($0).accessibilityLabel })
            .joined(separator: l("list.separator"))
    }
}
#endif
