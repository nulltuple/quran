//
//  BookmarkCollectionsView.swift
//

import AnnotationsService
import FeaturesSupport
import Localization
import NoorUI
import QuranAnnotations
import SwiftUI
import UIx

@MainActor
struct BookmarkCollectionsView: View {
    @StateObject var viewModel: BookmarkCollectionsViewModel

    init(viewModel: BookmarkCollectionsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        BookmarkCollectionsContent(viewModel: viewModel)
            .enableToastPresenter()
    }
}

@MainActor
private struct BookmarkCollectionsContent: View {
    @ObservedObject var viewModel: BookmarkCollectionsViewModel

    @Environment(\.showToast) private var showToast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NoorList {
            #if QURAN_SYNC
            if viewModel.showsOldPageBookmarksTip {
                Section {
                    oldPageBookmarksTip
                        .tipCardListRow()
                }
            }

            ContinueReadingSection(
                title: l("bookmarks.reading.title"),
                readingBookmarks: viewModel.readingBookmarks,
                lastPages: [],
                selectReadingBookmark: { viewModel.navigateTo($0) },
                selectLastPage: { _ in },
                deleteReadingBookmark: { bookmark in
                    { await deleteReadingBookmark(bookmark) }
                },
                renameReadingBookmark: { viewModel.presentRenameReadingBookmark($0) }
            )

            NoorBasicSection(title: l("bookmarks.highlights")) {
                HighlightColorsView(
                    items: highlightColors,
                    selectColor: { viewModel.showHighlights($0) },
                    removeAll: { viewModel.requestRemoveAllHighlights($0) }
                )
            }

            collectionsSection
            #else
            collectionsSection

            PageBookmarksSection(viewModel: viewModel.pageBookmarks)
            #endif
        }
        #if QURAN_SYNC
        .animation(reduceMotion ? nil : NoorAnimation.standard, value: viewModel.showsOldPageBookmarksTip)
            .refreshable(isEnabled: viewModel.canRefresh) { await viewModel.refresh() }
        #endif
            .task { await viewModel.start() }
            .collectionNameAlert(
                l("bookmarks.collections.add"),
                state: $viewModel.nameAlert,
                name: $viewModel.newCollectionName,
                submit: { await createPendingCollection() }
            )
        #if QURAN_SYNC
            .readingBookmarkNameAlert(
                slot: $viewModel.renamingReadingBookmark,
                name: $viewModel.readingBookmarkName,
                submit: { await viewModel.renameReadingBookmark(in: $0) }
            )
        #endif
            .collectionNameAlert(
                l("bookmarks.collections.rename"),
                state: $viewModel.renameAlert,
                name: $viewModel.renamedCollectionName,
                submit: { await viewModel.renamePendingCollection() }
            )
            .collectionDeleteConfirmation(
                item: $viewModel.collectionPendingDeletion,
                delete: { await viewModel.deleteCollection($0) }
            )
            .destructiveConfirmation(
                l("bookmarks.delete-all"),
                actionTitle: l("bookmarks.delete-all"),
                item: $viewModel.collectionPendingRemoveAll,
                message: { DeleteAllConfirmation.message(collectionName: $0.displayName) },
                action: { await viewModel.removeAllAyahs(from: $0) }
            )
        #if QURAN_SYNC
            .destructiveConfirmation(
                l("bookmarks.delete-all"),
                actionTitle: l("bookmarks.delete-all"),
                item: $viewModel.highlightColorPendingRemoveAll,
                message: { DeleteAllConfirmation.message(highlightColor: $0) },
                action: { await viewModel.removeAllHighlights($0) }
            )
        #endif
            .errorAlert(error: $viewModel.error)
            .environment(\.editMode, $viewModel.editMode)
    }

    #if QURAN_SYNC
    /// The release whose page bookmarks became Old Page Bookmarks.
    private var pageBookmarksVersion: String {
        [3, 0].map { NumberFormatter.shared.format($0) }.joined(separator: ".")
    }

    private var oldPageBookmarksTip: some View {
        TipCard(
            title: l("bookmarks.old-page-bookmarks-tip.title"),
            text: lFormat("bookmarks.old-page-bookmarks-tip.text", pageBookmarksVersion),
            image: .book,
            action: TipCard.Action(l("bookmarks.old-page-bookmarks.open")) { viewModel.openOldPageBookmarks() },
            dismiss: { viewModel.dismissOldPageBookmarksTip() }
        )
    }
    #endif

    private var collectionsSection: some View {
        NoorBasicSection(title: l("bookmarks.collections.mine")) {
            if viewModel.displayedCollections.isEmpty {
                NoorListEmptyState(
                    title: l("bookmarks.collections.no-data.title"),
                    text: l("bookmarks.collections.no-data.text"),
                    image: .star
                )
            }

            NoorListRows(
                viewModel.displayedCollections,
                canDelete: { $0.canDelete },
                onDelete: { collection in
                    { await viewModel.requestDeleteCollection(collection) }
                }
            ) { collection in
                collectionRow(
                    title: collection.displayName,
                    image: collection.displayImage,
                    imageColor: collection.displayImageColor,
                    count: collection.bookmarks.count,
                    action: { viewModel.showCollection(collection) }
                )
                .noorItemContextMenu(
                    isEnabled: viewModel.isItemMenuEnabled,
                    open: { viewModel.showCollection(collection) },
                    rename: renameAction(for: collection),
                    deleteAll: removeAllAction(for: collection)
                )
            }

            NoorListItem(
                image: .init(.plusCircle, color: .accentColor),
                title: .text(l("bookmarks.collections.new")),
                titleColor: .accentColor,
                action: .sync { viewModel.presentAddCollection() }
            )
            .deleteDisabled(true)
        }
    }

    #if QURAN_SYNC
    private var highlightColors: [HighlightColorsView.Item] {
        HighlightColor.sortedByUsage(in: viewModel.highlights.values).map { color in
            HighlightColorsView.Item(
                color: color,
                count: viewModel.highlights.values.count { $0 == color },
                canRemoveAll: viewModel.canRemoveAllHighlights(color)
            )
        }
    }
    #endif

    private func renameAction(for collection: AyahBookmarkCollection) -> (@MainActor () -> Void)? {
        guard collection.canRename else {
            return nil
        }
        return { viewModel.presentRenameCollection(collection) }
    }

    private func removeAllAction(for collection: AyahBookmarkCollection) -> (@MainActor () -> Void)? {
        guard viewModel.canRemoveAllAyahs(from: collection) else {
            return nil
        }
        return { viewModel.requestRemoveAllAyahs(from: collection) }
    }

    private func createPendingCollection() async {
        if let toast = await viewModel.createPendingCollection() {
            showToast?(toast)
        }
    }

    #if QURAN_SYNC
    private func deleteReadingBookmark(_ bookmark: PlacedReadingBookmark) async {
        if let toast = await viewModel.deleteReadingBookmark(bookmark) {
            showToast?(toast)
        }
    }
    #endif

    private func collectionRow(
        title: String,
        image: NoorSystemImage,
        imageColor: Color,
        count: Int,
        action: @escaping Action
    ) -> some View {
        NoorListItem(
            image: .init(image, color: imageColor),
            title: .text(title),
            subtitle: .init(
                text: .text(NumberFormatter.shared.format(count)),
                location: .trailing
            ),
            accessory: .disclosureIndicator,
            action: .sync { action() }
        )
    }
}
