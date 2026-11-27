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
    /// consecutive windows of at most the model's length. When more audio follows, a window ends at
    /// the quietest frame of its last `quietSearchSeconds` (`windowEnd`), so the cut falls in a pause
    /// rather than inside a word, which would be misheard or split (recite and check reports
    /// those as mistakes).
    public func recognizeWords(_ samples: [Float]) async throws -> [RecognizedWord] {
        var words: [RecognizedWord] = []
        var start = 0
        repeat {
            let end = Self.windowEnd(samples, from: start, length: model.windowSampleCount, frame: model.samplesPerFrame)
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

    // MARK: Internal

    static let quietSearchSeconds = 4.0

    /// The end of the window that starts at `start`: the end of `samples` when they fit in
    /// `length`; otherwise the frame boundary (a whole number of `frame`s from `start`, so word
    /// frames stay exact) after the quietest frame of the window's last `quietSearchSeconds`.
    static func windowEnd(_ samples: [Float], from start: Int, length: Int, frame: Int) -> Int {
        let full = start + length
        guard full < samples.count else {
            return samples.count
        }
        let searched = Int(quietSearchSeconds * Double(RecitationAudio.sampleRate)) / frame
        var best = full
        var quietest = Float.infinity
        for back in 0 ..< min(searched, length / frame - 1) {
            let end = full - back * frame
            var energy: Float = 0
            for sample in samples[end - frame ..< end] {
                energy += sample * sample
            }
            if energy < quietest {
                quietest = energy
                best = end
            }
        }
        return best
    }

    // MARK: Private

    private let model: any RecitationAcousticModel
    private let decoder: CTCDecoder
    private let matcher: VerseMatcher
}
