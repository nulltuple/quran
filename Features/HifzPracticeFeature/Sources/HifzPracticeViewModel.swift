//
//  HifzPracticeViewModel.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import MemorizationService
import Observation
import QuranAnnotations
import QuranKit
import RecitationRecognition
import VLogging

/// Hifz practice on the page (roadmap H2, slice a): the passage's words are hidden; the person
/// recites each ayah from memory, may ask for its next word's first letter or the word itself,
/// checks it, and grades it. The graded ayahs are saved as one session (H1).
@MainActor
@Observable
public final class HifzPracticeViewModel {
    // MARK: Lifecycle

    /// `mask` shows the hidden words on the page (nil restores it); `close` removes the controls.
    public init(
        passage: Passage,
        verseText: RecitationVerseText,
        service: MemorizationService,
        now: @escaping @Sendable () -> Date = Date.init,
        mask: @escaping (PracticeMask?) -> Void,
        close: @escaping () -> Void
    ) {
        self.passage = passage
        verses = passage.verses
        self.verseText = verseText
        self.service = service
        self.now = now
        self.mask = mask
        self.close = close
        startedOn = now()
    }

    // MARK: Public

    public enum Phase: Equatable {
        case loading
        /// The current ayah is (partly) hidden.
        case reciting
        /// The current ayah is shown so the person can compare and grade it.
        case grading
        /// Every ayah graded and the session saved; the passage's next review.
        case finished(PassageProgress)
        case failed
    }

    public let passage: Passage
    public let verses: [AyahNumber]
    public private(set) var phase: Phase = .loading
    public private(set) var currentIndex = 0
    /// Words of the current ayah shown so far (QUL numbering).
    public private(set) var revealedWords = 0
    /// The next hidden word's first letter, after the person asked for it.
    public private(set) var hint: String?

    public var currentVerse: AyahNumber? {
        verses.indices.contains(currentIndex) ? verses[currentIndex] : nil
    }

    /// Whether the current ayah has a hidden word left to peek or hint.
    public var hasHiddenWord: Bool {
        guard let currentVerse else { return false }
        return revealedWords < wordCount(currentVerse)
    }

    public func start() async {
        do {
            let units = try await verseText.expectedWords.expectedWords(for: verses)
            for unit in units {
                for word in unit.words {
                    wordTexts[word] = word == unit.words.first ? unit.text : nil
                    wordCounts[word.verse] = max(wordCounts[word.verse] ?? 0, word.wordNumber)
                }
            }
            phase = .reciting
            updateMask()
        } catch {
            logger.error("Hifz practice: loading words failed. \(error)")
            phase = .failed
        }
    }

    /// Shows the first letter of the next hidden word; counts as help.
    public func showHint() {
        guard phase == .reciting, let currentVerse, hasHiddenWord else { return }
        let word = Word(verse: currentVerse, wordNumber: revealedWords + 1)
        // A word written joined to the one before it has no text of its own: its unit starts earlier.
        hint = wordTexts[word].flatMap { Self.firstLetter(of: $0) } ?? "…"
        assistance += 1
    }

    /// Shows the next hidden word; counts as help.
    public func revealNextWord() {
        guard phase == .reciting, hasHiddenWord else { return }
        revealedWords += 1
        hint = nil
        assistance += 1
        updateMask()
    }

    /// Shows the whole ayah to compare with what was recited.
    public func check() {
        guard phase == .reciting, let currentVerse else { return }
        revealedWords = wordCount(currentVerse)
        hint = nil
        phase = .grading
        updateMask()
    }

    /// Grades the current ayah, then moves to the next, or saves the session after the last.
    /// `.correct` with help used is recorded as `.hint`.
    public func grade(_ outcome: RecallOutcome) async {
        guard phase == .grading, let currentVerse else { return }
        let recorded: RecallOutcome = outcome == .correct && assistance > 0 ? .hint : outcome
        recalls.append(VerseRecall(verse: currentVerse, outcome: recorded, assistance: assistance))
        assistance = 0
        if currentIndex + 1 < verses.count {
            currentIndex += 1
            revealedWords = 0
            phase = .reciting
            updateMask()
        } else {
            currentIndex = verses.count
            updateMask()
            await save()
        }
    }

    /// Ends practice: the ayahs graded so far are saved as a session, the page shows every word again.
    public func end() async {
        await saveGradedAyahs()
        mask(nil)
        close()
    }

    /// Saves the ayahs graded so far, once, if practice stopped before the last.
    public func saveGradedAyahs() async {
        if !saved, !recalls.isEmpty {
            await save()
        }
    }

    // MARK: Internal

    static func firstLetter(of text: String) -> String? {
        text.first.map(String.init)
    }

    // MARK: Private

    private let verseText: RecitationVerseText
    private let service: MemorizationService
    private let now: @Sendable () -> Date
    private let mask: (PracticeMask?) -> Void
    private let close: () -> Void
    private let startedOn: Date

    private var wordTexts: [Word: String] = [:]
    private var wordCounts: [AyahNumber: Int] = [:]
    private var assistance = 0
    private var recalls: [VerseRecall] = []
    private var saved = false

    private func wordCount(_ verse: AyahNumber) -> Int {
        wordCounts[verse] ?? 0
    }

    private func updateMask() {
        let later = verses.indices.contains(currentIndex + 1) ? verses[(currentIndex + 1)...] : []
        // While grading, the whole ayah shows, its end marker too (a glyph after its last word).
        let partialVerse = phase == .grading ? nil : currentVerse
        mask(PracticeMask(hiddenVerses: Set(later), partialVerse: partialVerse, revealedWords: revealedWords))
    }

    private func save() async {
        do {
            try await service.recordSession(passage, startedOn: startedOn, recalls: recalls)
            saved = true
            phase = try await .finished(service.progress(of: passage))
        } catch {
            logger.error("Hifz practice: saving the session failed. \(error)")
            phase = .failed
        }
    }
}
