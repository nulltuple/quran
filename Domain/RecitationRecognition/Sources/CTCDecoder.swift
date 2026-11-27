//
//  CTCDecoder.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Foundation

/// A CTC model's output for one window: `frameCount` × `vocabularySize` log-probabilities,
/// row-major by frame.
public struct CTCLogProbabilities: Sendable {
    // MARK: Lifecycle

    public init(frameCount: Int, vocabularySize: Int, values: [Float]) {
        precondition(values.count == frameCount * vocabularySize, "values must hold frameCount × vocabularySize")
        self.frameCount = frameCount
        self.vocabularySize = vocabularySize
        self.values = values
    }

    // MARK: Public

    public let frameCount: Int
    public let vocabularySize: Int
    public let values: [Float]

    /// The most likely token id in each frame.
    public func bestTokens() -> [Int] {
        (0 ..< frameCount).map { frame in
            let row = frame * vocabularySize
            var best = 0
            var bestValue = -Float.infinity
            for token in 0 ..< vocabularySize where values[row + token] > bestValue {
                bestValue = values[row + token]
                best = token
            }
            return best
        }
    }
}

/// The model's token pieces: SentencePiece strings where U+2581 marks a word start.
public struct CTCVocabulary: Sendable {
    // MARK: Lifecycle

    public init(pieces: [String], blankID: Int) {
        self.pieces = pieces
        self.blankID = blankID
    }

    /// Reads a `{"0": "<unk>", "1": "ة", ...}` map (the model's `vocab.json`).
    public init(jsonData: Data, blankID: Int) throws {
        let map = try JSONDecoder().decode([String: String].self, from: jsonData)
        var pieces = [String](repeating: "", count: map.count)
        for (key, piece) in map {
            guard let id = Int(key), pieces.indices.contains(id) else {
                throw CTCVocabularyError.invalidTokenID(key)
            }
            pieces[id] = piece
        }
        self.init(pieces: pieces, blankID: blankID)
    }

    // MARK: Public

    public let pieces: [String]
    public let blankID: Int
}

public enum CTCVocabularyError: Error, Equatable {
    case invalidTokenID(String)
}

/// One emitted token and the frames (80 ms each for the Tilawi model) it spans.
public struct CTCToken: Equatable, Sendable {
    public let id: Int
    public let piece: String
    public let frames: ClosedRange<Int>
    /// The token's mean probability (0–1) over its frames, when decoded from probabilities.
    public var confidence: Float? = nil
}

public struct CTCTranscript: Equatable, Sendable {
    public let text: String
    public let tokens: [CTCToken]
}

/// Greedy CTC decoding: the best token in each frame, repeats collapsed, blanks dropped.
public struct CTCDecoder: Sendable {
    // MARK: Lifecycle

    public init(vocabulary: CTCVocabulary) {
        self.vocabulary = vocabulary
    }

    // MARK: Public

    public let vocabulary: CTCVocabulary

    public func decode(_ logProbabilities: CTCLogProbabilities) -> CTCTranscript {
        let transcript = decode(frameTokens: logProbabilities.bestTokens())
        let size = logProbabilities.vocabularySize
        let tokens = transcript.tokens.map { token in
            var token = token
            let total = token.frames.reduce(Float(0)) { $0 + exp(logProbabilities.values[$1 * size + token.id]) }
            token.confidence = total / Float(token.frames.count)
            return token
        }
        return CTCTranscript(text: transcript.text, tokens: tokens)
    }

    public func decode(frameTokens: [Int]) -> CTCTranscript {
        var tokens: [CTCToken] = []
        var previous: Int?
        for (frame, id) in frameTokens.enumerated() {
            defer { previous = id }
            if id == previous {
                if let last = tokens.last, last.id == id, last.frames.upperBound == frame - 1 {
                    tokens[tokens.count - 1] = CTCToken(id: id, piece: last.piece, frames: last.frames.lowerBound ... frame)
                }
                continue
            }
            guard id != vocabulary.blankID, vocabulary.pieces.indices.contains(id) else {
                continue
            }
            tokens.append(CTCToken(id: id, piece: vocabulary.pieces[id], frames: frame ... frame))
        }
        let text = tokens.map(\.piece).joined()
            .replacingOccurrences(of: "\u{2581}", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        return CTCTranscript(text: text, tokens: tokens)
    }
}
