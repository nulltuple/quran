//
//  AyahMenuViewController.swift
//  Quran
//
//  Created by Afifi, Mohamed on 4/11/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import NoorUI
import UIKit
import UIx

final class AyahMenuViewController: UIViewController {
    // MARK: Lifecycle

    init(viewModel: AyahMenuViewModel, compareSimilarVerses: AsyncAction? = nil) {
        self.viewModel = viewModel
        self.compareSimilarVerses = compareSimilarVerses
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public

    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        preferredContentSize = container.preferredContentSize
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()

        #if QURAN_SYNC
        let actions = AyahMenuUI.Actions(
            play: { [weak self] in self?.viewModel.play() },
            repeatVerses: { [weak self] in self?.viewModel.repeatVerses() },
            bookmark: { [weak self] in self?.viewModel.bookmark() },
            addNote: { [weak self] in await self?.viewModel.editNote() },
            deleteNote: { [weak self] in await self?.viewModel.deleteNotes() },
            showTranslation: { [weak self] in self?.viewModel.showTranslation() },
            showTafsir: { [weak self] in self?.viewModel.showTafsir() },
            copy: { [weak self] in await self?.viewModel.copy() },
            share: { [weak self] in await self?.viewModel.share() },
            showReadingBookmarkMenu: { [weak self] in self?.viewModel.showReadingBookmarkMenu() },
            reciteToCheck: { [weak self] in self?.viewModel.reciteToCheck() },
            practice: { [weak self] in self?.viewModel.practice() },
            compareSimilarVerses: compareSimilarVerses
        )
        #else
        let actions = AyahMenuUI.Actions(
            play: { [weak self] in self?.viewModel.play() },
            repeatVerses: { [weak self] in self?.viewModel.repeatVerses() },
            bookmark: { [weak self] in self?.viewModel.bookmark() },
            highlight: { [weak self] color in await self?.viewModel.updateHighlight(color: color) },
            addNote: { [weak self] in await self?.viewModel.editNote() },
            deleteNote: { [weak self] in await self?.viewModel.deleteNotes() },
            showTranslation: { [weak self] in self?.viewModel.showTranslation() },
            showTafsir: { [weak self] in self?.viewModel.showTafsir() },
            copy: { [weak self] in await self?.viewModel.copy() },
            share: { [weak self] in await self?.viewModel.share() },
            reciteToCheck: { [weak self] in self?.viewModel.reciteToCheck() },
            practice: { [weak self] in self?.viewModel.practice() },
            compareSimilarVerses: compareSimilarVerses
        )
        #endif
        let highlightingColor = viewModel.highlightingColor
        #if QURAN_SYNC
        let dataObject = AyahMenuUI.DataObject(
            highlightingColor: highlightingColor,
            state: viewModel.noteState,
            bookmarkTitle: viewModel.bookmarkTitle,
            notesTitle: viewModel.notesTitle,
            bookmarkState: viewModel.bookmarkState,
            playSubtitle: viewModel.playSubtitle,
            repeatSubtitle: viewModel.repeatSubtitle,
            actions: actions,
            isTranslationView: viewModel.isTranslationView,
            usesSyncedNotesIcon: viewModel.usesSyncedNotesIcon,
            readingBookmarkState: viewModel.readingBookmarkState
        )
        #else
        let dataObject = AyahMenuUI.DataObject(
            highlightingColor: highlightingColor,
            state: viewModel.noteState,
            bookmarkTitle: viewModel.bookmarkTitle,
            bookmarkState: viewModel.bookmarkState,
            playSubtitle: viewModel.playSubtitle,
            repeatSubtitle: viewModel.repeatSubtitle,
            actions: actions,
            isTranslationView: viewModel.isTranslationView,
            usesSyncedNotesIcon: viewModel.usesSyncedNotesIcon
        )
        #endif
        showAyahMenu(dataObject)
    }

    // MARK: Private

    private let viewModel: AyahMenuViewModel
    private let compareSimilarVerses: AsyncAction?

    private func showAyahMenu(_ dataObject: AyahMenuUI.DataObject) {
        let view = AyahMenuView(dataObject: dataObject)
        let hostingController = AutoUpdatingPreferredContentSizeHostingController(rootView: view)
        addFullScreenChild(hostingController)
    }
}
