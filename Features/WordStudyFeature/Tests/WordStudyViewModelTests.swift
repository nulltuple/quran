//
//  WordStudyViewModelTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import QuranKit
import QuranText
import TestResources
import WordTextService
import XCTest
@testable import WordStudyFeature

@MainActor
final class WordStudyViewModelTests: XCTestCase {
    // MARK: Internal

    func test_loadsTheWord() async {
        let viewModel = WordStudyViewModel(word: word(1, 2, 1), service: service(), language: .english)
        XCTAssertEqual(viewModel.state, .loading)

        await viewModel.load()

        guard case .loaded(let study) = viewModel.state else {
            return XCTFail("Expected a loaded study, got \(viewModel.state)")
        }
        XCTAssertEqual(study.arabic, "ٱلْحَمْدُ")
        XCTAssertEqual(study.meaning, "All praises and thanks")
    }

    func test_aWordThatDoesNotExistIsUnavailable() async {
        let viewModel = WordStudyViewModel(word: word(1, 1, 9), service: service(), language: .english)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .unavailable)
    }

    func test_aMissingDatabaseIsUnavailable() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).db")
        let service = WordStudyService(morphologyFileURL: missing, wordByWordFileURL: missing)
        let viewModel = WordStudyViewModel(word: word(1, 2, 1), service: service, language: .english)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .unavailable)
    }

    func test_appearingMovesTheReaderToTheWordsAyah() {
        var shown: [AyahNumber] = []
        let viewModel = WordStudyViewModel(
            word: word(2, 3, 2),
            service: service(),
            language: .english,
            showVerse: { shown.append($0) }
        )

        viewModel.didAppear()

        XCTAssertEqual(shown, [word(2, 3, 2).verse])
    }

    func test_selectingARootOpensItsOccurrences() async {
        var opened: [WordStudyTerm] = []
        let viewModel = WordStudyViewModel(
            word: word(1, 2, 1),
            service: service(),
            language: .english,
            showOccurrences: { opened.append($0) }
        )
        await viewModel.load()
        guard case .loaded(let study) = viewModel.state, let root = study.morphology.headSegment?.root else {
            return XCTFail("Expected a loaded study with a root, got \(viewModel.state)")
        }

        viewModel.select(.root(root))

        XCTAssertEqual(opened, [.root(root)])
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405

    private func service() -> WordStudyService {
        WordStudyService(
            morphologyFileURL: TestResources.resourceURL("quran_morphology.db"),
            wordByWordFileURL: TestResources.resourceURL("word_by_word.db")
        )
    }

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: AyahNumber(quran: quran, sura: sura, ayah: ayah)!, wordNumber: number)
    }
}
