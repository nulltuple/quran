//
//  RecognizedWord.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation

/// One word of a transcript, as the model wrote it, with the CTC frames its tokens span from the
/// start of the audio (80 ms a frame for the Tilawi model). `frames` is nil for a transcript that
/// came without timing, such as a stored benchmark transcript.
public struct RecognizedWord: Equatable, Sendable {
    // MARK: Lifecycle

    public init(text: String, frames: ClosedRange<Int>?, confidence: Float? = nil, meanConfidence: Float? = nil) {
        self.text = text
        self.frames = frames
        self.confidence = confidence
        self.meanConfidence = meanConfidence ?? confidence
    }

    // MARK: Public

    public let text: String
    public let frames: ClosedRange<Int>?
    /// The model's confidence (0–1) in the word: its least confident token's mean probability; nil
    /// without probabilities.
    public let confidence: Float?
    /// The average token probability (0–1) across the word's tokens; nil without probabilities.
    public let meanConfidence: Float?

    /// The words of a plain transcript, without timing.
    public static func words(of transcript: String) -> [RecognizedWord] {
        transcript.split(whereSeparator: \.isWhitespace).map { RecognizedWord(text: String($0), frames: nil) }
    }
}

extension CTCTranscript {
    /// The transcript's words: a token piece starting with U+2581 starts a word. Each word spans
    /// the frames of its tokens, shifted by `frameOffset` (the window's first frame in the audio).
    public func words(frameOffset: Int = 0) -> [RecognizedWord] {
        var words: [RecognizedWord] = []
        var text = ""
        var frames: ClosedRange<Int>?
        var minConfidence: Float?
        var confidenceSum: Float = 0
        var confidenceCount = 0
        func finishWord() {
            if !text.isEmpty, let frames {
                let meanConfidence = confidenceCount > 0 ? confidenceSum / Float(confidenceCount) : nil
                words.append(RecognizedWord(text: text, frames: frames, confidence: minConfidence, meanConfidence: meanConfidence))
            }
            text = ""
            frames = nil
            minConfidence = nil
            confidenceSum = 0
            confidenceCount = 0
        }
        for token in tokens {
            let shifted = token.frames.lowerBound + frameOffset ... token.frames.upperBound + frameOffset
            // A piece may start a word ("▁قل"), continue one ("ل"), or be the separator alone ("▁").
            let parts = token.piece.split(separator: "\u{2581}", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    finishWord()
                }
                let letters = part.filter { !$0.isWhitespace }
                guard !letters.isEmpty else {
                    continue
                }
                text += letters
                frames = frames.map { min($0.lowerBound, shifted.lowerBound) ... max($0.upperBound, shifted.upperBound) } ?? shifted
                if let tokenConfidence = token.confidence {
                    minConfidence = min(minConfidence ?? tokenConfidence, tokenConfidence)
                    confidenceSum += tokenConfidence
                    confidenceCount += 1
                }
            }
        }
        finishWord()
        return words
    }
}
