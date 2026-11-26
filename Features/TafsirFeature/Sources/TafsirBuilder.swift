//
//  TafsirBuilder.swift
//

import AppDependencies
import QuranKit
import QuranTextKit
import TranslationService
import TranslationsFeature
import UIKit

@MainActor
public struct TafsirBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    /// The tafsir sheet for `startingVerse`. `onVerseChange` is called with each ayah the sheet moves to.
    public func build(startingVerse: AyahNumber, onVerseChange: @escaping (AyahNumber) -> Void) -> UIViewController {
        let viewModel = TafsirViewModel(
            startingVerse: startingVerse,
            localTranslationsRetriever: LocalTranslationsRetriever(databasesURL: container.databasesURL),
            dataService: QuranTextDataService(
                databasesURL: container.databasesURL,
                quranFileURL: container.quranUthmaniV2Database
            ),
            onVerseChange: onVerseChange
        )
        let viewController = TafsirViewController(
            viewModel: viewModel,
            translationsListBuilder: TranslationsListBuilder(container: container)
        )
        return UINavigationController(rootViewController: viewController)
    }

    // MARK: Private

    private let container: AppDependencies
}
