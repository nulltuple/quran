//
//  QuranArabicText.swift
//
//
//  Created by Mohamed Afifi on 2024-02-10.
//

import Localization
import NoorFont
import QuranAnnotations
import QuranKit
import QuranText
import SwiftUI
import UIx

public struct QuranArabicText: View {
    @ScaledMetric var bottomPadding = 5

    let verse: AyahNumber
    let text: QuranText
    let quranFont: QuranFont
    let fontSize: FontSize
    /// The recited word, counting the text's space-separated words from 1.
    let highlightedWord: Int?

    public init(verse: AyahNumber, text: QuranText, quranFont: QuranFont, fontSize: FontSize, highlightedWord: Int? = nil) {
        self.verse = verse
        self.text = text
        self.quranFont = quranFont
        self.fontSize = fontSize
        self.highlightedWord = highlightedWord
    }

    public var body: some View {
        QuranTextView(
            text,
            quranFont: quranFont,
            highlighting: wordHighlighting,
            fontOverrides: ayahMarkerFontOverrides
        )
        .dynamicTypeSize(fontSize.dynamicTypeSize)
        .textAlignment(follows: .rightToLeft)
        .padding(.bottom, bottomPadding)
        .readableInsetsPadding(.horizontal)
    }

    var wordHighlighting: [HighlightingRange] {
        guard let highlightedWord, let range = text.text.wordRange(at: highlightedWord) else {
            return []
        }
        return [HighlightingRange(range, backgroundColor: VerseOverlays.wordHighlightColor)]
    }

    var ayahMarkerFontOverrides: [QuranTextFontOverride] {
        guard quranFont == .indoPak else {
            return []
        }
        let marker = NumberFormatter.arabicNumberFormatter.format(verse.ayah)
        guard let range = text.text.range(of: marker, options: .backwards),
              range.upperBound == text.text.endIndex
        else {
            return []
        }
        return [QuranTextFontOverride(range: range, quranFont: .uthmanicHafs)]
    }
}

extension String {
    /// The range of the space-separated word at `number`, counting from 1.
    func wordRange(at number: Int) -> Range<String.Index>? {
        guard number > 0 else {
            return nil
        }
        var count = 0
        var index = startIndex
        while index < endIndex {
            guard let start = self[index...].firstIndex(where: { !$0.isWhitespace }) else {
                return nil
            }
            let end = self[start...].firstIndex(where: \.isWhitespace) ?? endIndex
            count += 1
            if count == number {
                return start ..< end
            }
            index = end
        }
        return nil
    }
}
