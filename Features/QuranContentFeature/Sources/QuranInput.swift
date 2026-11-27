//
//  QuranInput.swift
//  Quran
//
//  Created by Afifi, Mohamed on 9/2/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import QuranAnnotations
import QuranKit

public struct QuranInput {
    // MARK: Lifecycle

    public init(
        initialPage: Page,
        lastPage: LastPage?,
        navigationAyah: AyahNumber?,
        initialPracticeRange: ClosedRange<AyahNumber>? = nil
    ) {
        self.initialPage = initialPage
        self.lastPage = lastPage
        self.navigationAyah = navigationAyah
        self.initialPracticeRange = initialPracticeRange
    }

    // MARK: Public

    public let initialPage: Page
    public let lastPage: LastPage?
    public let navigationAyah: AyahNumber?
    /// When set, the reader launches Hifz Practice immediately on this exact passage (roadmap H3).
    public let initialPracticeRange: ClosedRange<AyahNumber>?
}
