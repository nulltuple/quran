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

/// Hifz practice on the page (roadmap H2, V2b): the passage's words are hidden, except the chosen
/// cue words; the person recites each ayah from memory (straight through, or cumulatively), may
/// turn on live recitation to reveal words and advance automatically with the practice range as
/// the prior, listen to an ayah repeated, ask for its next word's first letter or the word itself,
/// check it, and grade it manually at any time (manual override always wins). Graded and
/// auto-advanced ayahs are kept as a draft after every ayah, so practice resumes after the app is
/// killed, and saved as one session (H1).
@MainActor
@Observable
public final class HifzPracticeViewModel {
    // MARK: Lifecycle

    /// `mask` shows the hidden words on the page (nil restores it); `listen` plays an ayah repeated
    /// with pauses to repeat it, `stopListening` stops it; `close` removes the controls.
    public init(
        passage: Passage,
        loader: RecitationEngineLoader,
        microphone: RecitationMicrophone,
        service: MemorizationService,
        store: PracticeStateStore,
        now: @escaping @Sendable () -> Date = Date.init,
        mask: @escaping (PracticeMask?) -> Void,
        listen: @escaping (AyahNumber) -> Void,
        stopListening: @escaping () -> Void,
        onHistoryChanged: (() -> Void)? = nil,
        toggleReaderMode: (() -> Void)? = nil,
        close: @escaping () -> Void
    ) {
        self.passage = passage
        verses = passage.verses
        self.loader = loader
        self.microphone = microphone
        self.service = service
        self.store = store
        self.now = now
        self.mask = mask
        self.listen = listen
        self.stopListening = stopListening
        self.onHistoryChanged = onHistoryChanged
        toggleReaderModeHandler = toggleReaderMode
        self.close = close
        let order = store.order
        self.order = order
        cueLevel = store.cueLevel
        startedOn = now()
        let steps = PracticePlan.steps(for: passage.verses, order: order)
        self.steps = steps
        items = Self.items(of: steps)
    }

    deinit {
        liveRecitationTask?.cancel()
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

    /// Live recitation status inside Practice (roadmap V2b).
    public enum LiveRecitationState: Equatable {
        case off
        case preparing
        /// The model is not on this device; downloading it takes `byteCount` bytes.
        case needsModel(byteCount: Int64)
        case downloading(progress: Double)
        /// Microphone is on and revealing recited words in the current ayah.
        case listening
        /// Recitation continues but has not matched the current ayah for several windows.
        case offTrack
        /// Microphone stopped automatically after `liveSilenceLimit` without speech.
        case stoppedAfterSilence
        /// The model failed to load.
        case failed
    }

    public enum LiveRecitationFailure: Equatable {
        case downloadFailed
        case microphoneDenied
        case microphoneUnavailable
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
    /// Recognized audio per live update: 16 s rolling buffer trimmed at a quiet pause boundary to ~14 s.
    public static let liveWindowSeconds = 16.0
    /// Time between the starts of two live recognition updates (low-latency live reveal & checking).
    public static let liveHop = Duration.milliseconds(300)
    /// Silence after which the live practice microphone stops.
    public static let liveSilenceLimit: TimeInterval = 60

    public var usesLinePage = false
    /// Whether the reader behind Practice is currently showing Translation mode instead of Mushaf pages.
    public var isTranslationMode = false
    /// Whether live recitation mistakes are highlighted directly on revealed words of the Mushaf.
    public var highlightLiveMistakes = true {
        didSet { updateMask() }
    }

    /// Mistakes detected live during recitation in this session, in passage order.
    public private(set) var liveMistakes: [LivePracticeMistake] = []
    /// Most recently recited or manually revealed canonical word (drives the green moving cursor).
    public private(set) var activeWord: Word?
    /// Next still-hidden canonical word where a live stumble was detected (drives the red baseline).
    public private(set) var pendingMistakeWord: Word?
    /// Timestamp when the current live microphone session started (drives the compact timer chip).
    public private(set) var liveRecitationStartedAt: Date?
    private(set) var showsMeaning = false

    public var canToggleReaderMode: Bool {
        toggleReaderModeHandler != nil
    }

    public func toggleReaderMode() {
        toggleReaderModeHandler?()
    }

    /// Accuracy percentage across words revealed so far in this session, or nil before any word is revealed.
    public var liveAccuracyPercent: Int? {
        let revealedTotal = totalSessionRevealedWords
        guard revealedTotal > 0 else { return nil }
        let clean = max(0, revealedTotal - liveMistakes.count)
        return Int((Double(clean) / Double(revealedTotal) * 100.0).rounded())
    }

    /// Disputes and removes a live-detected mistake, immediately updating the Mushaf highlights and
    /// any already-recorded verse recall in this session.
    public func disputeLiveMistake(_ mistake: LivePracticeMistake) {
        liveMistakes.removeAll { $0.word == mistake.word }
        disputedWords.insert(mistake.word)
        liveTracker?.removeMistake(for: mistake.word)
        for index in recalls.indices where recalls[index].verse == mistake.word.verse {
            let remaining = recalls[index].mistakenWords.filter { $0 != mistake.word.wordNumber }
            let outcome: RecallOutcome = if !remaining.isEmpty {
                .mistake
            } else if recalls[index].assistance > 0 {
                .hint
            } else {
                .correct
            }
            recalls[index] = VerseRecall(
                verse: recalls[index].verse,
                outcome: outcome,
                assistance: recalls[index].assistance,
                mistakenWords: remaining,
                provenance: recalls[index].provenance
            )
        }
        updateMask()
    }

    public func revealMeaning(for verse: AyahNumber) {
        guard verse == currentVerse, phase == .reciting, !showsMeaning else { return }
        showsMeaning = true
        assistance += 1
        updateMask()
    }

    /// Line scans have ayah coordinates only. Present canonical word cues separately from the scan.
    var linePageCues: String? {
        guard usesLinePage, phase == .reciting, let verse = currentVerse else { return nil }
        let cues = Set(cueLevel.cueWords(wordCount: wordCount(verse)))
        guard !cues.isEmpty || revealedWords > 0 else { return nil }
        return wordChoices.map { choice in
            choice.words.contains { $0 <= revealedWords || cues.contains($0) } ? choice.text : "…"
        }.joined(separator: " ")
    }

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
    /// Live recitation state (V2b): off during manual practice.
    public private(set) var liveRecitationState: LiveRecitationState = .off
    public var liveRecitationFailure: LiveRecitationFailure?

    public var isLiveReciting: Bool {
        switch liveRecitationState {
        case .listening, .offTrack: true
        default: false
        }
    }

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
            let loaded = try await loader.verseText.expectedWords.expectedWords(for: verses)
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
        if isLiveReciting {
            rebuildLiveTracker()
            microphone.clearBuffer()
        }
    }

    /// Plays the current ayah repeated, with a pause after each to repeat it; again to stop. Counts as help.
    public func toggleListening() {
        guard phase == .reciting, let currentVerse else { return }
        if isListening {
            stopListeningIfNeeded()
        } else {
            // The microphone and recitation playback never run together.
            stopLiveRecitation()
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

    /// Starts or stops hands-free live recitation reveal in Practice (roadmap V2b).
    public func toggleLiveRecitation() async {
        guard phase == .reciting else { return }
        switch liveRecitationState {
        case .listening, .offTrack:
            stopLiveRecitation()
        case .needsModel:
            liveRecitationState = .off
        case .preparing, .downloading:
            return
        case .off, .stoppedAfterSilence, .failed:
            await startLiveRecitation()
        }
    }

    /// Downloads the recitation model from the inline prompt when missing.
    public func downloadRecitationModel() async {
        guard case .needsModel = liveRecitationState else { return }
        liveRecitationState = .downloading(progress: 0)
        do {
            try await loader.download { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = liveRecitationState else { return }
                    liveRecitationState = .downloading(progress: progress)
                }
            }
        } catch {
            logger.error("Hifz practice: model download failed: \(error)")
            liveRecitationState = .needsModel(byteCount: loader.downloadByteCount)
            liveRecitationFailure = .downloadFailed
            return
        }
        liveRecitationState = .preparing
        if await prepareRecognizer(), phase == .reciting {
            // Wait for the person to tap Recite when ready to speak, matching V1 and V2a.
            liveRecitationState = .off
        }
    }

    /// Stops live recitation and its microphone while keeping Practice open.
    public func stopLiveRecitation() {
        let wasActive = isLiveReciting || liveRecitationTask != nil || microphone.isRecording
        liveRecitationTask?.cancel()
        liveRecitationTask = nil
        _ = try? microphone.stop()
        liveTracker = nil
        liveRecitationStartedAt = nil
        pendingMistakeWord = nil
        if isLiveReciting || liveRecitationState == .preparing {
            liveRecitationState = .off
        }
        if wasActive {
            updateMask()
            logger.info("Hifz practice: live recitation stopped")
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

    /// Shows the next hidden word; counts as help. Manual override always wins over live recitation.
    public func revealNextWord() {
        guard phase == .reciting, let currentVerse, hasHiddenWord else { return }
        revealedWords += 1
        activeWord = Word(verse: currentVerse, wordNumber: revealedWords)
        pendingMistakeWord = nil
        hint = nil
        assistance += 1
        liveTracker?.sync(verse: currentVerse, revealedWords: revealedWords)
        updateMask()
    }

    /// Shows the whole ayah to compare with what was recited. Manual override stops live recitation.
    public func check() {
        guard phase == .reciting, let currentVerse else { return }
        stopLiveRecitation()
        stopListeningIfNeeded()
        revealedWords = wordCount(currentVerse)
        activeWord = nil
        pendingMistakeWord = nil
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
        recalls.append(VerseRecall(
            verse: currentVerse,
            outcome: recorded,
            assistance: assistance,
            mistakenWords: mistakenWords,
            provenance: .manual
        ))
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
        stopLiveRecitation()
        recognizer = nil
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

    /// Loads the recognizer; false when the model is missing (offers download) or fails to load.
    func prepareRecognizer() async -> Bool {
        if recognizer != nil {
            return true
        }
        do {
            guard let loaded = try await loader.load() else {
                liveRecitationState = .needsModel(byteCount: loader.downloadByteCount)
                return false
            }
            recognizer = loaded
            return true
        } catch {
            logger.error("Hifz practice: model failed to load: \(error)")
            liveRecitationState = .failed
            return false
        }
    }

    /// Starts live tracking for the current practice stretch; the caller feeds windows (microphone or test).
    func beginLiveRecitation() {
        rebuildLiveTracker()
        speechLevel = SpeechLevel()
        let timestamp = now()
        lastSpeech = timestamp
        liveRecitationStartedAt = timestamp
        liveRecitationState = .listening
    }

    /// Recognizes one 16 kHz mono window and reveals/advances the current practice stretch.
    func followLiveRecitation(_ samples: [Float]) async {
        guard let recognizer, liveTracker != nil else { return }
        let anchored = RecitationAudio.quietAnchoredWindow(samples)
        let isAcousticSpeech = speechLevel.isSpeech(window: anchored)
        let normalized = RecitationAudio.normalizeForRecognition(anchored)
        let words: [RecognizedWord]
        do {
            words = try await recognizer.recognizeWords(normalized)
        } catch {
            if !(error is CancellationError) {
                logger.error("Hifz practice: live recognition failed: \(error)")
            }
            return
        }
        // Manual override (`check`, `stopLiveRecitation`, `end`, `toggleListening`) may have happened
        // while Core ML was running: drop any stale window.
        guard isLiveReciting, phase == .reciting, var tracker = liveTracker else { return }
        let hasConfidentSpeech = words.contains { ($0.meanConfidence ?? 1) >= 0.60 }
        let isSpeaking = isAcousticSpeech || hasConfidentSpeech
        let update = tracker.update(with: words, isSpeaking: isSpeaking)
        liveTracker = tracker
        if isSpeaking || !update.completedVerses.isEmpty || update.revealedWords > revealedWords {
            lastSpeech = now()
        }
        liveRecitationState = update.isOffTrack ? .offTrack : .listening
        mergeLiveMistakes(update.liveMistakes)
        if let currentWord = update.currentWord {
            activeWord = currentWord
        }
        pendingMistakeWord = update.pendingMistakeWord

        var crossedStepBoundary = false
        for completedVerse in update.completedVerses {
            guard completedVerse == currentVerse else { break }
            let verseMistakes = liveMistakes
                .filter { $0.word.verse == completedVerse }
                .map(\.word.wordNumber)
                .sorted()
            let outcome: RecallOutcome = if !verseMistakes.isEmpty {
                .mistake
            } else if assistance > 0 {
                .hint
            } else {
                .correct
            }
            recalls.append(VerseRecall(
                verse: completedVerse,
                outcome: outcome,
                assistance: assistance,
                mistakenWords: verseMistakes,
                provenance: .model
            ))
            resumed = false
            if position + 1 < items.count {
                let previousStep = currentItem?.step
                position += 1
                revealedWords = 0
                assistance = 0
                showsMeaning = false
                markedWords = []
                hint = nil
                saveDraft()
                if order == .cumulative, currentItem?.step != previousStep {
                    activeWord = nil
                    pendingMistakeWord = nil
                    rebuildLiveTracker()
                    microphone.clearBuffer()
                    crossedStepBoundary = true
                    break
                }
            } else {
                position = items.count
                activeWord = nil
                pendingMistakeWord = nil
                stopLiveRecitation()
                updateMask()
                saveDraft()
                await save()
                return
            }
        }

        if !crossedStepBoundary, update.revealedWords > revealedWords {
            revealedWords = update.revealedWords
            hint = nil
        }
        updateMask()
    }

    // MARK: Private

    private struct Item {
        let step: Int
        let index: Int
        let verse: AyahNumber
    }

    private let loader: RecitationEngineLoader
    private let microphone: RecitationMicrophone
    private let service: MemorizationService
    private let store: PracticeStateStore
    private let now: @Sendable () -> Date
    private let mask: (PracticeMask?) -> Void
    private let listen: (AyahNumber) -> Void
    private let stopListening: () -> Void
    private let onHistoryChanged: (() -> Void)?
    private let toggleReaderModeHandler: (() -> Void)?
    private let close: () -> Void
    private var startedOn: Date

    private var wordTexts: [Word: String] = [:]
    private var wordCounts: [AyahNumber: Int] = [:]
    private var units: [AyahNumber: [ExpectedWordText]] = [:]
    private var disputedWords: Set<Word> = []
    private var assistance = 0
    private var recalls: [VerseRecall] = []
    private var saved = false

    private var items: [Item] = []
    private var recognizer: RecitationRecognizer?
    private var liveTracker: PracticeRecitationTracker?
    @ObservationIgnored private nonisolated(unsafe) var liveRecitationTask: Task<Void, Never>?
    private var speechLevel = SpeechLevel()
    private var lastSpeech = Date()

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

    private func startLiveRecitation() async {
        stopListeningIfNeeded()
        if recognizer == nil {
            liveRecitationState = .preparing
            guard await prepareRecognizer(), phase == .reciting else { return }
        }
        do {
            try await microphone.start()
        } catch {
            logger.error("Hifz practice: microphone failed to start: \(error)")
            liveRecitationState = .off
            liveRecitationFailure = (error as? RecitationMicrophoneError) == .permissionDenied ? .microphoneDenied : .microphoneUnavailable
            return
        }
        guard phase == .reciting else {
            _ = try? microphone.stop()
            return
        }
        beginLiveRecitation()
        logger.info("Hifz practice: live recitation started at \(currentVerse?.nonLocalizedDescription ?? "none")")
        liveRecitationTask = Task { [weak self] in
            let clock = ContinuousClock()
            var lastGeneration = -1
            while !Task.isCancelled {
                let started = clock.now
                guard let self, isLiveReciting, phase == .reciting else { return }
                let generation = microphone.sampleGeneration
                if generation != lastGeneration {
                    lastGeneration = generation
                    do {
                        let samples = try microphone.recentSamples(seconds: Self.liveWindowSeconds)
                        if samples.count >= RecitationAudio.sampleRate / 5 {
                            await followLiveRecitation(samples)
                        }
                    } catch {
                        logger.error("Hifz practice: live audio read failed: \(error)")
                    }
                }
                guard isLiveReciting, phase == .reciting else { return }
                if now().timeIntervalSince(lastSpeech) > Self.liveSilenceLimit {
                    // This task stops itself, so it must not cancel its own handle (V1 trail, Decisions).
                    liveRecitationTask = nil
                    _ = try? microphone.stop()
                    liveTracker = nil
                    liveRecitationStartedAt = nil
                    pendingMistakeWord = nil
                    liveRecitationState = .stoppedAfterSilence
                    updateMask()
                    logger.info("Hifz practice: live recitation stopped after silence")
                    return
                }
                try? await clock.sleep(until: started + Self.liveHop)
            }
        }
    }

    /// Builds a tracker over the current monotonic stretch: all remaining ayahs in straight order,
    /// or the remaining ayahs of the current step in cumulative order.
    private func rebuildLiveTracker() {
        guard let currentItem else {
            liveTracker = nil
            return
        }
        let stretchItems: ArraySlice<Item> = switch order {
        case .straight:
            items[position...]
        case .cumulative:
            items[position...].prefix { $0.step == currentItem.step }
        }
        let stretchUnits = stretchItems.flatMap { units[$0.verse] ?? [] }
        var tracker = PracticeRecitationTracker(expected: stretchUnits)
        if revealedWords > 0 {
            tracker.sync(verse: currentItem.verse, revealedWords: revealedWords)
        }
        liveTracker = tracker
    }

    private func moveTo(_ newPosition: Int) {
        stopListeningIfNeeded()
        position = newPosition
        revealedWords = 0
        activeWord = nil
        pendingMistakeWord = nil
        assistance = 0
        showsMeaning = false
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

    private var totalSessionRevealedWords: Int {
        var total = 0
        for index in 0 ..< min(position, items.count) {
            total += wordCount(items[index].verse)
        }
        total += revealedWords
        return total
    }

    private func mergeLiveMistakes(_ incoming: [LivePracticeMistake]) {
        guard !incoming.isEmpty else { return }
        var byWord = Dictionary(uniqueKeysWithValues: liveMistakes.map { ($0.word, $0) })
        var changed = false
        for mistake in incoming where !disputedWords.contains(mistake.word) {
            if byWord[mistake.word] == nil {
                byWord[mistake.word] = mistake
                changed = true
            }
        }
        if changed {
            liveMistakes = byWord.values.sorted { $0.word < $1.word }
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
        let mistakes: Set<Word> = highlightLiveMistakes ? Set(liveMistakes.map(\.word)) : []
        let active: Word? = phase == .reciting ? activeWord : nil
        let pending: Word? = (phase == .reciting && highlightLiveMistakes) ? pendingMistakeWord : nil
        var next = PracticeMask(
            hiddenVerses: Set(later),
            partialVerse: partialVerse,
            revealedWords: revealedWords,
            cueWords: Set(cues),
            mistakeWords: mistakes,
            activeWord: active,
            pendingMistakeWord: pending
        )
        next.checkedVerse = partialVerse == nil ? current : nil
        next.showsMeaning = showsMeaning && partialVerse != nil
        mask(next)
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
            onHistoryChanged?()
            phase = try await .finished(service.progress(of: passage))
        } catch {
            logger.error("Hifz practice: saving the session failed. \(error)")
            phase = .failed
        }
    }
}
