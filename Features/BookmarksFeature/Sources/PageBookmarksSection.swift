//
//  PageBookmarksSection.swift
//
//
//  Created by Mohamed Afifi on 2023-07-13.
//

#if !QURAN_SYNC
import Localization
import NoorUI
import QuranAnnotations
import QuranKit
import SwiftUI
import UIx

/// One page bookmark: its suras, when it was added, and its page number.
@MainActor
private struct PageBookmarkRow: View {
    let bookmark: PageBookmark
    let select: ItemAction<PageBookmark>

    var body: some View {
        NoorListItem(
            image: .init(.bookmark, color: .red),
            title: "\(suras: bookmark.page.suras)",
            subtitle: .init(text: .text(bookmark.creationDate.timeAgo()), location: .bottom),
            accessory: .text(bookmark.page.localizedNumber, accessibilityLabel: bookmark.page.localizedName),
            action: .sync { select(bookmark) }
        )
    }
}

/// The page bookmarks under the collections in the no-sync Bookmarks tab.
@MainActor
struct PageBookmarksSection: View {
    @ObservedObject var viewModel: BookmarksViewModel

    var body: some View {
        if !viewModel.bookmarks.isEmpty {
            NoorBasicSection(title: l("bookmarks.pages")) {
                NoorListRows(viewModel.bookmarks, onDelete: { viewModel.deleteItem($0) }) { bookmark in
                    PageBookmarkRow(bookmark: bookmark, select: { viewModel.navigateTo($0) })
                }
            }
        }
    }
}
#endif
