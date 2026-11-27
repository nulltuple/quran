//
//  VoiceSearchViewModel.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import QuranKit
import QuranText
import RecitationRecognition
import VLogging

/// Search by recitation (roadmap V1): listen until the reciter pauses, recognize on the device,
/// then offer the verses it matches. When the match is not trusted, every candidate is offered
/// with equal weight so the person chooses. Nothing recorded is kept: the samples live in memory
/// until they are recognized.
@MainActor
final class VoiceSearchViewModel: ObservableObject {
    enum State: Equatable {
        case preparing
        /// The model is not on this device; downloading it takes `byteCount` bytes.
        case needsModel(byteCount: Int64)
        case downloading(progress: Double)
        /// Ready to listen (after a download, a cancelled recording or a result).
        case ready
        /// `level` is the microphone's recent peak, 0–1.
        case listening(level: Double)
        case recognizing
        case results(Results)
        /// Nothing louder than room noise was heard.
        case heardNothing
        /// Speech was heard but matched no verse well enough to offer.
        case noMatch
        case failed
    }

    enum Failure: Equatable {
        case downloadFailed
        case microphoneDenied
        case microphoneUnavailable
    }

    struct Candidate: Equatable, Identifiable {
        let id: Int
        let verses: ClosedRange<AyahNumber>
        let text: QuranText?
    }

    struct Results: Equatable {
        /// The first candidate is trusted (the matcher's trust gate).
        let isConfident: Bool
        let candidates: [Candidate]
    }

    // MARK: Lifecycle

    init(
        loader: RecitationEngineLoader,
        microphone: RecitationMicrophone,
        quran: @escaping () -> Quran,
        navigateTo: @escaping (AyahNumber) -> Void
    ) {
        self.loader = loader
        self.microphone = microphone
        self.quran = quran
        self.navigateTo = navigateTo
    }

    deinit {
        listeningTask?.cancel()
    }

    // MARK: Internal

    static let candidateLimit = 5

    @Published private(set) var state: State = .preparing
    @Published var failure: Failure?

    /// Loads the model, then starts listening: opening voice search is the request to listen.
    func start() async {
        guard state == .preparing else { return }
        guard await prepare() else { return }
        await startListening()
    }

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
            logger.error("Voice search: model failed to load: \(error)")
            state = .failed
            return false
        }
    }

    func download() async {
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
            logger.error("Voice search: model download failed: \(error)")
            state = .needsModel(byteCount: loader.downloadByteCount)
            failure = .downloadFailed
            return
        }
        state = .preparing
        if await prepare() {
            state = .ready
        }
    }

    func startListening() async {
        guard recognizer != nil, !isListening else { return }
        do {
            try await microphone.start()
        } catch {
            logger.error("Voice search: microphone failed to start: \(error)")
            state = .ready
            failure = (error as? RecitationMicrophoneError) == .permissionDenied ? .microphoneDenied : .microphoneUnavailable
            return
        }
        state = .listening(level: 0)
        let started = Date()
        listeningTask = Task { [weak self] in
            var detector = EndOfRecitationDetector()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, case .listening = state else { return }
                let peak = microphone.recentPeak()
                state = .listening(level: Double(peak))
                switch detector.update(elapsed: Date().timeIntervalSince(started), peak: peak) {
                case .keepListening:
                    continue
                case .finished:
                    // This task runs the search: cancelling it, as `stopListening()` does, would cancel recognition.
                    listeningTask = nil
                    await finishListening()
                    return
                case .heardNothing:
                    _ = try? microphone.stop()
                    state = .heardNothing
                    return
                }
            }
        }
    }

    /// Stops listening and searches what was heard.
    func stopListening() async {
        guard isListening else { return }
        listeningTask?.cancel()
        listeningTask = nil
        await finishListening()
    }

    /// Listens again after a result, nothing heard, no match, or a model that failed to load.
    func tryAgain() async {
        switch state {
        case .failed:
            state = .preparing
            await start()
        case .results, .heardNothing, .noMatch, .ready:
            await startListening()
        default:
            return
        }
    }

    /// Stops listening without searching; called when the sheet closes.
    func cancel() {
        listeningTask?.cancel()
        listeningTask = nil
        _ = try? microphone.stop()
        if isListening || state == .recognizing {
            state = .ready
        }
    }

    /// Recognizes `samples` (16 kHz mono) and publishes the candidates.
    func search(_ samples: [Float]) async {
        guard let recognizer else { return }
        state = .recognizing
        do {
            let identification = try await recognizer.identifyVerses(in: samples, limit: Self.candidateLimit)
            guard identification.isWorthOffering else {
                logger.info("Voice search: nothing worth offering (\(identification.letterCount) letters)")
                state = .noMatch
                return
            }
            let quran = quran()
            let texts = (try? await loader.verseText.text(of: identification.candidates.map(\.firstVerse))) ?? [:]
            var candidates: [Candidate] = []
            for candidate in identification.candidates {
                // Runs starting at the same verse (1:2 and 1:2–3) open the same place: offer it once.
                guard let verses = Self.verses(of: candidate, in: quran),
                      !candidates.contains(where: { $0.verses.lowerBound == verses.lowerBound })
                else { continue }
                candidates.append(Candidate(id: candidates.count, verses: verses, text: texts[candidate.firstVerse]))
            }
            logger.info("Voice search: \(candidates.count) candidates, confident: \(identification.isConfident)")
            state = candidates.isEmpty ? .noMatch : .results(Results(isConfident: identification.isConfident, candidates: candidates))
        } catch is CancellationError {
            // The sheet closed while recognizing.
        } catch {
            logger.error("Voice search: recognition failed: \(error)")
            state = .noMatch
        }
    }

    func select(_ candidate: Candidate) {
        logger.info("Voice search: candidate \(candidate.id) selected")
        cancel()
        navigateTo(candidate.verses.lowerBound)
    }

    // MARK: Private

    private let loader: RecitationEngineLoader
    private let microphone: RecitationMicrophone
    private let quran: () -> Quran
    private let navigateTo: (AyahNumber) -> Void
    private var recognizer: RecitationRecognizer?
    private var listeningTask: Task<Void, Never>?

    private var isListening: Bool {
        if case .listening = state {
            return true
        }
        return false
    }

    private func finishListening() async {
        guard isListening else { return }
        state = .recognizing
        do {
            let samples = try microphone.stop()
            await search(samples)
        } catch {
            logger.error("Voice search: recording failed: \(error)")
            state = .ready
            failure = .microphoneUnavailable
        }
    }

    /// The candidate's verses in the reader's edition: every Hafs edition numbers ayahs alike, but
    /// navigation needs the edition the reader shows.
    private static func verses(of candidate: VerseCandidate, in quran: Quran) -> ClosedRange<AyahNumber>? {
        guard let first = AyahNumber(quran: quran, sura: candidate.firstVerse.sura.suraNumber, ayah: candidate.firstVerse.ayah),
              let last = AyahNumber(quran: quran, sura: candidate.lastVerse.sura.suraNumber, ayah: candidate.lastVerse.ayah),
              first <= last
        else {
            return nil
        }
        return first ... last
    }
}
