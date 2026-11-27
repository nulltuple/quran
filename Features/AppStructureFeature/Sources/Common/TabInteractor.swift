//
//  TabInteractor.swift
//  Quran
//
//  Created by Afifi, Mohamed on 3/24/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import FeaturesSupport
import QuranAnnotations
import QuranContentFeature
import QuranKit
import QuranViewFeature
import ReadingService
import UIKit

protocol TabPresenter: UINavigationController {
}

class TabInteractor: QuranNavigator {
    // MARK: Lifecycle

    init(quranBuilder: QuranBuilder) {
        self.quranBuilder = quranBuilder
    }

    // MARK: Internal

    weak var presenter: TabPresenter?

    func navigateTo(page: Page, lastPage: LastPage?) {
        navigateTo(
            input: QuranInput(initialPage: page, lastPage: lastPage, navigationAyah: nil)
        )
    }

    func navigateTo(ayah: AyahNumber, lastPage: LastPage?) {
        navigateTo(
            input: QuranInput(initialPage: ayah.page, lastPage: lastPage, navigationAyah: ayah)
        )
    }

    func navigateToPractice(verses: ClosedRange<AyahNumber>) {
        let quran = ReadingPreferences.shared.reading.quran
        let first = AyahNumber(quran: quran, sura: verses.lowerBound.sura.suraNumber, ayah: verses.lowerBound.ayah)
            ?? verses.lowerBound
        let last = AyahNumber(quran: quran, sura: verses.upperBound.sura.suraNumber, ayah: verses.upperBound.ayah)
            ?? verses.upperBound
        let range = min(first, last) ... max(first, last)
        navigateTo(
            input: QuranInput(
                initialPage: range.lowerBound.page,
                lastPage: nil,
                navigationAyah: range.lowerBound,
                initialPracticeRange: range
            )
        )
    }

    func start() {
    }

    // MARK: Private

    private let quranBuilder: QuranBuilder

    private func navigateTo(input: QuranInput) {
        let viewController = quranBuilder.build(input: input)
        presenter?.pushViewController(viewController, animated: true)
    }
}
