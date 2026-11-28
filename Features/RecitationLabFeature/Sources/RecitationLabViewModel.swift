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

/// The developer screen's state: load the on-device Tilawi (V0) and phonetic (V4) models, record
/// from the microphone, then show what the engines heard, the verses found, canonical word
/// alignment, V4 phoneme/vowel pronunciation assessment, and latency/memory numbers. Nothing
/// recorded is kept: the samples live in memory until the next recording or until the screen closes.
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

        struct PronunciationWord: Equatable, Identifiable {
            let id: Int
            let displayText: String
            let expectedPhonemes: String
            let heardPhonemes: String
            let status: WordPronunciationAssessment.Status
            let issueSummaries: [String]
        }

        struct PronunciationSummary: Equatable {
            let targetRange: String
            let expectedPhonemes: String
            let heardPhonemes: String
            let phonemeMatchRate: Double
            let confirmedMistakeCount: Int
            let uncertainCount: Int
            let inferenceMilliseconds: Int
            let words: [PronunciationWord]
        }

        struct TajweedRemarkItem: Equatable, Identifiable {
            let id: Int
            let wordText: String
            let category: TajweedRuleCategory
            let certainty: TajweedRemark.Certainty
            let summary: String
        }

        struct TajweedSummary: Equatable {
            let targetRange: String
            let confirmedRemarkCount: Int
            let uncertainRemarkCount: Int
            let secondsPerCount: Double?
            let measuredMadds: [String]
            let remarks: [TajweedRemarkItem]
        }

        let transcript: String
        let candidates: [Candidate]
        let isConfident: Bool
        let words: [AlignedWord]
        let pronunciation: PronunciationSummary?
        let tajweed: TajweedSummary?
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

    init(
        loader: RecitationEngineLoader,
        phoneticLoader: PhoneticEngineLoader,
        microphone: RecitationMicrophone
    ) {
        self.loader = loader
        self.phoneticLoader = phoneticLoader
        self.microphone = microphone
    }

    deinit {
        elapsedTask?.cancel()
    }

    // MARK: Internal

    @Published private(set) var modelState: ModelState = .loading
    @Published private(set) var phoneticModelState: ModelState = .loading
    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var result: Result?
    @Published var error: Error?
    /// Optional explicit verse (`sura:ayah`, e.g. `112:1`) to assess pronunciation against instead
    /// of Tilawi's top identified verse — useful for testing error detection with mismatched audio.
    @Published var targetVerseOverride: String = ""

    var canRecord: Bool {
        if case .ready = modelState, recordingState == .idle {
            return true
        }
        return false
    }

    func load() async {
        await loadRecitationModel()
        await loadPhoneticModel()
    }

    /// Downloads the published Tilawi model (84 MB, owner decision D7), then loads it.
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
            await loadRecitationModel()
        } catch {
            logger.error("Recitation lab: model download failed: \(error)")
            modelState = .notInstalled(directory: loader.store.directory.path)
            self.error = LabError(underlying: error)
        }
    }

    /// Downloads the published phonetic assessment pack (`phonetic-model-1`, 21 MB), then loads it.
    func downloadPhoneticModel() async {
        switch phoneticModelState {
        case .notInstalled, .failed: break
        default: return
        }
        phoneticModelState = .downloading(progress: 0)
        do {
            try await phoneticLoader.download { progress in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = phoneticModelState else { return }
                    phoneticModelState = .downloading(progress: progress)
                }
            }
            phoneticModelState = .loading
            await loadPhoneticModel()
        } catch {
            logger.error("Recitation lab: phonetic model download failed: \(error)")
            phoneticModelState = .notInstalled(directory: phoneticLoader.store.directory.path)
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

    /// Recognizes `samples` (16 kHz mono) with Tilawi (V0) and, when installed, assesses clear
    /// pronunciation (V4) against the selected or top identified verse(s).
    func analyze(_ samples: [Float]) async {
        guard let engine else { return }
        do {
            let start = Date()
            let words = try await engine.recognizer.recognizeWords(samples)
            let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
            let identification = engine.recognizer.identifyVerses(in: words)
            var aligned: [Result.AlignedWord] = []
            var candidateVerses: [AyahNumber] = []
            if let best = identification.candidates.first {
                candidateVerses = verses(from: best.firstVerse, to: best.lastVerse)
                let expected = try await loader.verseText.expectedWords.expectedWords(for: candidateVerses)
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

            let (pronunciation, tajweed) = try await assessPhonetics(
                samples: samples,
                identifiedVerses: candidateVerses
            )

            result = Result(
                transcript: identification.transcript,
                candidates: identification.candidates.enumerated().map { index, candidate in
                    Result.Candidate(id: index, range: Self.name(candidate), score: candidate.score)
                },
                isConfident: identification.isConfident,
                words: aligned,
                pronunciation: pronunciation,
                tajweed: tajweed,
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
    private let phoneticLoader: PhoneticEngineLoader
    private let microphone: RecitationMicrophone
    private var engine: Engine?
    private var phoneticPack: PhoneticModelStore.LoadedPack?
    private var elapsedTask: Task<Void, Never>?

    private func loadRecitationModel() async {
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

    private func loadPhoneticModel() async {
        guard phoneticPack == nil else { return }
        phoneticModelState = .loading
        let start = Date()
        do {
            guard let pack = try await phoneticLoader.load() else {
                phoneticModelState = .notInstalled(directory: phoneticLoader.store.directory.path)
                return
            }
            phoneticPack = pack
            phoneticModelState = .ready(loadMilliseconds: Int(Date().timeIntervalSince(start) * 1000))
        } catch {
            logger.error("Recitation lab: phonetic model failed to load: \(error)")
            phoneticModelState = .failed("\(error)")
        }
    }

    private func assessPhonetics(
        samples: [Float],
        identifiedVerses: [AyahNumber]
    ) async throws -> (Result.PronunciationSummary?, Result.TajweedSummary?) {
        guard let phoneticPack else { return (nil, nil) }
        let targetVerses: [AyahNumber] = if let override = Self.parseVerse(targetVerseOverride) {
            [override]
        } else {
            identifiedVerses
        }
        guard !targetVerses.isEmpty,
              let reference = try phoneticPack.referenceStore.reference(for: targetVerses)
        else {
            return (nil, nil)
        }

        let start = Date()
        let transcription = try await phoneticPack.acousticModel.transcribe(samples)
        let assessment = PronunciationAssessor().assess(transcription: transcription, against: reference)
        let tajweedAssessment = TajweedAssessor().assess(transcription: transcription, against: reference)
        let inferenceMs = Int(Date().timeIntervalSince(start) * 1000)

        let targetLabel: String = if let first = targetVerses.first, let last = targetVerses.last {
            first == last
                ? "\(first.sura.suraNumber):\(first.ayah)"
                : "\(first.sura.suraNumber):\(first.ayah)–\(last.sura.suraNumber):\(last.ayah)"
        } else {
            ""
        }

        let pronunciationSummary = Result.PronunciationSummary(
            targetRange: targetLabel,
            expectedPhonemes: assessment.expectedPhonemes,
            heardPhonemes: assessment.heardPhonemes,
            phonemeMatchRate: assessment.phonemeMatchRate,
            confirmedMistakeCount: assessment.confirmedMistakeCount,
            uncertainCount: assessment.uncertainCount,
            inferenceMilliseconds: inferenceMs,
            words: assessment.words.map { word in
                Result.PronunciationWord(
                    id: word.wordIndex,
                    displayText: word.displayText,
                    expectedPhonemes: word.expectedPhonemes,
                    heardPhonemes: word.heardPhonemes,
                    status: word.status,
                    issueSummaries: word.issues.map { issue in
                        let tag = issue.certainty == .confirmed ? "Mistake" : "Uncertain"
                        return "[\(tag) · \(Int((issue.confidence * 100).rounded()))%] \(issue.summary)"
                    }
                )
            }
        )

        let tajweedSummary = Result.TajweedSummary(
            targetRange: targetLabel,
            confirmedRemarkCount: tajweedAssessment.confirmedRemarkCount,
            uncertainRemarkCount: tajweedAssessment.uncertainRemarkCount,
            secondsPerCount: tajweedAssessment.secondsPerCount,
            measuredMadds: tajweedAssessment.measuredMadds.map { madd in
                let timingTag = madd.measuredByTiming ? " (timed)" : ""
                return "\(madd.displayText): \(madd.displayName) — \(madd.heardCounts) counts\(timingTag)"
            },
            remarks: tajweedAssessment.remarks.enumerated().map { index, remark in
                let tag = remark.certainty == .confirmed ? "Remark" : "Uncertain"
                return Result.TajweedRemarkItem(
                    id: index,
                    wordText: remark.displayText,
                    category: remark.category,
                    certainty: remark.certainty,
                    summary: "[\(tag) · \(remark.category.rawValue) · \(Int((remark.confidence * 100).rounded()))%] \(remark.summary)"
                )
            }
        )

        return (pronunciationSummary, tajweedSummary)
    }

    static func parseVerse(_ input: String) -> AyahNumber? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let suraNum = Int(parts[0]),
              let ayahNum = Int(parts[1]),
              let sura = Sura(quran: Quran.hafsMadani1405, suraNumber: suraNum)
        else {
            return nil
        }
        return AyahNumber(sura: sura, ayah: ayahNum)
    }

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
