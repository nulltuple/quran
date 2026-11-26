//
//  AyahMenuUI.swift
//
//
//  Created by Afifi, Mohamed on 7/25/21.
//

import QuranAnnotations
import UIx

public enum AyahMenuUI {
    public struct Actions {
        // MARK: Lifecycle

        #if QURAN_SYNC
        public init(
            play: @escaping AsyncAction,
            repeatVerses: @escaping AsyncAction,
            bookmark: @escaping AsyncAction,
            addNote: @escaping AsyncAction,
            deleteNote: @escaping AsyncAction,
            showTranslation: @escaping AsyncAction,
            copy: @escaping AsyncAction,
            share: @escaping AsyncAction,
            showReadingBookmarkMenu: @escaping AsyncAction
        ) {
            self.play = play
            self.repeatVerses = repeatVerses
            self.bookmark = bookmark
            self.addNote = addNote
            self.deleteNote = deleteNote
            self.showTranslation = showTranslation
            self.copy = copy
            self.share = share
            self.showReadingBookmarkMenu = showReadingBookmarkMenu
        }
        #else
        public init(
            play: @escaping AsyncAction,
            repeatVerses: @escaping AsyncAction,
            bookmark: @escaping AsyncAction,
            highlight: @Sendable @escaping (HighlightColor) async -> Void,
            addNote: @escaping AsyncAction,
            deleteNote: @escaping AsyncAction,
            showTranslation: @escaping AsyncAction,
            copy: @escaping AsyncAction,
            share: @escaping AsyncAction
        ) {
            self.play = play
            self.repeatVerses = repeatVerses
            self.bookmark = bookmark
            self.highlight = highlight
            self.addNote = addNote
            self.deleteNote = deleteNote
            self.showTranslation = showTranslation
            self.copy = copy
            self.share = share
        }
        #endif

        // MARK: Internal

        let play: AsyncAction
        let repeatVerses: AsyncAction
        let bookmark: AsyncAction
        #if !QURAN_SYNC
        let highlight: @Sendable (HighlightColor) async -> Void
        #endif
        let addNote: AsyncAction
        let deleteNote: AsyncAction
        let showTranslation: AsyncAction
        let copy: AsyncAction
        let share: AsyncAction
        #if QURAN_SYNC
        let showReadingBookmarkMenu: AsyncAction
        #endif
    }

    public struct DataObject {
        // MARK: Lifecycle

        #if QURAN_SYNC
        public init(
            highlightingColor: HighlightColor,
            state: NoteState,
            bookmarkTitle: String,
            notesTitle: String,
            bookmarkState: BookmarkState = .unhighlighted,
            playSubtitle: String,
            repeatSubtitle: String,
            actions: Actions,
            isTranslationView: Bool,
            usesSyncedNotesIcon: Bool = false,
            readingBookmarkState: ReadingBookmarkState
        ) {
            self.highlightingColor = highlightingColor
            self.state = state
            self.bookmarkTitle = bookmarkTitle
            self.notesTitle = notesTitle
            self.bookmarkState = bookmarkState
            self.playSubtitle = playSubtitle
            self.repeatSubtitle = repeatSubtitle
            self.actions = actions
            self.isTranslationView = isTranslationView
            self.usesSyncedNotesIcon = usesSyncedNotesIcon
            self.readingBookmarkState = readingBookmarkState
        }
        #else
        public init(
            highlightingColor: HighlightColor,
            state: NoteState,
            bookmarkTitle: String,
            bookmarkState: BookmarkState = .unhighlighted,
            playSubtitle: String,
            repeatSubtitle: String,
            actions: Actions,
            isTranslationView: Bool,
            usesSyncedNotesIcon: Bool = false
        ) {
            self.highlightingColor = highlightingColor
            self.state = state
            self.bookmarkTitle = bookmarkTitle
            self.bookmarkState = bookmarkState
            self.playSubtitle = playSubtitle
            self.repeatSubtitle = repeatSubtitle
            self.actions = actions
            self.isTranslationView = isTranslationView
            self.usesSyncedNotesIcon = usesSyncedNotesIcon
        }
        #endif

        // MARK: Internal

        let highlightingColor: HighlightColor
        let state: NoteState
        let actions: Actions
        let bookmarkTitle: String
        let bookmarkState: BookmarkState
        #if QURAN_SYNC
        let notesTitle: String
        let readingBookmarkState: ReadingBookmarkState
        #endif
        let playSubtitle: String
        let repeatSubtitle: String
        let isTranslationView: Bool
        let usesSyncedNotesIcon: Bool
    }

    // MARK: Public

    public enum NoteState {
        case noHighlight
        case highlighted
        case noted
    }

    /// Without sync, only `unhighlighted` and `bookmarked` occur: highlights stay with notes.
    public enum BookmarkState: Equatable {
        case unhighlighted
        case bookmarked
        case partiallyHighlighted
        case highlighted(HighlightColor)
    }

    #if QURAN_SYNC

    public enum ReadingBookmarkState: Equatable {
        case disabled(message: String)
        case available(bookmark: PlacedReadingBookmark?, subtitle: String, showsNewBadge: Bool)
    }
    #endif
}
