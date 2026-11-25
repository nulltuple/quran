//
//  MoreMenuWordByWordTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import WordTextService
import XCTest
@testable import MoreMenuFeature

@MainActor
final class MoreMenuWordByWordTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        previousShowsTransliteration = WordByWordPreferences.shared.showsTransliteration
        WordByWordPreferences.shared.showsTransliteration = false
    }

    override func tearDown() {
        WordByWordPreferences.shared.showsTransliteration = previousShowsTransliteration
        super.tearDown()
    }

    func testTheTransliterationToggleStartsFromTheSavedChoice() {
        WordByWordPreferences.shared.showsTransliteration = true

        XCTAssertTrue(makeSUT().wordByWordShowsTransliteration)
    }

    func testTurningTheTransliterationToggleOnSavesIt() {
        let sut = makeSUT()

        sut.wordByWordShowsTransliteration = true

        XCTAssertTrue(WordByWordPreferences.shared.showsTransliteration)
    }

    // MARK: Private

    private var previousShowsTransliteration = false

    private func makeSUT() -> MoreMenuViewModel {
        MoreMenuViewModel(model: MoreMenuModel(isWordPointerActive: false, state: MoreMenuControlsState()))
    }
}
