//
//  UthmaniWordLayout.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

/// How an ayah's canonical words line up with the whitespace-separated tokens of the bundled
/// Uthmani text. Usually each token is one word; a few ayahs write two words as one token
/// (`لَّوۡمَا` in 15:7) or one word as two (`إِلۡ يَاسِينَ` in 37:130). `Tools/build-qul-word-data.py`
/// verifies every such ayah letter by letter.
public struct UthmaniWordLayout: Hashable, Sendable {
    /// Tokens shown together with the words they show.
    public struct Unit: Hashable, Sendable {
        public init(tokens: ClosedRange<Int>, words: ClosedRange<Int>) {
            self.tokens = tokens
            self.words = words
        }

        /// The text tokens the unit joins, from 1.
        public let tokens: ClosedRange<Int>
        /// The canonical words it shows, from 1.
        public let words: ClosedRange<Int>
    }

    // MARK: Lifecycle

    /// `tokenWords[i]` are the words token `i + 1` covers, or `nil` for one token per word.
    public init(wordCount: Int, tokenWords: [ClosedRange<Int>]? = nil) {
        self.wordCount = wordCount
        self.tokenWords = tokenWords
    }

    // MARK: Public

    public let wordCount: Int

    /// The units of a text with `tokenCount` tokens; `nil` when the text doesn't split as the
    /// verified mapping expects (another script or edition), so it shows no word-by-word data.
    public func units(tokenCount: Int) -> [Unit]? {
        guard let tokenWords else {
            guard tokenCount == wordCount else {
                return nil
            }
            return (0 ..< wordCount).map { Unit(tokens: $0 + 1 ... $0 + 1, words: $0 + 1 ... $0 + 1) }
        }
        guard tokenWords.count == tokenCount, tokenWords.first?.lowerBound == 1,
              tokenWords.last?.upperBound == wordCount
        else {
            return nil
        }
        var units: [Unit] = []
        for (index, words) in tokenWords.enumerated() {
            let token = index + 1
            if let last = units.last, last.words == words {
                units[units.count - 1] = Unit(tokens: last.tokens.lowerBound ... token, words: words)
            } else if units.last.map({ words.lowerBound == $0.words.upperBound + 1 }) ?? true {
                units.append(Unit(tokens: token ... token, words: words))
            } else {
                return nil
            }
        }
        return units
    }

    // MARK: Private

    private let tokenWords: [ClosedRange<Int>]?
}
