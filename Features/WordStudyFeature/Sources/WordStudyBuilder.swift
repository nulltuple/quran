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

    /// The word study sheet for `word`, in a navigation controller. `readerFollower` keeps the
    /// reader on the ayah of the word being studied; call its `returnToOrigin()` when the sheet
    /// is dismissed.
    public func build(word: Word, readerFollower: WordStudyReaderFollower) -> UIViewController {
        let navigator = WordStudyNavigator(
            service: WordStudyService(
                morphologyFileURL: container.quranMorphologyDatabase,
                wordByWordFileURL: container.wordByWordDatabase
            ),
            language: WordByWordPreferences.shared.language,
            // The corpus text is Uthmani; the IndoPak font does not draw it.
            quranFont: ReadingPreferences.shared.reading.quranFont == .indoPak
                ? .uthmanicHafs : ReadingPreferences.shared.reading.quranFont,
            fontSize: FontSizePreferences.shared.arabicFontSize,
            readerFollower: readerFollower
        )
        let navigationController = UINavigationController(rootViewController: navigator.study(of: word))
        navigator.navigationController = navigationController
        return navigationController
    }

    // MARK: Private

    private let container: AppDependencies
}

/// Pushes occurrence lists and the studies of their words inside the sheet.
@MainActor
private final class WordStudyNavigator {
    // MARK: Lifecycle

    init(
        service: WordStudyService,
        language: WordByWordLanguage,
        quranFont: QuranFont,
        fontSize: FontSize,
        readerFollower: WordStudyReaderFollower
    ) {
        self.service = service
        self.language = language
        self.quranFont = quranFont
        self.fontSize = fontSize
        self.readerFollower = readerFollower
    }

    // MARK: Internal

    weak var navigationController: UINavigationController?

    func study(of word: Word) -> UIViewController {
        let viewModel = WordStudyViewModel(
            word: word,
            service: service,
            language: language,
            // Strong: the sheet's views keep the navigator; it keeps the navigation controller weakly.
            showOccurrences: { [self] in showOccurrences(of: $0) },
            showVerse: { [readerFollower] in readerFollower.show($0) }
        )
        let viewController = UIHostingController(rootView: WordStudyView(
            viewModel: viewModel,
            quranFont: quranFont,
            fontSize: fontSize
        ))
        viewController.title = l("word_study.title")
        return viewController
    }

    // MARK: Private

    private let service: WordStudyService
    private let language: WordByWordLanguage
    private let quranFont: QuranFont
    private let fontSize: FontSize
    private let readerFollower: WordStudyReaderFollower

    private func showOccurrences(of term: WordStudyTerm) {
        let viewModel = WordOccurrencesViewModel(
            term: term,
            quran: readerFollower.origin.quran,
            service: service,
            language: language,
            selectWord: { [self] in showStudy(of: $0) }
        )
        let viewController = UIHostingController(rootView: WordOccurrencesView(
            viewModel: viewModel,
            arabic: term.arabic,
            quranFont: quranFont,
            fontSize: fontSize
        ))
        viewController.title = term.title
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func showStudy(of word: Word) {
        navigationController?.pushViewController(study(of: word), animated: true)
        // Leave room to see the ayah the reader jumps to.
        if let sheet = navigationController?.sheetPresentationController {
            sheet.animateChanges { sheet.selectedDetentIdentifier = .medium }
        }
    }
}

private extension WordStudyTerm {
    var title: String {
        switch self {
        case .root: l("word_study.root")
        case .lemma: l("word_study.lemma")
        }
    }

    var arabic: String {
        switch self {
        case .root(let root): root.spacedLetters
        case .lemma(let lemma): lemma.text
        }
    }
}
