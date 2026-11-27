//
//  RecitationCheckViewModel.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Combine
import Foundation
import QuranKit
import RecitationRecognition
import VLogging

/// Recite and check (roadmap V3a): the person recites a passage from memory, stops, and sees which
/// words they left out or said differently. The recording is checked once, then dropped; nothing is
/// stored.
@MainActor
public final class RecitationCheckViewModel: ObservableObject {
    // MARK: Lifecycle

    /// `verses`: the passage, in order.
    public init(loader: RecitationEngineLoader, microphone: RecitationMicrophone, verses: [AyahNumber]) {
        self.loader = loader
        self.microphone = microphone
        self.verses = verses
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
        /// The unit's worst mark (a unit is usually one word).
        public let mark: CheckedWord.Mark
        /// The verse this unit ends, for the verse-number marker after it.
        public let endsVerse: AyahNumber?
    }

    /// The longest recording checked: about two pages at a usual pace. Recording stops and is
    /// checked when it is reached.
    public static let maximumSeconds = 300.0

    @Published public private(set) var state: State = .preparing
    @Published public var failure: Failure?

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
        } catch {
            logger.error("Recitation check: recognition failed: \(error)")
            state = .failed
        }
    }

    // MARK: Private

    private let loader: RecitationEngineLoader
    private let microphone: RecitationMicrophone
    private var recognizer: RecitationRecognizer?
    private var passageWords: [ExpectedWordText] = []
    private var listeningTask: Task<Void, Never>?

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
}
