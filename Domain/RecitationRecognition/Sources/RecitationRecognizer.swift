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

    /// The transcript of `samples` (16 kHz mono), in consecutive windows of the model's length.
    /// A word cut by a window edge may be misheard; overlapping windows are a V2 follow-up.
    public func transcribe(_ samples: [Float]) async throws -> String {
        var parts: [String] = []
        var start = 0
        repeat {
            let end = min(start + model.windowSampleCount, samples.count)
            let text = try await decoder.decode(model.logProbabilities(for: samples[start ..< end])).text
            if !text.isEmpty {
                parts.append(text)
            }
            start = end
        } while start < samples.count
        return parts.joined(separator: " ")
    }

    /// The verses `samples` most likely recite, best first.
    public func identifyVerses(in samples: [Float], limit: Int = 5) async throws -> VerseIdentification {
        let transcript = try await transcribe(samples)
        return matcher.identify(transcript: transcript, limit: limit)
    }

    // MARK: Private

    private let model: any RecitationAcousticModel
    private let decoder: CTCDecoder
    private let matcher: VerseMatcher
}
