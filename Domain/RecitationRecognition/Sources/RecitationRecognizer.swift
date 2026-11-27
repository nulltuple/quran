//
//  RecitationRecognizer.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Foundation

/// Audio → transcript → ranked verses, on the device. The transcript is the reciter's words only;
/// Quran text is never generated, only compared with.
public struct RecitationRecognizer: Sendable {
    // MARK: Lifecycle

    public init(model: any RecitationAcousticModel, decoder: CTCDecoder, matcher: VerseMatcher) {
        self.model = model
        self.decoder = decoder
        self.matcher = matcher
    }

    // MARK: Public

    /// The words of `samples` (16 kHz mono), with their frames from the start of the audio, in
    /// consecutive windows of the model's length. A word cut by a window edge may be misheard or
    /// split; overlapping windows are a V2 follow-up.
    public func recognizeWords(_ samples: [Float]) async throws -> [RecognizedWord] {
        var words: [RecognizedWord] = []
        var start = 0
        repeat {
            let end = min(start + model.windowSampleCount, samples.count)
            let transcript = try await decoder.decode(model.logProbabilities(for: samples[start ..< end]))
            words += transcript.words(frameOffset: start / model.samplesPerFrame)
            start = end
        } while start < samples.count
        return words
    }

    /// The transcript of `samples`: the recognized words, space separated.
    public func transcribe(_ samples: [Float]) async throws -> String {
        try await recognizeWords(samples).map(\.text).joined(separator: " ")
    }

    /// The verses `samples` most likely recite, best first.
    public func identifyVerses(in samples: [Float], limit: Int = 5) async throws -> VerseIdentification {
        let transcript = try await transcribe(samples)
        return matcher.identify(transcript: transcript, limit: limit)
    }

    /// The verses `words` (from `recognizeWords`) most likely recite, best first; with
    /// `WordAligner` this identifies and aligns one recording with a single model run.
    public func identifyVerses(in words: [RecognizedWord], limit: Int = 5) -> VerseIdentification {
        matcher.identify(transcript: words.map(\.text).joined(separator: " "), limit: limit)
    }

    /// The words of `samples` aligned to `expected` (the canonical words of the passage they
    /// recite, from `ExpectedWordsReader`), each step with its recited words' frames.
    public func alignWords(in samples: [Float], to expected: [ExpectedWordText]) async throws -> [WordAlignmentStep] {
        try await WordAligner().align(recognizeWords(samples), to: expected)
    }

    // MARK: Private

    private let model: any RecitationAcousticModel
    private let decoder: CTCDecoder
    private let matcher: VerseMatcher
}
