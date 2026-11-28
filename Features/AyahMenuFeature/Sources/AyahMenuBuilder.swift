//
//  AyahMenuBuilder.swift
//  Quran
//
//  Created by Afifi, Mohamed on 4/11/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import AnnotationsService
import AppDependencies
import QuranAnnotations
import QuranKit
import QuranTextKit
import UIKit
import UIx

public struct AyahMenuInput {
    // MARK: Lifecycle

    #if QURAN_SYNC
    public init(
        sourceView: UIView,
        pointInView: CGPoint,
        verses: [AyahNumber],
        notes: [QuranAnnotations.Note],
        highlightVerses: [AyahNumber: HighlightColor] = [:],
        bookmarkedVerses: Set<AyahNumber> = [],
        readingBookmark: PlacedReadingBookmark? = nil,
        placedReadingBookmarks: [PlacedReadingBookmark]?
    ) {
        self.sourceView = sourceView
        self.pointInView = pointInView
        self.verses = verses
        self.notes = notes
        self.highlightVerses = highlightVerses
        self.bookmarkedVerses = bookmarkedVerses
        self.readingBookmark = readingBookmark
        self.placedReadingBookmarks = placedReadingBookmarks
    }
    #else
    public init(
        sourceView: UIView,
        pointInView: CGPoint,
        verses: [AyahNumber],
        notes: [QuranAnnotations.Note],
        bookmarkedVerses: Set<AyahNumber> = []
    ) {
        self.sourceView = sourceView
        self.pointInView = pointInView
        self.verses = verses
        self.notes = notes
        self.bookmarkedVerses = bookmarkedVerses
    }
    #endif

    // MARK: Internal

    let sourceView: UIView
    let pointInView: CGPoint
    let verses: [AyahNumber]
    let notes: [QuranAnnotations.Note]
    let bookmarkedVerses: Set<AyahNumber>
    #if QURAN_SYNC
    let highlightVerses: [AyahNumber: HighlightColor]
    let readingBookmark: PlacedReadingBookmark?
    /// Every placed reading bookmark, in any slot, or nil while they're still loading.
    let placedReadingBookmarks: [PlacedReadingBookmark]?
    #endif
}

@MainActor
public struct AyahMenuBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build(
        withListener listener: AyahMenuListener,
        input: AyahMenuInput,
        compareSimilarVerses: (@MainActor @Sendable (AyahNumber) -> Void)? = nil
    ) -> UIViewController {
        let textRetriever = ShareableVerseTextRetriever(
            databasesURL: container.databasesURL,
            quranFileURL: container.quranUthmaniV2Database
        )
        #if QURAN_SYNC
        let deps = AyahMenuViewModel.Deps(
            sourceView: input.sourceView,
            pointInView: input.pointInView,
            verses: input.verses,
            textRetriever: textRetriever,
            notes: input.notes,
            highlightVerses: input.highlightVerses,
            bookmarkedVerses: input.bookmarkedVerses,
            readingBookmark: input.readingBookmark,
            placedReadingBookmarks: input.placedReadingBookmarks
        )
        #else
        let deps = AyahMenuViewModel.Deps(
            sourceView: input.sourceView,
            pointInView: input.pointInView,
            verses: input.verses,
            textRetriever: textRetriever,
            notes: input.notes,
            bookmarkedVerses: input.bookmarkedVerses,
            noteService: container.noteService()
        )
        #endif
        let viewModel = AyahMenuViewModel(deps: deps)
        viewModel.listener = listener
        let compare: AsyncAction? = if let compareSimilarVerses, input.verses.count == 1, let verse = input.verses.first {
            { compareSimilarVerses(verse) }
        } else {
            nil
        }
        return AyahMenuViewController(viewModel: viewModel, compareSimilarVerses: compare)
    }

    // MARK: Private

    private let container: AppDependencies
}
