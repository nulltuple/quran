import AnnotationsService
import QuranAnnotations
import QuranKit
import QuranTextKit
import UIKit

@MainActor
struct AyahSetBuilder {
    #if QURAN_SYNC
    init(
        ayahBookmarkCollectionService: AyahBookmarkCollectionService,
        ayahHighlightService: MobileSyncAyahHighlightService,
        quranTextDataService: QuranTextDataService,
        navigateToAyah: @escaping (AyahNumber) -> Void
    ) {
        self.ayahBookmarkCollectionService = ayahBookmarkCollectionService
        self.ayahHighlightService = ayahHighlightService
        self.quranTextDataService = quranTextDataService
        self.navigateToAyah = navigateToAyah
    }
    #else
    init(
        ayahBookmarkCollectionService: AyahBookmarkCollectionService,
        quranTextDataService: QuranTextDataService,
        navigateToAyah: @escaping (AyahNumber) -> Void
    ) {
        self.ayahBookmarkCollectionService = ayahBookmarkCollectionService
        self.quranTextDataService = quranTextDataService
        self.navigateToAyah = navigateToAyah
    }
    #endif

    func buildCollection(
        _ collection: AyahBookmarkCollection,
        collectionDeleted: @escaping () -> Void
    ) -> UIViewController {
        build(
            dataSource: BookmarkCollectionAyahSetDataSource(
                collection: collection,
                service: ayahBookmarkCollectionService
            ),
            dataSourceDeleted: collectionDeleted
        )
    }

    #if QURAN_SYNC
    func buildHighlights(color: HighlightColor, ayahs: [AyahNumber]) -> UIViewController {
        build(
            dataSource: HighlightAyahSetDataSource(
                color: color,
                initialAyahs: ayahs,
                service: ayahHighlightService
            ),
            dataSourceDeleted: {}
        )
    }

    private let ayahHighlightService: MobileSyncAyahHighlightService
    #endif

    private let ayahBookmarkCollectionService: AyahBookmarkCollectionService
    private let quranTextDataService: QuranTextDataService
    private let navigateToAyah: (AyahNumber) -> Void

    private func build(
        dataSource: any AyahSetDataSource,
        dataSourceDeleted: @escaping () -> Void
    ) -> UIViewController {
        let viewModel = AyahSetViewModel(
            dataSource: dataSource,
            quranTextDataService: quranTextDataService,
            navigateToAyah: navigateToAyah,
            dataSourceDeleted: dataSourceDeleted
        )
        return AyahSetViewController(viewModel: viewModel)
    }
}
