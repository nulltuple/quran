//
//  HifzReviewBuilder.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import AppDependencies
import FeaturesSupport
import MemorizationPersistence
import MemorizationService
import QuranKit
import ReadingService
import SwiftUI
import UIKit

/// Builds the H3 Memorization screen (review queue, Sabaq/Sabqi/Manzil budgets, and Juz → Surah → Ayah map).
@MainActor
public struct HifzReviewBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build(withListener listener: QuranNavigator) -> UIViewController {
        let service = MemorizationService(
            persistence: CoreDataMemorizationPersistence(stack: container.coreDataStack)
        )
        var hostingController: UIViewController?
        let builder = self
        let viewModel = HifzReviewViewModel(
            service: service,
            budgetStore: ReviewBudgetStore(),
            practicePassage: { [weak listener] passage in
                listener?.navigateToPractice(verses: passage.first ... passage.last)
            },
            openAyah: { [weak listener] ayah in
                let activeQuran = ReadingPreferences.shared.reading.quran
                let mapped = AyahNumber(quran: activeQuran, sura: ayah.sura.suraNumber, ayah: ayah.ayah) ?? ayah
                listener?.navigateTo(ayah: mapped, lastPage: nil)
            },
            openSpotTest: { [weak listener] in
                guard let listener, let nav = hostingController?.navigationController else { return }
                nav.pushViewController(builder.buildSpotTest(withListener: listener), animated: true)
            }
        )
        let viewController = UIHostingController(rootView: HifzReviewView(viewModel: viewModel))
        viewController.navigationItem.largeTitleDisplayMode = .never
        hostingController = viewController
        return viewController
    }

    public func buildSpotTest(withListener listener: QuranNavigator) -> UIViewController {
        let service = MemorizationService(
            persistence: CoreDataMemorizationPersistence(stack: container.coreDataStack)
        )
        let textLoader = SpotTestTextLoader(
            uthmaniDatabase: container.quranUthmaniV2Database,
            wordByWordDatabase: container.wordByWordDatabase
        )
        let viewModel = SpotTestViewModel(
            service: service,
            textLoader: textLoader,
            practicePassage: { [weak listener] passage in
                listener?.navigateToPractice(verses: passage.first ... passage.last)
            },
            openAyah: { [weak listener] ayah in
                let activeQuran = ReadingPreferences.shared.reading.quran
                let mapped = AyahNumber(quran: activeQuran, sura: ayah.sura.suraNumber, ayah: ayah.ayah) ?? ayah
                listener?.navigateTo(ayah: mapped, lastPage: nil)
            }
        )
        let viewController = UIHostingController(rootView: SpotTestView(viewModel: viewModel, showCloseButton: false))
        viewController.navigationItem.largeTitleDisplayMode = .never
        return viewController
    }

    // MARK: Private

    private let container: AppDependencies
}
