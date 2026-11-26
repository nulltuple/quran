//
//  BookmarkCollectionsBuilder.swift
//

import AnnotationsService
import AppDependencies
import FeaturesSupport
import QuranKit
import UIKit

@MainActor
struct BookmarkCollectionsBuilder {
    let container: AppDependencies

    func build(
        withListener listener: QuranNavigator,
        navigationController: UINavigationController
    ) -> UIViewController {
        #if QURAN_SYNC
        let collectionService = container.ayahBookmarkCollectionService()
        let highlightService = container.ayahHighlightService()
        let ayahSetBuilder = AyahSetBuilder(
            ayahBookmarkCollectionService: collectionService,
            ayahHighlightService: highlightService,
            quranTextDataService: container.textDataService(),
            navigateToAyah: { [weak listener] ayah in
                listener?.navigateTo(ayah: ayah, lastPage: nil)
            }
        )
        let viewModel = BookmarkCollectionsViewModel(
            authenticationClient: container.authenticationClient,
            quranDataService: container.quranDataService,
            ayahBookmarkCollectionService: collectionService,
            ayahHighlightService: highlightService,
            readingBookmarkService: container.readingBookmarkService(),
            ayahSetBuilder: ayahSetBuilder,
            signInNudge: SyncSignInNudge(
                authenticationClient: container.authenticationClient,
                analytics: container.analytics,
                signInViewControllers: { [weak navigationController] in navigationController.map { [$0] } ?? [] }
            ),
            navigationController: navigationController,
            navigateToPage: { [weak listener] page in
                listener?.navigateTo(page: page, lastPage: nil)
            },
            navigateToAyah: { [weak listener] ayah in
                listener?.navigateTo(ayah: ayah, lastPage: nil)
            }
        )
        #else
        let collectionService = container.ayahBookmarkCollectionService()
        let ayahSetBuilder = AyahSetBuilder(
            ayahBookmarkCollectionService: collectionService,
            quranTextDataService: container.textDataService(),
            navigateToAyah: { [weak listener] ayah in
                listener?.navigateTo(ayah: ayah, lastPage: nil)
            }
        )
        let pageBookmarks = BookmarksViewModel(
            analytics: container.analytics,
            service: PageBookmarkService(persistence: container.pageBookmarkPersistence),
            navigateTo: { [weak listener] page in
                listener?.navigateTo(page: page, lastPage: nil)
            }
        )
        let viewModel = BookmarkCollectionsViewModel(
            ayahBookmarkCollectionService: collectionService,
            pageBookmarks: pageBookmarks,
            ayahSetBuilder: ayahSetBuilder,
            navigationController: navigationController
        )
        #endif
        return BookmarkCollectionsViewController(viewModel: viewModel)
    }
}
