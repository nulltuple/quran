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
            }
        )
        let viewController = UIHostingController(rootView: HifzReviewView(viewModel: viewModel))
        viewController.navigationItem.largeTitleDisplayMode = .never
        return viewController
    }

    // MARK: Private

    private let container: AppDependencies
}
