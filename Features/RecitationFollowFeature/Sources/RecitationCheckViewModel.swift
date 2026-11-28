//
//  RecitationCheckViewModel.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Combine
import Foundation
import MemorizationPersistence
import MemorizationService
import QuranKit
import RecitationRecognition
import VLogging

/// How Recite to Check presents mistakes (roadmap V3b).
public enum RecitationCheckPolicy: String, CaseIterable, Hashable, Sendable {
    /// Displays mistake marks and notes, records confirmed mistakes into H7 history, and offers inline dispute.
    case showMistakes
    /// Records confirmed mistakes into H7 history silently without showing mistake marks during the check.
    case silent
}

/// Recite and check (roadmap V3a + V3b): the person recites a passage from memory, stops, and sees
/// which words they left out or said differently (or records silently under the silent policy).
/// Confirmed mistakes are recorded as `.model` `RecallEvidence` for H7's heatmap, with inline dispute.
@MainActor
public final class RecitationCheckViewModel: ObservableObject {
    // MARK: Lifecycle

    /// `verses`: the passage, in order.
    public init(
        loader: RecitationEngineLoader,
        microphone: RecitationMicrophone,
        verses: [AyahNumber],
        memorizationService: MemorizationService? = nil,
        policy: RecitationCheckPolicy = .showMistakes,
        onHistoryChanged: (() -> Void)? = nil
    ) {
        self.loader = loader
        self.microphone = microphone
        self.verses = verses
        self.memorizationService = memorizationService
        self.policy = policy
        self.onHistoryChanged = onHistoryChanged
    }

    deinit {
        listeningTask?.cancel()
    }

    // MARK: Public

    public enum State: Equatable {
        case preparing
        case needsModel(byteCount: Int64)
        case downloading(progress: Double)
        /// The passage is loaded; waiting for the person to start.
        case ready
        case listening
        case checking
        case checked(RecitationCheck)
        case failed
    }

    public enum Failure: Equatable {
        case downloadFailed
        case microphoneDenied
        case microphoneUnavailable
    }

    /// A unit of the passage's text as the result shows it.
    public struct CheckedText: Equatable, Identifiable {
        public let id: Int
        public let text: String
        /// The verse the unit is in.
        public let verse: AyahNumber
        /// Canonical word numbers covered by this unit (usually one).
        public let wordNumbers: [Int]
        /// The unit's worst mark (a unit is usually one word).
        public let mark: CheckedWord.Mark
        /// The verse this unit ends, for the verse-number marker after it.
        public let endsVerse: AyahNumber?
    }

    /// One confirmed mistake from the latest check that was recorded as `.model` evidence and can be disputed.
    public struct RecordedMistakeItem: Equatable, Identifiable {
        public enum Kind: Equatable {
            case skippedVerse
            case omitted(wordText: String)
            case substituted(recited: String, expected: String)
        }

        public let id: String
        public let verse: AyahNumber
        public let wordNumbers: [Int]
        public let kind: Kind
        public let evidenceIDs: [UUID]
        public var isDisputed: Bool
    }

    /// The longest recording checked: about two pages at a usual pace. Recording stops and is
    /// checked when it is reached.
    public static let maximumSeconds = 300.0

    @Published public private(set) var state: State = .preparing
    @Published public var failure: Failure?
    @Published public var policy: RecitationCheckPolicy
    @Published public private(set) var recordedMistakes: [RecordedMistakeItem] = []
    @Published public private(set) var recordedSessionID: UUID?
    @Published public private(set) var recordedReachedVerseCount = 0
    @Published public private(set) var recordSaveFailed = false

    public let verses: [AyahNumber]

    /// The passage recite and check offers for an ayah-menu selection: the selected verses, or for
    /// a single verse, that verse to the end of its page (a usual memorization portion), within its
    /// sura.
    public static func passage(for selection: [AyahNumber]) -> [AyahNumber] {
        let sorted = selection.sorted()
        guard sorted.count == 1, let verse = sorted.first else {
            return sorted
        }
        return verse.page.verses.filter { $0 >= verse && $0.sura == verse.sura }
    }

    /// Converts a `RecitationCheck` into H1 `VerseRecall` entries with `.model` provenance.
    ///
    /// Rules:
    /// - Unreached verses (every word `.notReached`) are excluded.
    /// - Skipped verses become an ayah-level `.mistake` (`word == 0`) with `.model` provenance.
    /// - Verses with confirmed word mistakes (`.omitted` or `.substituted`) record `.mistake` with those exact word numbers.
    /// - Verses with `.uncertain` or partially reached words and no confirmed mistakes record `.skipped`
    ///   (never a mistake, never a clean recall that would falsely decay prior heat).
    /// - Verses where every word is `.correct` record `.correct` with `.model` provenance.
    public static func recalls(from check: RecitationCheck) -> [VerseRecall] {
        guard !check.words.isEmpty else { return [] }
        let skippedSet = Set(check.skippedVerses)
        var orderedVerses: [AyahNumber] = []
        var wordsByVerse: [AyahNumber: [CheckedWord]] = [:]
        for item in check.words {
            let verse = item.word.verse
            if wordsByVerse[verse] == nil {
                orderedVerses.append(verse)
            }
            wordsByVerse[verse, default: []].append(item)
        }

        var result: [VerseRecall] = []
        for verse in orderedVerses {
            let verseWords = wordsByVerse[verse] ?? []
            guard !verseWords.isEmpty else { continue }
            if verseWords.allSatisfy({ $0.mark == .notReached }) {
                continue
            }
            if skippedSet.contains(verse) {
                result.append(VerseRecall(verse: verse, outcome: .mistake, assistance: 0, mistakenWords: [], provenance: .model))
                continue
            }
            let mistakenWords = Array(Set(verseWords.filter(\.isMistake).map(\.word.wordNumber))).sorted()
            if !mistakenWords.isEmpty {
                result.append(
                    VerseRecall(
                        verse: verse,
                        outcome: .mistake,
                        assistance: 0,
                        mistakenWords: mistakenWords,
                        provenance: .model
                    )
                )
            } else if verseWords.allSatisfy({ $0.mark == .correct }) {
                result.append(VerseRecall(verse: verse, outcome: .correct, assistance: 0, mistakenWords: [], provenance: .model))
            } else {
                // Uncertain or partially reached verse: neither a confirmed mistake nor a clean recall.
                result.append(VerseRecall(verse: verse, outcome: .skipped, assistance: 0, mistakenWords: [], provenance: .model))
            }
        }
        return result
    }

    /// The passage's text with each unit's mark, once checked; every unit `.notReached` before.
    public var checkedTexts: [CheckedText] {
        let marks: [Word: CheckedWord.Mark] = if case .checked(let check) = state {
            Dictionary(check.words.map { ($0.word, $0.mark) }, uniquingKeysWith: { first, _ in first })
        } else {
            [:]
        }
        return passageWords.enumerated().map { index, unit in
            let unitMarks = unit.words.map { marks[$0] ?? .notReached }
            let next = passageWords.indices.contains(index + 1) ? passageWords[index + 1].words.first?.verse : nil
            let verse = unit.words[unit.words.count - 1].verse
            return CheckedText(
                id: index,
                text: unit.text,
                verse: verse,
                wordNumbers: unit.words.map(\.wordNumber),
                mark: unitMarks.max { Self.severity($0) < Self.severity($1) } ?? .notReached,
                endsVerse: next == verse ? nil : verse
            )
        }
    }

    /// Loads the model and the passage's words, then waits for Start.
    public func start() async {
        guard state == .preparing else { return }
        if await prepare() {
            state = .ready
        }
    }

    public func download() async {
        guard case .needsModel = state else { return }
        state = .downloading(progress: 0)
        do {
            try await loader.download { progress in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = state else { return }
                    state = .downloading(progress: progress)
                }
            }
        } catch {
            logger.error("Recitation check: model download failed: \(error)")
            state = .needsModel(byteCount: loader.downloadByteCount)
            failure = .downloadFailed
            return
        }
        state = .preparing
        if await prepare() {
            state = .ready
        }
    }

    public func startListening() async {
        guard state == .ready || isChecked else { return }
        do {
            try await microphone.start()
        } catch {
            logger.error("Recitation check: microphone failed to start: \(error)")
            failure = (error as? RecitationMicrophoneError) == .permissionDenied ? .microphoneDenied : .microphoneUnavailable
            return
        }
        logger.info("Recitation check: listening, \(verses.count) verses")
        checkStartedOn = Date()
        recordedMistakes = []
        recordedSessionID = nil
        recordedEvidence = []
        recordedReachedVerseCount = 0
        recordSaveFailed = false
        state = .listening
        listeningTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumSeconds))
            guard !Task.isCancelled, let self else { return }
            // This task stops itself, so it must not cancel its own handle (V1 trail, Decisions).
            listeningTask = nil
            await finishListening()
        }
    }

    /// Stops recording and checks the recitation.
    public func stopAndCheck() async {
        listeningTask?.cancel()
        listeningTask = nil
        await finishListening()
    }

    /// Stops the microphone without checking (the sheet closed).
    public func stop() {
        listeningTask?.cancel()
        listeningTask = nil
        _ = try? microphone.stop()
        if state == .listening {
            state = .ready
        }
    }

    /// Disputes one recorded `.model` mistake from the latest check, retracting its evidence
    /// (and the companion ayah-level `.mistake` when all word mistakes in that verse are disputed)
    /// and notifying listeners so H7's heatmap recomputes immediately.
    public func dispute(_ item: RecordedMistakeItem) async {
        guard let index = recordedMistakes.firstIndex(where: { $0.id == item.id }),
              !recordedMistakes[index].isDisputed
        else {
            return
        }
        guard let memorizationService else {
            recordedMistakes[index].isDisputed = true
            return
        }

        var idsToRetract = Set(item.evidenceIDs)
        if !item.wordNumbers.isEmpty {
            let otherActiveWordMistakesInVerse = recordedMistakes.contains { other in
                other.id != item.id && other.verse == item.verse && !other.wordNumbers.isEmpty && !other.isDisputed
            }
            if !otherActiveWordMistakesInVerse {
                let verseKey = MemorizationVerse(sura: item.verse.sura.suraNumber, ayah: item.verse.ayah)
                let companionAyahIDs = recordedEvidence
                    .filter { $0.verse == verseKey && $0.word == 0 && $0.outcome == .mistake }
                    .map(\.id)
                idsToRetract.formUnion(companionAyahIDs)
            }
        }

        do {
            try await memorizationService.retractEvidence(withIDs: idsToRetract)
            recordedMistakes[index].isDisputed = true
            onHistoryChanged?()
        } catch {
            logger.error("Recitation check: failed to dispute mistake \(item.id): \(error)")
            recordSaveFailed = true
        }
    }

    // MARK: Internal

    /// Loads the recognizer and the passage's words; false when the model is missing (the state
    /// offers the download) or something failed to load.
    func prepare() async -> Bool {
        do {
            if recognizer == nil {
                guard let recognizer = try await loader.load() else {
                    state = .needsModel(byteCount: loader.downloadByteCount)
                    return false
                }
                self.recognizer = recognizer
            }
            if passageWords.isEmpty {
                passageWords = try await loader.verseText.expectedWords.expectedWords(for: verses)
            }
            return true
        } catch {
            logger.error("Recitation check: failed to prepare: \(error)")
            state = .failed
            return false
        }
    }

    /// Checks `samples` (16 kHz mono: the microphone's recording, or a test's).
    func check(_ samples: [Float]) async {
        guard let recognizer else { return }
        state = .checking
        do {
            let words = try await recognizer.recognizeWords(samples)
            let result = RecitationChecker().check(words, against: passageWords)
            logger.info("Recitation check: \(words.count) words recited, \(result.mistakes.count) mistakes")
            state = .checked(result)
            await recordCheckResult(result)
        } catch {
            logger.error("Recitation check: recognition failed: \(error)")
            state = .failed
        }
    }

    // MARK: Private

    private let loader: RecitationEngineLoader
    private let microphone: RecitationMicrophone
    private let memorizationService: MemorizationService?
    private let onHistoryChanged: (() -> Void)?
    private var recognizer: RecitationRecognizer?
    private var passageWords: [ExpectedWordText] = []
    private var listeningTask: Task<Void, Never>?
    private var checkStartedOn: Date?
    private var recordedEvidence: [RecallEvidenceRecord] = []

    private var isChecked: Bool {
        if case .checked = state {
            true
        } else {
            false
        }
    }

    private static func severity(_ mark: CheckedWord.Mark) -> Int {
        switch mark {
        case .correct: 0
        case .notReached: 1
        case .uncertain: 2
        case .substituted: 3
        case .omitted: 4
        }
    }

    private func finishListening() async {
        guard state == .listening else { return }
        let samples: [Float]
        do {
            samples = try microphone.stop()
        } catch {
            logger.error("Recitation check: recording failed: \(error)")
            state = .failed
            return
        }
        await check(samples)
    }

    private func recordCheckResult(_ check: RecitationCheck) async {
        let recalls = Self.recalls(from: check)
        recordedReachedVerseCount = recalls.count
        var savedEvidence: [RecallEvidenceRecord] = []

        if let memorizationService, let first = verses.first, let last = verses.last, !recalls.isEmpty {
            do {
                let recorded = try await memorizationService.recordSessionWithEvidence(
                    Passage(first, last),
                    startedOn: checkStartedOn ?? Date(),
                    recalls: recalls
                )
                recordedSessionID = recorded.sessionID
                recordedEvidence = recorded.evidence
                savedEvidence = recorded.evidence
                recordSaveFailed = false
                onHistoryChanged?()
            } catch {
                logger.error("Recitation check: failed to save model evidence: \(error)")
                recordSaveFailed = true
            }
        }

        recordedMistakes = buildRecordedMistakeItems(from: check, evidence: savedEvidence)
    }

    private func buildRecordedMistakeItems(
        from check: RecitationCheck,
        evidence: [RecallEvidenceRecord]
    ) -> [RecordedMistakeItem] {
        var items: [RecordedMistakeItem] = []
        let skippedSet = Set(check.skippedVerses)

        for verse in check.skippedVerses {
            let verseKey = MemorizationVerse(sura: verse.sura.suraNumber, ayah: verse.ayah)
            let ids = evidence
                .filter { $0.verse == verseKey && $0.word == 0 && $0.outcome == .mistake }
                .map(\.id)
            items.append(
                RecordedMistakeItem(
                    id: "skip-\(verse.sura.suraNumber)-\(verse.ayah)",
                    verse: verse,
                    wordNumbers: [],
                    kind: .skippedVerse,
                    evidenceIDs: ids,
                    isDisputed: false
                )
            )
        }

        for text in checkedTexts {
            guard !skippedSet.contains(text.verse) else { continue }
            let kind: RecordedMistakeItem.Kind? = switch text.mark {
            case .omitted: .omitted(wordText: text.text)
            case .substituted(let recited): .substituted(recited: recited, expected: text.text)
            case .correct, .uncertain, .notReached: nil
            }
            guard let kind else { continue }
            let verseKey = MemorizationVerse(sura: text.verse.sura.suraNumber, ayah: text.verse.ayah)
            let wordSet = Set(text.wordNumbers)
            let ids = evidence
                .filter { $0.verse == verseKey && wordSet.contains($0.word) && $0.outcome == .mistake }
                .map(\.id)
            items.append(
                RecordedMistakeItem(
                    id: "word-\(text.verse.sura.suraNumber)-\(text.verse.ayah)-\(text.id)",
                    verse: text.verse,
                    wordNumbers: text.wordNumbers,
                    kind: kind,
                    evidenceIDs: ids,
                    isDisputed: false
                )
            )
        }
        return items
    }
}
