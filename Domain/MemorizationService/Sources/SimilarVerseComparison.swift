//
//  SimilarVerseComparison.swift
//

import Foundation
import QuranKit
import QuranText

public struct SimilarVerseComparison: Sendable {
    public struct Verse: Identifiable, Sendable {
        public let id: AyahNumber
        public let text: QuranText
    }

    public struct Continuation: Sendable {
        public let expected: Verse
        public let alternative: Verse
    }

    public struct Ending: Sendable {
        public let prompt: QuranText
        public let answer: QuranText
    }

    init(source: Verse, match: Verse, sourceNext: Verse?, matchNext: Verse?) {
        self.source = source
        self.match = match

        let sourceWords = Self.words(in: source.text)
        let matchWords = Self.words(in: match.text)
        let changes = sourceWords.map(Self.comparableWord).difference(from: matchWords.map(Self.comparableWord))
        sourceDifferences = changes.insertions.map { change in
            guard case .insert(let offset, _, _) = change else { preconditionFailure() }
            let word = sourceWords[offset]
            return word.startIndex ..< word.endIndex
        }
        matchDifferences = changes.removals.map { change in
            guard case .remove(let offset, _, _) = change else { preconditionFailure() }
            let word = matchWords[offset]
            return word.startIndex ..< word.endIndex
        }

        if let sourceNext, let matchNext, Self.normalizedWords(of: sourceNext) != Self.normalizedWords(of: matchNext) {
            continuation = Continuation(expected: sourceNext, alternative: matchNext)
        } else {
            continuation = nil
        }

        let count = min(3, sourceWords.count / 2)
        if count > 0,
           sourceWords.suffix(count).map(Self.comparableWord) != matchWords.suffix(count).map(Self.comparableWord)
        {
            let answerStart = sourceWords[sourceWords.count - count].startIndex
            let prompt = source.text.text[..<answerStart].trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = String(source.text.text[answerStart...])
            ending = Ending(prompt: QuranText(prompt), answer: QuranText(answer))
        } else {
            ending = nil
        }
    }

    public let source: Verse
    public let match: Verse
    public let sourceDifferences: [Range<String.Index>]
    public let matchDifferences: [Range<String.Index>]
    public let continuation: Continuation?
    public let ending: Ending?

    private static func normalizedWords(of verse: Verse) -> [String] {
        words(in: verse.text).map(comparableWord)
    }

    private static func words(in text: QuranText) -> [Substring] {
        text.text.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }
    }

    private static func comparableWord(_ word: Substring) -> String {
        // Ignore Quranic pause symbols. Preserve the letters and vowels that distinguish readings.
        String(String.UnicodeScalarView(word.unicodeScalars.filter { !(0x06D6 ... 0x06DC).contains($0.value) }))
    }
}
