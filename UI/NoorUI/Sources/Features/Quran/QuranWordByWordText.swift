//
//  QuranWordByWordText.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import Localization
import NoorFont
import QuranAnnotations
import QuranKit
import QuranText
import SwiftUI
import UIx

/// One word of an ayah with its meaning, for word-by-word reading.
public struct QuranWordMeaning: Hashable, Sendable {
    public init(arabic: String, meaning: String?) {
        self.arabic = arabic
        self.meaning = meaning
    }

    public let arabic: String
    public let meaning: String?
}

/// An ayah as a right-to-left flow of words, each with its meaning in small text underneath.
@available(iOS 16.0, *)
public struct QuranWordByWordText: View {
    // MARK: Lifecycle

    public init(
        verse: AyahNumber,
        words: [QuranWordMeaning],
        quranFont: QuranFont,
        fontSize: FontSize,
        highlightedWord: Int? = nil
    ) {
        self.verse = verse
        self.words = words
        self.quranFont = quranFont
        self.fontSize = fontSize
        self.highlightedWord = highlightedWord
    }

    // MARK: Public

    public var body: some View {
        WrappingHStack(alignment: .topLeading, horizontalSpacing: wordSpacing, verticalSpacing: lineSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                wordCell(word, isHighlighted: highlightedWord == index + 1)
            }
            QuranTextView(QuranText(NumberFormatter.arabicNumberFormatter.format(verse.ayah)), quranFont: ayahMarkerFont)
                .dynamicTypeSize(fontSize.dynamicTypeSize)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.bottom, bottomPadding)
        .readableInsetsPadding(.horizontal)
    }

    // MARK: Private

    @ScaledMetric private var wordSpacing = 10
    @ScaledMetric private var lineSpacing = 8
    @ScaledMetric private var bottomPadding = 5
    @ScaledMetric private var cellPadding = 3
    @ScaledMetric private var cornerRadius = 6

    private let verse: AyahNumber
    private let words: [QuranWordMeaning]
    private let quranFont: QuranFont
    private let fontSize: FontSize
    private let highlightedWord: Int?

    private var ayahMarkerFont: QuranFont {
        quranFont == .indoPak ? .uthmanicHafs : quranFont
    }

    private func wordCell(_ word: QuranWordMeaning, isHighlighted: Bool) -> some View {
        VStack(spacing: 2) {
            QuranTextView(QuranText(word.arabic), quranFont: quranFont)
                .dynamicTypeSize(fontSize.dynamicTypeSize)
            if let meaning = word.meaning {
                Text(meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .fixedSize()
        .padding(cellPadding)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VerseOverlays.wordHighlightColor)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@available(iOS 16.0, *)
#Preview {
    QuranWordByWordText(
        verse: Quran.hafsMadani1405.suras[0].verses[1],
        words: [
            QuranWordMeaning(arabic: "ٱلۡحَمۡدُ", meaning: "All praises and thanks"),
            QuranWordMeaning(arabic: "لِلَّهِ", meaning: "(be) to Allah"),
            QuranWordMeaning(arabic: "رَبِّ", meaning: "the Lord"),
            QuranWordMeaning(arabic: "ٱلۡعَٰلَمِينَ", meaning: "of the universe"),
        ],
        quranFont: .uthmanicHafs,
        fontSize: .medium,
        highlightedWord: 2
    )
    .populateReadableInsets()
}
