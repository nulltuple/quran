//
//  BookmarkCollectionsViewController.swift
//

import Combine
import Localization
import NoorUI
import SwiftUI
import UIx

final class BookmarkCollectionsViewController: UIHostingController<BookmarkCollectionsView> {
    init(viewModel: BookmarkCollectionsViewModel) {
        self.viewModel = viewModel
        super.init(rootView: BookmarkCollectionsView(viewModel: viewModel))
        title = lAndroid("menu_bookmarks")
        configureEditButton()
        #if !QURAN_SYNC
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateLeftButton() }
            .store(in: &cancellables)
        updateLeftButton()
        #endif
    }

    @available(*, unavailable)
    @MainActor
    dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var currentEditMode: EditMode? {
        viewModel.hasDeletableItems ? viewModel.editMode : nil
    }

    private let viewModel: BookmarkCollectionsViewModel
    private var editController: NavigationEditModeController?
    private var cancellables: Set<AnyCancellable> = []

    private func configureEditButton() {
        let addButton = NavigationBarButton.add(accessibilityLabel: l("bookmarks.collections.add")) { [weak self] in
            self?.viewModel.presentAddCollection()
        }

        editController = NavigationEditModeController(
            navigationItem: navigationItem,
            reload: viewModel.objectWillChange.eraseToAnyPublisher(),
            editMode: Binding(
                get: { [weak self] in self?.currentEditMode },
                set: { [weak self] value in self?.viewModel.editMode = value ?? .inactive }
            ),
            customItems: [addButton]
        )
    }

    #if !QURAN_SYNC
    /// Delete All for page bookmarks while editing, as the no-sync list had; otherwise the iCloud backup note.
    private func updateLeftButton() {
        if viewModel.editMode.isEditing, !viewModel.pageBookmarks.bookmarks.isEmpty {
            navigationItem.leftBarButtonItem = NavigationBarButton.deleteAll { [weak self] in
                self?.confirmDeleteAllPageBookmarks($0)
            }
        } else {
            addCloudSyncInfo()
        }
    }

    private func confirmDeleteAllPageBookmarks(_ sourceBarButtonItem: UIBarButtonItem) {
        let alert = DeleteAllConfirmation.make(
            message: l("bookmarks.pages.delete-all.confirmation"),
            sourceBarButtonItem: sourceBarButtonItem
        ) { [weak self] in
            Task { await self?.viewModel.pageBookmarks.deleteAll() }
        }
        present(alert, animated: true)
    }
    #endif
}
