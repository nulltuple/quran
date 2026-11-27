//
//  WordStudyViewModel.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Combine
import QuranKit
import QuranText
import VLogging
import WordTextService

@MainActor
final class WordStudyViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(WordStudy)
        /// The corpus has no such word, or reading it failed: the sheet says word study is unavailable.
        case unavailable
    }

    // MARK: Lifecycle

    /// `showOccurrences` opens the list of words sharing a root or dictionary form; `showVerse`
    /// moves the reader behind the sheet to the studied word's ayah when the study appears.
    init(
        word: Word,
        service: WordStudyService,
        language: WordByWordLanguage,
        showOccurrences: @escaping (WordStudyTerm) -> Void = { _ in },
        showVerse: @escaping (AyahNumber) -> Void = { _ in }
    ) {
        self.word = word
        self.service = service
        self.language = language
        self.showOccurrences = showOccurrences
        self.showVerse = showVerse
    }

    // MARK: Internal

    let word: Word
    @Published private(set) var state: State = .loading

    func load() async {
        do {
            let study = try await service.study(of: word, language: language)
            state = study.map(State.loaded) ?? .unavailable
        } catch {
            logger.error("Word study: failed to load \(word.verse.nonLocalizedDescription) word \(word.wordNumber). Error: \(error)")
            state = .unavailable
        }
    }

    func didAppear() {
        showVerse(word.verse)
    }

    func select(_ term: WordStudyTerm) {
        showOccurrences(term)
    }

    // MARK: Private

    private let showOccurrences: (WordStudyTerm) -> Void
    private let showVerse: (AyahNumber) -> Void
    private let service: WordStudyService
    private let language: WordByWordLanguage
}
