//
//  WordOccurrencesViewModelTests.swift
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
final class WordOccurrencesViewModelTests: XCTestCase {
    // MARK: Internal

    func test_pagesThroughARootInQuranOrderUntilComplete() async throws {
        let root = try await headSegment(of: word(1, 2, 1)).root
        let viewModel = makeViewModel(term: .root(try XCTUnwrap(root)), pageSize: 30)

        await viewModel.loadNextPage()
        XCTAssertEqual(viewModel.occurrences.count, 30)
        XCTAssertEqual(viewModel.occurrences.first?.word, word(1, 2, 1))
        XCTAssertEqual(viewModel.occurrences.first?.arabic, "ٱلْحَمْدُ")
        XCTAssertFalse(viewModel.isComplete)

        await viewModel.loadNextPage()
        await viewModel.loadNextPage()

        XCTAssertEqual(viewModel.occurrences.count, 68, "ح م د is one segment in each of its 68 words")
        XCTAssertEqual(viewModel.occurrences.map(\.word), viewModel.occurrences.map(\.word).sorted())
        XCTAssertTrue(viewModel.isComplete)
        XCTAssertFalse(viewModel.failed)
    }

    func test_aCompleteListLoadsNothingMore() async throws {
        let lemma = try await headSegment(of: word(1, 2, 1)).lemma
        let viewModel = makeViewModel(term: .lemma(try XCTUnwrap(lemma)), pageSize: 50)

        await viewModel.loadNextPage()
        XCTAssertEqual(viewModel.occurrences.count, 43)
        XCTAssertTrue(viewModel.isComplete)

        await viewModel.loadNextPage()
        XCTAssertEqual(viewModel.occurrences.count, 43)
    }

    func test_selectingAnOccurrenceOpensItsWord() async throws {
        let root = try await headSegment(of: word(1, 2, 1)).root
        var selected: [Word] = []
        let viewModel = makeViewModel(term: .root(try XCTUnwrap(root)), pageSize: 5) { selected.append($0) }
        await viewModel.loadNextPage()

        viewModel.select(viewModel.occurrences[1])

        XCTAssertEqual(selected, [word(2, 30, 20)])
    }

    func test_aFailedPageStopsTheList() async throws {
        let root = try await headSegment(of: word(1, 2, 1)).root
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).db")
        let viewModel = WordOccurrencesViewModel(
            term: .root(try XCTUnwrap(root)),
            quran: quran,
            service: WordStudyService(morphologyFileURL: missing, wordByWordFileURL: missing),
            language: .english,
            selectWord: { _ in }
        )

        await viewModel.loadNextPage()

        XCTAssertTrue(viewModel.failed)
        XCTAssertEqual(viewModel.occurrences, [])
    }

    func test_aCancelledPageIsNotAFailureAndLoadsAgain() async throws {
        let root = try await headSegment(of: word(1, 2, 1)).root
        let viewModel = makeViewModel(term: .root(try XCTUnwrap(root)), pageSize: 30)

        let task = Task { await viewModel.loadNextPage() }
        task.cancel()
        await task.value

        XCTAssertFalse(viewModel.failed)
        XCTAssertEqual(viewModel.occurrences, [], "A cancelled page adds nothing")

        await viewModel.loadNextPage()
        XCTAssertEqual(viewModel.occurrences.count, 30)
    }

    /// The largest list in the corpus, the conjunction و (9,594 segments), paged as the sheet pages it:
    /// every page is read off the main actor, and none takes long enough to keep the list waiting.
    func test_theLargestListPagesQuickly() async throws {
        // 2:4 وَٱلَّذِينَ: its first segment is the conjunction.
        let segments = try await service.study(of: word(2, 4, 1), language: .english)?.morphology.segments
        let conjunction = try XCTUnwrap(segments?.first?.lemma)
        XCTAssertEqual(conjunction.text, "و")
        let viewModel = makeViewModel(term: .lemma(conjunction), pageSize: 50)

        let clock = ContinuousClock()
        var slowest = Duration.zero
        var pages = 0
        while !viewModel.isComplete, !viewModel.failed {
            let elapsed = await clock.measure { await viewModel.loadNextPage() }
            slowest = max(slowest, elapsed)
            pages += 1
        }

        XCTAssertFalse(viewModel.failed)
        XCTAssertEqual(Set(viewModel.occurrences.map(\.word)).count, viewModel.occurrences.count)
        XCTAssertGreaterThan(viewModel.occurrences.count, 9000)
        print("Word study: \(viewModel.occurrences.count) و words in \(pages) pages; slowest page \(slowest)")
        XCTAssertLessThan(slowest, .milliseconds(250))
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405
    private let service = WordStudyService(
        morphologyFileURL: TestResources.resourceURL("quran_morphology.db"),
        wordByWordFileURL: TestResources.resourceURL("word_by_word.db")
    )

    private func makeViewModel(
        term: WordStudyTerm,
        pageSize: Int,
        selectWord: @escaping (Word) -> Void = { _ in }
    ) -> WordOccurrencesViewModel {
        WordOccurrencesViewModel(
            term: term,
            quran: quran,
            service: service,
            language: .english,
            pageSize: pageSize,
            selectWord: selectWord
        )
    }

    private func headSegment(of word: Word) async throws -> MorphologySegment {
        let study = try await service.study(of: word, language: .english)
        return try XCTUnwrap(study?.morphology.headSegment)
    }

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: AyahNumber(quran: quran, sura: sura, ayah: ayah)!, wordNumber: number)
    }
}
