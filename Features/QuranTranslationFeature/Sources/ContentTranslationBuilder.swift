//
//  ContentTranslationBuilder.swift
//  Quran
//
//  Created by Afifi, Mohamed on 11/30/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import AnnotationsService
import AppDependencies
import QuranKit
import QuranPagesFeature
import QuranTextKit
import SwiftUI
import TranslationService
import WordTextService

public struct ContentTranslationBuilder {
    private let container: AppDependencies
    private let overlayService: VerseOverlayService

    public init(container: AppDependencies, overlayService: VerseOverlayService) {
        self.container = container
        self.overlayService = overlayService
    }

    /// `onWordTapped` opens word study for a word tapped in the word-by-word Arabic text.
    #if QURAN_SYNC
    @MainActor
    public func build(
        at page: Page,
        onWordTapped: @escaping (Word) -> Void,
        onAyahNumberTapped: @escaping (AyahNumber, CGPoint) -> Void
    ) -> some View {
        ContentTranslationView(viewModel: makeViewModel(at: page, onWordTapped: onWordTapped), onAyahNumberTapped: onAyahNumberTapped)
    }
    #else
    @MainActor
    public func build(at page: Page, onWordTapped: @escaping (Word) -> Void) -> some View {
        ContentTranslationView(viewModel: makeViewModel(at: page, onWordTapped: onWordTapped))
    }
    #endif

    @MainActor
    private func makeViewModel(at page: Page, onWordTapped: @escaping (Word) -> Void) -> ContentTranslationViewModel {
        let dataService = QuranTextDataService(
            databasesURL: container.databasesURL,
            quranFileURL: container.quranUthmaniV2Database
        )

        let localTranslationsRetriever = LocalTranslationsRetriever(databasesURL: container.databasesURL)
        let viewModel = ContentTranslationViewModel(
            localTranslationsRetriever: localTranslationsRetriever,
            dataService: dataService,
            overlayService: overlayService,
            wordByWordService: WordByWordService(fileURL: container.wordByWordDatabase)
        )
        viewModel.verses = page.verses
        viewModel.onWordTapped = onWordTapped
        return viewModel
    }
}
