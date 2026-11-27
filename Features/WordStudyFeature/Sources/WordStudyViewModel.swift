//
//  WordStudyViewModel.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Combine
import QuranAudioKit
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

    /// Hearing the word from a recitation recorded with word timings.
    enum Hearing: Equatable {
        /// Looking up the word's timing, or no reciter or timing has it: the sheet shows no Hear row.
        case unavailable
        case ready(WordRecitation)
        case playing(WordRecitation)
        /// The last attempt failed, such as a stream without a connection; the row can try again.
        case failed(WordRecitation)
    }

    // MARK: Lifecycle

    /// `recitations` and `recitationPlayer` let the sheet play the word (none without them);
    /// `pauseRecitation` pauses the reader's recitation before the word plays.
    /// `showOccurrences` opens the list of words sharing a root or dictionary form; `showVerse`
    /// moves the reader behind the sheet to the studied word's ayah when the study appears.
    init(
        word: Word,
        service: WordStudyService,
        language: WordByWordLanguage,
        recitations: WordRecitationRetriever? = nil,
        recitationPlayer: WordRecitationPlayer? = nil,
        pauseRecitation: @escaping () -> Void = {},
        showOccurrences: @escaping (WordStudyTerm) -> Void = { _ in },
        showVerse: @escaping (AyahNumber) -> Void = { _ in }
    ) {
        self.word = word
        self.service = service
        self.language = language
        self.recitations = recitations
        self.recitationPlayer = recitationPlayer
        self.pauseRecitation = pauseRecitation
        self.showOccurrences = showOccurrences
        self.showVerse = showVerse
    }

    // MARK: Internal

    let word: Word
    @Published private(set) var state: State = .loading
    @Published private(set) var hearing: Hearing = .unavailable

    func load() async {
        async let recitation = loadRecitation()
        do {
            let study = try await service.study(of: word, language: language)
            state = study.map(State.loaded) ?? .unavailable
        } catch {
            logger.error("Word study: failed to load \(word.verse.nonLocalizedDescription) word \(word.wordNumber). Error: \(error)")
            state = .unavailable
        }
        hearing = await recitation.map(Hearing.ready) ?? .unavailable
    }

    /// Plays the word, or stops it while it plays.
    func toggleHearing() async {
        guard let recitationPlayer else {
            return
        }
        switch hearing {
        case .unavailable:
            return
        case .playing:
            recitationPlayer.stop()
        case .ready(let recitation), .failed(let recitation):
            pauseRecitation()
            hearing = .playing(recitation)
            let outcome = await recitationPlayer.play(recitation)
            // A newer play or a stop already set the state it ended in.
            guard hearing == .playing(recitation) else {
                return
            }
            hearing = outcome == .failed ? .failed(recitation) : .ready(recitation)
        }
    }

    /// The study left the screen (another pushed over it, or the sheet closed): silence it.
    func didDisappear() {
        if case .playing = hearing {
            recitationPlayer?.stop()
        }
    }

    func didAppear() {
        showVerse(word.verse)
    }

    func select(_ term: WordStudyTerm) {
        showOccurrences(term)
    }

    // MARK: Private

    private let recitations: WordRecitationRetriever?
    private let recitationPlayer: WordRecitationPlayer?
    private let pauseRecitation: () -> Void
    private let showOccurrences: (WordStudyTerm) -> Void
    private let showVerse: (AyahNumber) -> Void
    private let service: WordStudyService
    private let language: WordByWordLanguage

    private func loadRecitation() async -> WordRecitation? {
        guard let recitations, recitationPlayer != nil else {
            return nil
        }
        do {
            return try await recitations.recitation(of: word)
        } catch {
            logger.error("Word study: failed to read the word's timing. Error: \(error)")
            return nil
        }
    }
}
