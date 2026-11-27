//
//  RecitationLabViewModel.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import QuranKit
import RecitationRecognition
import VLogging

/// The developer screen's state: load the on-device model, record from the microphone, then show
/// what the engine heard, the verses it found and each canonical word's alignment and timing,
/// with the latency and memory numbers V0's device benchmarks need. Nothing recorded is kept: the
/// samples live in memory until the next recording or until the screen closes.
@MainActor
final class RecitationLabViewModel: ObservableObject {
    enum ModelState: Equatable {
        case loading
        case notInstalled(directory: String)
        case downloading(progress: Double)
        case failed(String)
        case ready(loadMilliseconds: Int)
    }

    enum RecordingState: Equatable {
        case idle
        case recording(seconds: Double)
        case recognizing
    }

    struct Result: Equatable {
        struct Candidate: Equatable, Identifiable {
            let id: Int
            let range: String
            let score: Double
        }

        struct AlignedWord: Equatable, Identifiable {
            let id: Int
            let expected: String
            let recognized: String
            let kind: WordAlignmentStep.Kind
            let seconds: ClosedRange<Double>?
        }

        let transcript: String
        let candidates: [Candidate]
        let isConfident: Bool
        let words: [AlignedWord]
        let audioSeconds: Double
        /// The loudest sample, in dB below full scale; about −90 or lower is silence (no microphone signal).
        let peakDecibels: Double
        let recognitionMilliseconds: Int
        let footprintMegabytes: Int?

        var realTimeFactor: Double {
            audioSeconds > 0 ? Double(recognitionMilliseconds) / 1000 / audioSeconds : 0
        }
    }

    // MARK: Lifecycle

    init(loader: RecitationEngineLoader, microphone: RecitationMicrophone) {
        self.loader = loader
        self.microphone = microphone
    }

    deinit {
        elapsedTask?.cancel()
    }

    // MARK: Internal

    @Published private(set) var modelState: ModelState = .loading
    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var result: Result?
    @Published var error: Error?

    var canRecord: Bool {
        if case .ready = modelState, recordingState == .idle {
            return true
        }
        return false
    }

    func load() async {
        guard engine == nil else { return }
        modelState = .loading
        let start = Date()
        do {
            guard let recognizer = try await loader.load() else {
                modelState = .notInstalled(directory: loader.store.directory.path)
                return
            }
            engine = Engine(recognizer: recognizer)
            modelState = .ready(loadMilliseconds: Int(Date().timeIntervalSince(start) * 1000))
        } catch {
            logger.error("Recitation lab: model failed to load: \(error)")
            modelState = .failed("\(error)")
        }
    }

    /// Downloads the published model (84 MB, owner decision D7), then loads it.
    func downloadModel() async {
        switch modelState {
        case .notInstalled, .failed: break
        default: return
        }
        modelState = .downloading(progress: 0)
        do {
            try await loader.download { progress in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = modelState else { return }
                    modelState = .downloading(progress: progress)
                }
            }
            modelState = .loading
            await load()
        } catch {
            logger.error("Recitation lab: model download failed: \(error)")
            modelState = .notInstalled(directory: loader.store.directory.path)
            self.error = LabError(underlying: error)
        }
    }

    func startRecording() async {
        guard canRecord else { return }
        do {
            try await microphone.start()
        } catch {
            self.error = LabError(underlying: error)
            return
        }
        result = nil
        recordingState = .recording(seconds: 0)
        let started = Date()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, case .recording = recordingState else { return }
                let seconds = Date().timeIntervalSince(started)
                recordingState = .recording(seconds: seconds)
                if seconds >= RecitationMicrophone.maximumSeconds {
                    await stopRecording()
                    return
                }
            }
        }
    }

    func stopRecording() async {
        guard case .recording = recordingState else { return }
        elapsedTask?.cancel()
        elapsedTask = nil
        recordingState = .recognizing
        do {
            let samples = try microphone.stop()
            await analyze(samples)
        } catch {
            self.error = LabError(underlying: error)
        }
        recordingState = .idle
    }

    /// Recognizes `samples` (16 kHz mono) and publishes the result.
    func analyze(_ samples: [Float]) async {
        guard let engine else { return }
        do {
            let start = Date()
            let words = try await engine.recognizer.recognizeWords(samples)
            let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
            let identification = engine.recognizer.identifyVerses(in: words)
            var aligned: [Result.AlignedWord] = []
            if let best = identification.candidates.first {
                let verses = verses(from: best.firstVerse, to: best.lastVerse)
                let expected = try await loader.verseText.expectedWords.expectedWords(for: verses)
                let texts = Dictionary(expected.flatMap { unit in unit.words.map { ($0, unit.text) } }, uniquingKeysWith: { first, _ in first })
                aligned = WordAligner().align(words, to: expected).enumerated().map { index, step in
                    Result.AlignedWord(
                        id: index,
                        expected: step.expected.map { "\($0.verse.sura.suraNumber):\($0.verse.ayah):\($0.wordNumber) \(texts[$0] ?? "")" }
                            .joined(separator: " + "),
                        recognized: step.recognized.map(\.text).joined(separator: " "),
                        kind: step.kind,
                        seconds: step.frames.map { Double($0.lowerBound) * Self.secondsPerFrame ... Double($0.upperBound + 1) * Self.secondsPerFrame }
                    )
                }
            }
            result = Result(
                transcript: identification.transcript,
                candidates: identification.candidates.enumerated().map { index, candidate in
                    Result.Candidate(id: index, range: Self.name(candidate), score: candidate.score)
                },
                isConfident: identification.isConfident,
                words: aligned,
                audioSeconds: Double(samples.count) / Double(RecitationAudio.sampleRate),
                peakDecibels: 20 * log10(max(Double(samples.map(abs).max() ?? 0), 1e-6)),
                recognitionMilliseconds: milliseconds,
                footprintMegabytes: ProcessMemory.footprintBytes().map { Int($0 / 1_048_576) }
            )
        } catch {
            self.error = LabError(underlying: error)
        }
    }

    // MARK: Private

    /// Shows the underlying error in the alert: on a developer screen the details are the point.
    private struct LabError: LocalizedError {
        let underlying: Error
        var errorDescription: String? {
            if let microphoneError = underlying as? RecitationMicrophoneError, microphoneError == .permissionDenied {
                return "Microphone access is off. Allow it in Settings > Privacy & Security > Microphone."
            }
            return "\(underlying)"
        }
    }

    private struct Engine {
        let recognizer: RecitationRecognizer
    }

    private static let secondsPerFrame = Double(CoreMLRecitationModel.samplesPerFrame) / Double(RecitationAudio.sampleRate)

    private let loader: RecitationEngineLoader
    private let microphone: RecitationMicrophone
    private var engine: Engine?
    private var elapsedTask: Task<Void, Never>?

    private static func name(_ candidate: VerseCandidate) -> String {
        let first = "\(candidate.firstVerse.sura.suraNumber):\(candidate.firstVerse.ayah)"
        guard candidate.lastVerse != candidate.firstVerse else {
            return first
        }
        return "\(first)–\(candidate.lastVerse.sura.suraNumber):\(candidate.lastVerse.ayah)"
    }

    private func verses(from first: AyahNumber, to last: AyahNumber) -> [AyahNumber] {
        var verses = [first]
        while let current = verses.last, current < last, let next = current.next {
            verses.append(next)
        }
        return verses
    }
}
