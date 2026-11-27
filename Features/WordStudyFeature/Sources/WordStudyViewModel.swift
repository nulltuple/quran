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

    init(word: Word, service: WordStudyService, language: WordByWordLanguage) {
        self.word = word
        self.service = service
        self.language = language
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

    // MARK: Private

    private let service: WordStudyService
    private let language: WordByWordLanguage
}
