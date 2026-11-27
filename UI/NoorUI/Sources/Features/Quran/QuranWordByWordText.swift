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
    public init(arabic: String, meaning: String?, transliteration: String? = nil) {
        self.arabic = arabic
        self.meaning = meaning
        self.transliteration = transliteration
    }

    public let arabic: String
    public let meaning: String?
    /// How the word sounds in Latin letters; `nil` unless the reader shows transliterations.
    public let transliteration: String?

    /// What VoiceOver reads for the word, in the order the cell shows it: the Arabic, its
    /// transliteration, then its meaning.
    var accessibilityLabel: String {
        [arabic, transliteration, meaning].compactMap { $0 }.joined(separator: ", ")
    }
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
        highlightedWord: Int? = nil,
        onWordTapped: ((Int) -> Void)? = nil
    ) {
        self.verse = verse
        self.words = words
        self.quranFont = quranFont
        self.fontSize = fontSize
        self.highlightedWord = highlightedWord
        self.onWordTapped = onWordTapped
    }

    // MARK: Public

    public var body: some View {
        WrappingHStack(alignment: .topLeading, horizontalSpacing: wordSpacing, verticalSpacing: lineSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                wordCell(word, position: index + 1)
            }
            QuranTextView(QuranText(NumberFormatter.arabicNumberFormatter.format(verse.ayah)), quranFont: ayahMarkerFont)
                .dynamicTypeSize(fontSize.dynamicTypeSize)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.bottom, bottomPadding)
        .readableInsetsPadding(.horizontal)
    }

    // MARK: Internal

    /// A recited word reads as selected; a word that opens word study reads as a button.
    static func accessibilityTraits(isHighlighted: Bool, isTappable: Bool) -> AccessibilityTraits {
        var traits: AccessibilityTraits = []
        if isHighlighted {
            traits.formUnion(.isSelected)
        }
        if isTappable {
            traits.formUnion(.isButton)
        }
        return traits
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
    /// Called with a word's position in `words`, from 1, when the reader taps it.
    private let onWordTapped: ((Int) -> Void)?

    private var ayahMarkerFont: QuranFont {
        quranFont == .indoPak ? .uthmanicHafs : quranFont
    }

    private func wordCell(_ word: QuranWordMeaning, position: Int) -> some View {
        let isHighlighted = highlightedWord == position
        return VStack(spacing: 2) {
            QuranTextView(QuranText(word.arabic), quranFont: quranFont)
                .dynamicTypeSize(fontSize.dynamicTypeSize)
            if let transliteration = word.transliteration {
                Text(transliteration)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .leftToRight)
            }
            if let meaning = word.meaning {
                Text(meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        // Each cell keeps its natural width, but no more than the column's: at large text sizes a
        // long meaning wraps under its word instead of pushing the ayah off screen.
        .fixedSize(horizontal: false, vertical: true)
        .padding(cellPadding)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VerseOverlays.wordHighlightColor)
            }
        }
        .modifier(WordTap(action: onWordTapped.map { tapped in { tapped(position) } }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.accessibilityLabel)
        // The recited word reads as selected, so VoiceOver users hear which word is playing.
        .accessibilityAddTraits(Self.accessibilityTraits(isHighlighted: isHighlighted, isTappable: onWordTapped != nil))
        .accessibilityHint(onWordTapped == nil ? "" : l("word_study.hint"))
        .accessibilityAction { onWordTapped?(position) }
    }
}

/// A tap, not a Button: the page's long press (the ayah menu) must still start on a word. Without
/// an action the word takes no tap, so the reader's own tap handling is unchanged.
private struct WordTap: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded(action))
        } else {
            content
        }
    }
}

@available(iOS 16.0, *)
#Preview {
    QuranWordByWordText(
        verse: Quran.hafsMadani1405.suras[0].verses[1],
        words: [
            QuranWordMeaning(arabic: "ٱلۡحَمۡدُ", meaning: "All praises and thanks", transliteration: "al-ḥamdu"),
            QuranWordMeaning(arabic: "لِلَّهِ", meaning: "(be) to Allah", transliteration: "lillahi"),
            QuranWordMeaning(arabic: "رَبِّ", meaning: "the Lord", transliteration: "rabbi"),
            QuranWordMeaning(arabic: "ٱلۡعَٰلَمِينَ", meaning: "of the universe", transliteration: "l-ʿālamīna"),
        ],
        quranFont: .uthmanicHafs,
        fontSize: .medium,
        highlightedWord: 2
    )
    .populateReadableInsets()
}
