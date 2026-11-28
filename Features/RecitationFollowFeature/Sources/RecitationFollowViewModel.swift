//
//  RecitationFollowViewModel.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import QuranKit
import RecitationRecognition
import VLogging

/// Live recitation follow in the reader (roadmap V2a): while the person recites, the microphone's
/// latest `windowSeconds` are recognized every `hop`, `RecitationFollower` finds the place in the
/// expected text from the page in view onward, and the reader highlights the recited word with the
/// path recitation audio uses, turning pages as the reciter moves on.
///
/// When the follower loses the place, the window is matched against the whole Quran; a trusted
/// match restarts following at its page. Turning the page while the place is not found restarts
/// following there. Nothing recorded is kept: the microphone holds only the latest seconds, in
/// memory. A minute without speech (`SpeechLevel`) stops the microphone.
@MainActor
public final class RecitationFollowViewModel: ObservableObject {
    public enum State: Equatable {
        case preparing
        /// The model is not on this device; downloading it takes `byteCount` bytes.
        case needsModel(byteCount: Int64)
        case downloading(progress: Double)
        /// Ready to listen (after a download, or after the microphone failed to start).
        case ready
        /// Listening; the place has not been found yet.
        case listening
        /// Following the reciter in `verse`.
        case following(AyahNumber)
        /// Recitation goes on but doesn't fit the text near the last place.
        case lost
        /// The microphone stopped after `silenceLimit` without recitation.
        case stoppedAfterSilence
        /// The model failed to load.
        case failed
    }

    public enum Failure: Equatable {
        case downloadFailed
        case microphoneDenied
        case microphoneUnavailable
    }

    // MARK: Lifecycle

    /// `pages`: the pages in view, where the reciter is expected to start. `highlight` shows the
    /// recited word (nil clears it); `close` removes the follow controls from the reader.
    public init(
        loader: RecitationEngineLoader,
        microphone: RecitationMicrophone,
        pages: [Page],
        highlight: @escaping (Word?) -> Void,
        close: @escaping () -> Void
    ) {
        self.loader = loader
        self.microphone = microphone
        self.pages = pages
        self.highlight = highlight
        self.close = close
    }

    deinit {
        listeningTask?.cancel()
    }

    // MARK: Public

    /// Recognized audio per update: the model pads every call to 20 s, so a longer quiet-anchored
    /// window costs no more to recognize, avoids mid-word front cuts, and gives alignment more context.
    public static let windowSeconds = 16.0
    /// Time between the starts of two updates.
    public static let hop = Duration.milliseconds(300)
    /// Silence after which the microphone stops.
    public static let silenceLimit: TimeInterval = 60

    @Published public private(set) var state: State = .preparing
    @Published public var failure: Failure?

    /// Loads the model, then starts listening: tapping Recite is the request to listen.
    public func start() async {
        guard state == .preparing else { return }
        guard await prepare() else { return }
        await startListening()
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
            logger.error("Recitation follow: model download failed: \(error)")
            state = .needsModel(byteCount: loader.downloadByteCount)
            failure = .downloadFailed
            return
        }
        state = .preparing
        if await prepare() {
            state = .ready
        }
    }

    /// Starts the microphone and following from the pages in view.
    public func startListening() async {
        guard recognizer != nil, !isListening else { return }
        do {
            try await microphone.start()
        } catch {
            logger.error("Recitation follow: microphone failed to start: \(error)")
            state = .ready
            failure = (error as? RecitationMicrophoneError) == .permissionDenied ? .microphoneDenied : .microphoneUnavailable
            return
        }
        do {
            try await beginFollowing()
        } catch {
            logger.error("Recitation follow: expected words failed to load: \(error)")
            stopMicrophone()
            state = .failed
            return
        }
        logger.info("Recitation follow: listening from page \(pages.first?.pageNumber ?? 0)")
        lastSpeech = Date()
        listeningTask = Task { [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let started = clock.now
                guard let self, isListening else { return }
                do {
                    let raw = try microphone.recentSamples(seconds: Self.windowSeconds)
                    await follow(RecitationAudio.quietAnchoredWindow(raw))
                } catch {
                    logger.error("Recitation follow: recording failed: \(error)")
                }
                if Date().timeIntervalSince(lastSpeech) > Self.silenceLimit {
                    // This task stops itself, so it must not cancel its own handle (V1 trail, Decisions).
                    listeningTask = nil
                    stopMicrophone()
                    state = .stoppedAfterSilence
                    return
                }
                try? await clock.sleep(until: started + Self.hop)
            }
        }
    }

    /// Stops following and closes the follow controls.
    public func stop() {
        logger.info("Recitation follow: stopped")
        listeningTask?.cancel()
        listeningTask = nil
        stopMicrophone()
        if isListening {
            // A window still being recognized is dropped (`follow` checks the state after recognizing).
            state = .ready
        }
        close()
    }

    /// The person turned the page: while the place is not found, follow from the new pages.
    public func visiblePagesChanged(_ pages: [Page]) {
        self.pages = pages
        guard let follower else { return }
        switch state {
        case .lost:
            break
        case .listening:
            // Still searching the passage that holds these pages: nothing to restart.
            let expectedPages = Set(follower.expected.flatMap { $0.words.map(\.verse.page) })
            if pages.allSatisfy(expectedPages.contains) {
                return
            }
        default:
            // While following, the reader turns pages itself.
            return
        }
        logger.info("Recitation follow: following from page \(pages.first?.pageNumber ?? 0) after a page turn")
        Task {
            try? await startFollower(at: pages)
            if state == .lost {
                state = .listening
            }
        }
    }

    // MARK: Internal

    /// Loads the recognizer; false when the model is missing (the state offers the download) or
    /// failed to load.
    func prepare() async -> Bool {
        if recognizer != nil {
            return true
        }
        do {
            guard let recognizer = try await loader.load() else {
                state = .needsModel(byteCount: loader.downloadByteCount)
                return false
            }
            self.recognizer = recognizer
            return true
        } catch {
            logger.error("Recitation follow: model failed to load: \(error)")
            state = .failed
            return false
        }
    }

    /// The first and last verse of the passage being followed.
    var followedVerses: ClosedRange<AyahNumber>? {
        guard let first = follower?.expected.first?.words.first?.verse, let last = follower?.lastVerse else {
            return nil
        }
        return first ... last
    }

    /// Follows from the pages in view; the caller feeds windows (the microphone's, or a test's).
    func beginFollowing() async throws {
        try await startFollower(at: pages)
        state = .listening
    }

    /// Starts a new follower at `pages` and the page after them.
    func startFollower(at pages: [Page]) async throws {
        var verses = pages.sorted().flatMap(\.verses)
        if let next = pages.max()?.next {
            verses += next.verses
        }
        let expected = try await loader.verseText.expectedWords.expectedWords(for: verses)
        follower = RecitationFollower(expected: expected)
        followedWord = nil
    }

    /// Follows one window of 16 kHz mono samples (the latest `windowSeconds` recorded).
    func follow(_ samples: [Float]) async {
        guard let recognizer, follower != nil else { return }
        let words: [RecognizedWord]
        do {
            words = try await recognizer.recognizeWords(samples)
        } catch {
            if !(error is CancellationError) {
                logger.error("Recitation follow: recognition failed: \(error)")
            }
            return
        }
        // The person may have stopped while the window was recognized.
        guard isListening, var follower else { return }
        let isSpeaking = speechLevel.isSpeech(window: samples)
        if isSpeaking {
            lastSpeech = Date()
        }
        let followerState = follower.update(with: words, isSpeaking: isSpeaking)
        self.follower = follower
        apply(followerState)
        if follower.hasMissedRepeatedly {
            // Lost, or reciting somewhere other than the page in view.
            await relocate(words, recognizer: recognizer)
        }
        if self.follower?.needsMoreText == true {
            await appendNextPage()
        }
    }

    // MARK: Private

    private let loader: RecitationEngineLoader
    private let microphone: RecitationMicrophone
    private let highlight: (Word?) -> Void
    private let close: () -> Void
    private var pages: [Page]
    private var recognizer: RecitationRecognizer?
    private var follower: RecitationFollower?
    private var followedWord: Word?
    private var listeningTask: Task<Void, Never>?
    private var lastSpeech = Date()
    private var speechLevel = SpeechLevel()
    private var isAppending = false

    private var isListening: Bool {
        switch state {
        case .listening, .following, .lost: true
        default: false
        }
    }

    private func apply(_ followerState: RecitationFollower.State) {
        switch followerState {
        case .searching:
            state = .listening
        case .following(let word):
            state = .following(word.verse)
            if word != followedWord {
                followedWord = word
                highlight(word)
            }
        case .lost:
            if state != .lost {
                logger.info("Recitation follow: lost the place")
            }
            state = .lost
        }
    }

    /// Finds a lost place in the whole Quran; a trusted match restarts following at its page.
    private func relocate(_ words: [RecognizedWord], recognizer: RecitationRecognizer) async {
        let identification = await Self.identify(words, with: recognizer)
        guard identification.isConfident,
              let candidate = identification.candidates.first,
              let quran = pages.first?.quran,
              // The matcher numbers verses in Hafs 1405; every Hafs edition numbers them alike.
              let verse = AyahNumber(quran: quran, sura: candidate.firstVerse.sura.suraNumber, ayah: candidate.firstVerse.ayah)
        else {
            return
        }
        logger.info("Recitation follow: found the place again at page \(verse.page.pageNumber)")
        do {
            try await startFollower(at: [verse.page])
        } catch {
            logger.error("Recitation follow: expected words failed to load: \(error)")
            return
        }
        guard isListening, var follower else { return }
        let followerState = follower.update(with: words)
        self.follower = follower
        apply(followerState)
    }

    /// Matches against every verse off the main actor (a nonisolated async function runs on the
    /// global executor): it takes tens of milliseconds, and runs every second while lost.
    private nonisolated static func identify(_ words: [RecognizedWord], with recognizer: RecitationRecognizer) async -> VerseIdentification {
        recognizer.identifyVerses(in: words, limit: 1)
    }

    private func appendNextPage() async {
        guard !isAppending, let page = follower?.lastVerse?.page.next else { return }
        isAppending = true
        defer { isAppending = false }
        do {
            let units = try await loader.verseText.expectedWords.expectedWords(for: page.verses)
            follower?.append(units)
        } catch {
            logger.error("Recitation follow: expected words failed to load: \(error)")
        }
    }

    private func stopMicrophone() {
        _ = try? microphone.stop()
        if followedWord != nil {
            followedWord = nil
            highlight(nil)
        }
    }
}
