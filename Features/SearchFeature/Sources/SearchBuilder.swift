//
//  SearchBuilder.swift
//  Quran
//
//  Created by Mohamed Afifi on 5/15/17.
//
//  Quran for iOS is a Quran reading application for iOS.
//  Copyright (C) 2017  Quran.com
//

import AppDependencies
import FeaturesSupport
import QuranKit
import QuranTextKit
import ReadingService
import RecitationRecognition
import UIKit

@MainActor
public struct SearchBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build(withListener listener: QuranNavigator) -> UIViewController {
        let viewModel = SearchViewModel(
            analytics: container.analytics,
            searchService: CompositeSearcher(
                databasesURL: container.databasesURL,
                quranFileURL: container.quranUthmaniV2Database
            ),
            navigateTo: { [weak listener] verse in
                listener?.navigateTo(ayah: verse, lastPage: nil)
            }
        )
        let container = container
        let viewController = SearchViewController(viewModel: viewModel) { navigateTo in
            VoiceSearchViewModel(
                loader: RecitationEngineLoader(
                    downloadManager: container.downloadManager,
                    quranUthmaniV2Database: container.quranUthmaniV2Database,
                    wordByWordDatabase: container.wordByWordDatabase
                ),
                microphone: RecitationMicrophone(),
                quran: { ReadingPreferences.shared.reading.quran },
                navigateTo: navigateTo
            )
        }
        return viewController
    }

    // MARK: Internal

    let container: AppDependencies
}
