//
//  QuranWordByWordTextTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import NoorFont
import QuranKit
import SwiftUI
import UIKit
import XCTest
@testable import NoorUI

final class QuranWordByWordTextTests: XCTestCase {
    func testVoiceOverReadsTheArabicThenItsMeaning() {
        let word = QuranWordMeaning(arabic: "لِلَّهِ", meaning: "(be) to Allah")

        XCTAssertEqual(word.accessibilityLabel, "لِلَّهِ, (be) to Allah")
    }

    func testVoiceOverReadsTheTransliterationBetweenTheArabicAndTheMeaning() {
        let word = QuranWordMeaning(arabic: "لِلَّهِ", meaning: "(be) to Allah", transliteration: "lillahi")

        XCTAssertEqual(word.accessibilityLabel, "لِلَّهِ, lillahi, (be) to Allah")
    }

    @MainActor
    func testTheTransliterationAddsALineUnderEachWord() {
        if UIFont(name: "icomoon", size: 20) == nil {
            FontName.registerFonts()
        }
        let meaningOnly = [QuranWordMeaning(arabic: "رَبِّ", meaning: "the Lord")]
        let withTransliteration = [QuranWordMeaning(arabic: "رَبِّ", meaning: "the Lord", transliteration: "rabbi")]

        let meaningOnlyHeight = fittingSize(words: meaningOnly, width: 345, dynamicTypeSize: .large).height
        let withTransliterationHeight = fittingSize(words: withTransliteration, width: 345, dynamicTypeSize: .large).height

        XCTAssertGreaterThan(withTransliterationHeight, meaningOnlyHeight + 8)
    }

    func testVoiceOverReadsOnlyTheArabicForAWordWithoutAMeaning() {
        let word = QuranWordMeaning(arabic: "ۛ", meaning: nil)

        XCTAssertEqual(word.accessibilityLabel, "ۛ")
    }

    @MainActor
    func testALongMeaningWrapsInsteadOfWideningTheAyahPastTheScreenAtAccessibilitySizes() {
        if UIFont(name: "icomoon", size: 20) == nil {
            FontName.registerFonts()
        }
        // 2:4's second word; the longest meanings run to about this length.
        let words = [
            QuranWordMeaning(arabic: "يُؤۡمِنُونَ", meaning: "believe in what has been revealed to you"),
            QuranWordMeaning(arabic: "بِمَآ", meaning: "in what"),
        ]
        let width: CGFloat = 320

        let size = fittingSize(words: words, width: width, dynamicTypeSize: .accessibility5)

        XCTAssertLessThanOrEqual(size.width, width)
    }

    @MainActor
    func testShortMeaningsKeepTheirWordsOnOneLineAtTheDefaultSize() {
        if UIFont(name: "icomoon", size: 20) == nil {
            FontName.registerFonts()
        }
        let oneWord = [QuranWordMeaning(arabic: "رَبِّ", meaning: "the Lord")]
        let twoWords = oneWord + [QuranWordMeaning(arabic: "ٱلۡعَٰلَمِينَ", meaning: "of the universe")]

        let oneWordHeight = fittingSize(words: oneWord, width: 345, dynamicTypeSize: .large).height
        let twoWordsHeight = fittingSize(words: twoWords, width: 345, dynamicTypeSize: .large).height

        XCTAssertEqual(twoWordsHeight, oneWordHeight, accuracy: 1)
    }

    // MARK: - Private

    @MainActor
    private func fittingSize(words: [QuranWordMeaning], width: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGSize {
        let controller = UIHostingController(
            rootView: QuranWordByWordText(
                verse: Quran.hafsMadani1405.suras[1].verses[3],
                words: words,
                quranFont: .uthmanicHafs,
                fontSize: .medium
            )
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        return controller.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }
}

final class QuranWordByWordTextTapTests: XCTestCase {
    func testATappableWordReadsAsAButton() {
        let traits = QuranWordByWordText.accessibilityTraits(isHighlighted: false, isTappable: true)

        XCTAssertEqual(traits, .isButton)
    }

    func testARecitedTappableWordReadsAsASelectedButton() {
        let traits = QuranWordByWordText.accessibilityTraits(isHighlighted: true, isTappable: true)

        XCTAssertEqual(traits, [.isButton, .isSelected])
    }

    func testAWordWithoutWordStudyIsNotAButton() {
        let traits = QuranWordByWordText.accessibilityTraits(isHighlighted: true, isTappable: false)

        XCTAssertEqual(traits, .isSelected)
    }

    func testTheWordStudySymbolExists() {
        XCTAssertNotNil(UIImage(systemName: NoorSystemImage.wordStudy.rawValue))
    }
}
