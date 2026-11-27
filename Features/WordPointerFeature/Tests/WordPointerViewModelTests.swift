//
//  WordPointerViewModelTests.swift
//
//
//  Created by Mohamed Afifi on 2026-10-07.
//

import QuranKit
import TestResources
import UIKit
import WordTextService
import XCTest
@testable import WordPointerFeature

@MainActor
final class WordPointerViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        WordTextPreferences.shared.wordTextType = .translation
        viewModel = WordPointerViewModel(service: WordTextService(fileURL: TestResources.resourceURL("word_by_word.db")))
        viewModel.listener = listener
    }

    func testPanningOverWordShowsItsTranslation() async {
        let result = await viewModel.viewPanned(to: .zero)

        XCTAssertEqual(result, .showPopover(text: "(of) your Lord"))
    }

    func testCancelledLookupDoesNotShowPopover() async {
        let lookup = Task { await viewModel.viewPanned(to: .zero) }
        lookup.cancel()

        let result = await lookup.value

        XCTAssertEqual(result, .none)
    }

    func testCancelledLookupDoesNotHideNextLookupForSameWord() async {
        let staleLookup = Task { await viewModel.viewPanned(to: .zero) }
        staleLookup.cancel()
        _ = await staleLookup.value

        let result = await viewModel.viewPanned(to: .zero)

        XCTAssertEqual(result, .showPopover(text: "(of) your Lord"))
    }

    func testReleasingOverAWordKeepsItsPopoverAndATapOpensItsStudy() async {
        _ = await viewModel.viewPanned(to: .zero)

        let released = viewModel.viewPanEnded()
        XCTAssertEqual(released?.text, "(of) your Lord")
        XCTAssertEqual(listener.highlights.last, listener.word, "The released word stays highlighted")

        viewModel.openReleasedWordStudy()
        XCTAssertEqual(listener.studiedWords, [listener.word!])
        XCTAssertEqual(listener.highlights.last, .some(nil))
    }

    func testTheStudyOpensTheWordNumberedAsInTheAyahText() async {
        // 2:2 glyph 5 is a pause mark, so glyph 6 is word 5.
        let listener = WordPointerListenerFake(word: word(2, 2, 6))
        viewModel.listener = listener
        _ = await viewModel.viewPanned(to: .zero)
        _ = viewModel.viewPanEnded()

        viewModel.openReleasedWordStudy()

        XCTAssertEqual(listener.studiedWords, [word(2, 2, 5)])
    }

    func testReleasingOverNoWordKeepsNothing() async {
        viewModel.listener = WordPointerListenerFake(word: nil)
        _ = await viewModel.viewPanned(to: .zero)

        XCTAssertNil(viewModel.viewPanEnded())
    }

    func testReleasingBeforeTheLastWordsLookupFinishedKeepsNothing() async {
        _ = await viewModel.viewPanned(to: .zero)
        listener.word = word(1, 1, 2)
        let lookup = Task { await viewModel.viewPanned(to: .zero) }
        lookup.cancel()
        _ = await lookup.value

        XCTAssertNil(viewModel.viewPanEnded())
        XCTAssertEqual(listener.highlights.last, .some(nil))
    }

    func testAnUnhighlightedWordCannotBeOpened() async {
        _ = await viewModel.viewPanned(to: .zero)
        viewModel.unhighlightWord()

        viewModel.openReleasedWordStudy()

        XCTAssertEqual(listener.studiedWords, [])
    }

    // MARK: Private

    private var viewModel: WordPointerViewModel!
    private let listener = WordPointerListenerFake(word: word(110, 3, 3))
}

private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
    Word(verse: AyahNumber(quran: Quran.hafsMadani1405, sura: sura, ayah: ayah)!, wordNumber: number)
}

@MainActor
private final class WordPointerListenerFake: WordPointerListener {
    // MARK: Lifecycle

    init(word: Word?) {
        self.word = word
    }

    // MARK: Internal

    var word: Word?
    private(set) var highlights: [Word?] = []
    private(set) var studiedWords: [Word] = []

    func onWordPointerPanBegan() { }

    func word(at point: CGPoint) -> Word? {
        word
    }

    func highlightWord(_ position: Word?) {
        highlights.append(position)
    }

    func presentWordStudy(_ word: Word) {
        studiedWords.append(word)
    }
}
