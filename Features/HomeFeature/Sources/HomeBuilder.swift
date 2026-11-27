//
//  HomeBuilder.swift
//  Quran
//
//  Created by Afifi, Mohamed on 11/14/20.
//  Copyright © 2020 Quran.com. All rights reserved.
//

import AnnotationsService
import AppDependencies
import FeaturesSupport
import HifzReviewFeature
import MemorizationPersistence
import MemorizationService
import QuranTextKit
import ReadingSelectorFeature
import UIKit

@MainActor
public struct HomeBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build(withListener listener: QuranNavigator) -> UIViewController {
        let textRetriever = QuranTextDataService(
            databasesURL: container.databasesURL,
            quranFileURL: container.quranUthmaniV2Database
        )
        let memorizationService = MemorizationService(
            persistence: CoreDataMemorizationPersistence(stack: container.coreDataStack)
        )
        #if QURAN_SYNC
        let viewModel = HomeViewModel(
            lastPageService: container.lastPageService(),
            textRetriever: textRetriever,
            readingBookmarkService: container.readingBookmarkService(),
            memorizationService: memorizationService,
            navigateToPage: { [weak listener] page, lastPage in
                listener?.navigateTo(page: page, lastPage: lastPage)
            },
            navigateToAyah: { [weak listener] ayah in
                listener?.navigateTo(ayah: ayah, lastPage: nil)
            },
            navigateToPractice: { [weak listener] passage in
                listener?.navigateToPractice(verses: passage.first ... passage.last)
            }
        )
        #else
        let viewModel = HomeViewModel(
            lastPageService: container.lastPageService(),
            textRetriever: textRetriever,
            memorizationService: memorizationService,
            navigateToPage: { [weak listener] page, lastPage in
                listener?.navigateTo(page: page, lastPage: lastPage)
            },
            navigateToAyah: { [weak listener] ayah in
                listener?.navigateTo(ayah: ayah, lastPage: nil)
            },
            navigateToPractice: { [weak listener] passage in
                listener?.navigateToPractice(verses: passage.first ... passage.last)
            }
        )
        #endif
        let viewController = HomeViewController(
            viewModel: viewModel,
            readingSelectorBuilder: ReadingSelectorBuilder(container: container),
            hifzReviewBuilder: HifzReviewBuilder(container: container),
            quranNavigator: listener
        )
        return viewController
    }

    // MARK: Internal

    let container: AppDependencies
}
