//
//  WordOccurrencesViewModel.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Combine
import QuranKit
import QuranText
import VLogging
import WordTextService

/// Every word in the Quran with a root or a dictionary form, loaded a page at a time as the list
/// scrolls. Each page is read off the main actor; a page whose row scrolls away is cancelled.
@MainActor
final class WordOccurrencesViewModel: ObservableObject {
    // MARK: Lifecycle

    init(
        term: WordStudyTerm,
        quran: Quran,
        service: WordStudyService,
        language: WordByWordLanguage,
        pageSize: Int = 50,
        selectWord: @escaping (Word) -> Void
    ) {
        self.term = term
        self.quran = quran
        self.service = service
        self.language = language
        self.pageSize = pageSize
        self.selectWord = selectWord
    }

    // MARK: Internal

    let term: WordStudyTerm

    @Published private(set) var occurrences: [WordOccurrence] = []
    /// Every occurrence is loaded.
    @Published private(set) var isComplete = false
    /// Reading a page failed; the list stops loading.
    @Published private(set) var failed = false

    /// Loads the next page, unless one is loading or the list is complete.
    func loadNextPage() async {
        guard !isLoading, !isComplete, !failed else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await service.occurrences(
                of: term,
                quran: quran,
                after: occurrences.last?.word,
                limit: pageSize,
                language: language
            )
            try Task.checkCancellation()
            occurrences += page
            isComplete = page.count < pageSize
        } catch {
            // The loading row scrolled away (persistence wraps the cancellation in its own error);
            // it asks again when it reappears.
            if Task.isCancelled {
                return
            }
            logger.error("Word study: failed to load occurrences after \(occurrences.count). Error: \(error)")
            failed = true
        }
    }

    func select(_ occurrence: WordOccurrence) {
        selectWord(occurrence.word)
    }

    // MARK: Private

    private let quran: Quran
    private let service: WordStudyService
    private let language: WordByWordLanguage
    private let pageSize: Int
    private let selectWord: (Word) -> Void
    private var isLoading = false
}
