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

/// Hifz practice on the page (roadmap H2, slices a and b): the passage's words are hidden, except the
/// chosen cue words; the person recites each ayah from memory (straight through, or cumulatively),
/// may listen to it repeated, ask for its next word's first letter or the word itself, checks it,
/// and grades it, marking the words they got wrong. The graded ayahs are kept as a draft after
/// every grade, so practice resumes after the app is killed, and saved as one session (H1).
@MainActor
@Observable
public final class HifzPracticeViewModel {
    // MARK: Lifecycle

    /// `mask` shows the hidden words on the page (nil restores it); `listen` plays an ayah repeated
    /// with pauses to repeat it, `stopListening` stops it; `close` removes the controls.
    public init(
        passage: Passage,
        verseText: RecitationVerseText,
        service: MemorizationService,
        store: PracticeStateStore,
        now: @escaping @Sendable () -> Date = Date.init,
        mask: @escaping (PracticeMask?) -> Void,
        listen: @escaping (AyahNumber) -> Void,
        stopListening: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        self.passage = passage
        verses = passage.verses
        self.verseText = verseText
        self.service = service
        self.store = store
        self.now = now
        self.mask = mask
        self.listen = listen
        self.stopListening = stopListening
        self.close = close
        let order = store.order
        self.order = order
        cueLevel = store.cueLevel
        startedOn = now()
        let steps = PracticePlan.steps(for: passage.verses, order: order)
        self.steps = steps
        items = Self.items(of: steps)
    }

    // MARK: Public

    public enum Phase: Equatable {
        case loading
        /// The current ayah is (partly) hidden.
        case reciting
        /// The current ayah is shown so the person can compare and grade it.
        case grading
        /// The person picks the words they got wrong in the current ayah.
        case markingMistakes
        /// Every ayah graded and the session saved; the passage's next review.
        case finished(PassageProgress)
        case failed
    }

    /// A word of the current ayah as written: words joined in writing form one choice.
    public struct WordChoice: Hashable, Identifiable, Sendable {
        public let text: String
        /// Word numbers (QUL numbering).
        public let words: [Int]

        public var id: Int { words[0] }
    }

    /// How many times listen and repeat plays the ayah, each followed by a pause as long as the ayah.
    public static let listenRepetitions = 3

    public let passage: Passage
    public let verses: [AyahNumber]
    public private(set) var phase: Phase = .loading
    public private(set) var order: PracticeOrder
    public private(set) var cueLevel: PracticeCueLevel
    public private(set) var steps: [PracticeStep]
    /// The index of the ayah being recited among every step's ayahs in turn.
    public private(set) var position = 0
    /// Words of the current ayah shown so far (QUL numbering).
    public private(set) var revealedWords = 0
    /// The next hidden word's first letter, after the person asked for it.
    public private(set) var hint: String?
    /// Words marked as mistakes in the current ayah (QUL numbering).
    public private(set) var markedWords: Set<Int> = []
    /// Whether the current ayah is being played to listen and repeat.
    public private(set) var isListening = false
    /// Whether practice picked up an unsaved session, until the next grade.
    public private(set) var resumed = false

    public var currentVerse: AyahNumber? {
        currentItem?.verse
    }

    /// The current step's index and the current ayah's index within it.
    public var currentStep: (step: Int, verse: Int)? {
        currentItem.map { ($0.step, $0.index) }
    }

    public var totalPositions: Int {
        items.count
    }

    /// Whether the current ayah has a hidden word left to peek or hint.
    public var hasHiddenWord: Bool {
        guard let currentVerse else { return false }
        return revealedWords < wordCount(currentVerse)
    }

    /// The order can change until the first ayah is graded.
    public var canChangeOrder: Bool {
        recalls.isEmpty && (phase == .reciting || phase == .grading)
    }

    /// The current ayah's words to mark as mistakes.
    public var wordChoices: [WordChoice] {
        guard let currentVerse else { return [] }
        return (units[currentVerse] ?? []).map {
            WordChoice(text: $0.text, words: $0.words.filter { $0.verse == currentVerse }.map(\.wordNumber))
        }
        .filter { !$0.words.isEmpty }
    }

    public func start() async {
        do {
            let loaded = try await verseText.expectedWords.expectedWords(for: verses)
            for unit in loaded {
                for word in unit.words {
                    wordTexts[word] = word == unit.words.first ? unit.text : nil
                    wordCounts[word.verse] = max(wordCounts[word.verse] ?? 0, word.wordNumber)
                }
                if let verse = unit.words.first?.verse {
                    units[verse, default: []].append(unit)
                }
            }
            await restoreDraft()
            phase = .reciting
            updateMask()
        } catch {
            logger.error("Hifz practice: loading words failed. \(error)")
            phase = .failed
        }
    }

    public func setCueLevel(_ level: PracticeCueLevel) {
        cueLevel = level
        store.cueLevel = level
        updateMask()
    }

    public func setOrder(_ newOrder: PracticeOrder) {
        guard canChangeOrder, newOrder != order else { return }
        order = newOrder
        store.order = newOrder
        setSteps(PracticePlan.steps(for: verses, order: newOrder))
        moveTo(0)
    }

    /// Plays the current ayah repeated, with a pause after each to repeat it; again to stop. Counts as help.
    public func toggleListening() {
        guard phase == .reciting, let currentVerse else { return }
        if isListening {
            stopListeningIfNeeded()
        } else {
            // Starting playback first stops any earlier audio, which reports `audioStopped()` right away.
            listen(currentVerse)
            isListening = true
            assistance += 1
        }
    }

    /// The recitation audio stopped (it finished, failed, or something else stopped it).
    public func audioStopped() {
        isListening = false
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
        stopListeningIfNeeded()
        revealedWords = wordCount(currentVerse)
        hint = nil
        phase = .grading
        updateMask()
    }

    /// Asks which words were wrong before grading the ayah as recited with mistakes.
    public func markMistakes() {
        guard phase == .grading else { return }
        markedWords = []
        phase = .markingMistakes
    }

    public func toggleMistake(_ choice: WordChoice) {
        guard phase == .markingMistakes else { return }
        if markedWords.isSuperset(of: choice.words) {
            markedWords.subtract(choice.words)
        } else {
            markedWords.formUnion(choice.words)
        }
    }

    /// Grades the current ayah as recited with mistakes, with the marked words (possibly none).
    public func saveMistakes() async {
        guard phase == .markingMistakes else { return }
        phase = .grading
        await grade(.mistake)
    }

    /// Grades the current ayah, then moves to the next, or saves the session after the last.
    /// `.correct` with help used is recorded as `.hint`.
    public func grade(_ outcome: RecallOutcome) async {
        guard phase == .grading, let currentVerse else { return }
        let recorded: RecallOutcome = outcome == .correct && assistance > 0 ? .hint : outcome
        let mistakenWords = outcome == .mistake ? markedWords.sorted() : []
        recalls.append(VerseRecall(verse: currentVerse, outcome: recorded, assistance: assistance, mistakenWords: mistakenWords))
        resumed = false
        if position + 1 < items.count {
            moveTo(position + 1)
            saveDraft()
        } else {
            position = items.count
            updateMask()
            saveDraft()
            await save()
        }
    }

    /// Ends practice: the ayahs graded so far are saved as a session, the page shows every word again.
    public func end() async {
        stopListeningIfNeeded()
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

    private struct Item {
        let step: Int
        let index: Int
        let verse: AyahNumber
    }

    private let verseText: RecitationVerseText
    private let service: MemorizationService
    private let store: PracticeStateStore
    private let now: @Sendable () -> Date
    private let mask: (PracticeMask?) -> Void
    private let listen: (AyahNumber) -> Void
    private let stopListening: () -> Void
    private let close: () -> Void
    private var startedOn: Date

    private var wordTexts: [Word: String] = [:]
    private var wordCounts: [AyahNumber: Int] = [:]
    private var units: [AyahNumber: [ExpectedWordText]] = [:]
    private var assistance = 0
    private var recalls: [VerseRecall] = []
    private var saved = false

    private var items: [Item] = []

    private var currentItem: Item? {
        items.indices.contains(position) ? items[position] : nil
    }

    private static func items(of steps: [PracticeStep]) -> [Item] {
        steps.enumerated().flatMap { step, value in
            value.verses.enumerated().map { Item(step: step, index: $0, verse: $1) }
        }
    }

    private func setSteps(_ newSteps: [PracticeStep]) {
        steps = newSteps
        items = Self.items(of: newSteps)
    }

    private func wordCount(_ verse: AyahNumber) -> Int {
        wordCounts[verse] ?? 0
    }

    private func moveTo(_ newPosition: Int) {
        stopListeningIfNeeded()
        position = newPosition
        revealedWords = 0
        assistance = 0
        markedWords = []
        hint = nil
        phase = .reciting
        updateMask()
    }

    private func stopListeningIfNeeded() {
        if isListening {
            isListening = false
            stopListening()
        }
    }

    private func updateMask() {
        // Ayahs after the current one stay hidden; earlier ones, already recited, show.
        let current = currentVerse
        let later = current.map { current in verses.filter { $0 > current } } ?? []
        // While grading, the whole ayah shows, its end marker too (a glyph after its last word).
        let partialVerse = phase == .reciting ? current : nil
        let cues = (later + [partialVerse].compactMap { $0 }).flatMap { verse in
            cueLevel.cueWords(wordCount: wordCount(verse)).map { Word(verse: verse, wordNumber: $0) }
        }
        mask(PracticeMask(hiddenVerses: Set(later), partialVerse: partialVerse, revealedWords: revealedWords, cueWords: Set(cues)))
    }

    /// Picks up this passage's unsaved session; another passage's graded ayahs are saved as their own session.
    private func restoreDraft() async {
        guard let draft = store.draft else { return }
        if draft.passage == passage {
            order = draft.order
            setSteps(PracticePlan.steps(for: verses, order: order))
            position = min(draft.position, max(items.count - 1, 0))
            startedOn = draft.startedOn
            recalls = draft.recalls
            resumed = !recalls.isEmpty
            logger.info("Hifz practice: resumed at \(position) with \(recalls.count) graded")
        } else {
            if !draft.recalls.isEmpty {
                do {
                    try await service.recordSession(draft.passage, startedOn: draft.startedOn, recalls: draft.recalls)
                } catch {
                    logger.error("Hifz practice: saving an unfinished session failed. \(error)")
                    return
                }
            }
            store.clearDraft()
        }
    }

    private func saveDraft() {
        do {
            try store.saveDraft(PracticeDraft(passage: passage, order: order, position: position, startedOn: startedOn, recalls: recalls))
        } catch {
            logger.error("Hifz practice: keeping the draft failed. \(error)")
        }
    }

    private func save() async {
        do {
            try await service.recordSession(passage, startedOn: startedOn, recalls: recalls)
            saved = true
            store.clearDraft()
            phase = try await .finished(service.progress(of: passage))
        } catch {
            logger.error("Hifz practice: saving the session failed. \(error)")
            phase = .failed
        }
    }
}
