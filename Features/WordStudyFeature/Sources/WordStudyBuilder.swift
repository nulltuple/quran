//
//  WordStudyBuilder.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import AppDependencies
import Localization
import NoorUI
import QuranKit
import QuranText
import QuranTextKit
import ReadingService
import SwiftUI
import UIKit
import WordTextService

@MainActor
public struct WordStudyBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    /// The word study sheet for `word`, in a navigation controller.
    public func build(word: Word) -> UIViewController {
        let viewModel = WordStudyViewModel(
            word: word,
            service: WordStudyService(
                morphologyFileURL: container.quranMorphologyDatabase,
                wordByWordFileURL: container.wordByWordDatabase
            ),
            language: WordByWordPreferences.shared.language
        )
        let readingFont = ReadingPreferences.shared.reading.quranFont
        let view = WordStudyView(
            viewModel: viewModel,
            // The corpus text is Uthmani; the IndoPak font does not draw it.
            quranFont: readingFont == .indoPak ? .uthmanicHafs : readingFont,
            fontSize: FontSizePreferences.shared.arabicFontSize
        )
        let viewController = UIHostingController(rootView: view)
        viewController.title = l("word_study.title")
        return UINavigationController(rootViewController: viewController)
    }

    // MARK: Private

    private let container: AppDependencies
}
