//
//  ImageDecorations.swift
//

import QuranGeometry
import QuranKit
import SwiftUI

public struct ImageDecorations {
    /// A single word (or multi-glyph word span) highlighted on the page's mistake heatmap (roadmap H7).
    public struct WordHeatmapHighlight: Equatable {
        public let first: Word
        public let last: Word?
        public let fillColor: Color
        public let underlineColor: Color

        public init(first: Word, last: Word? = nil, fillColor: Color, underlineColor: Color) {
            self.first = first
            self.last = last
            self.fillColor = fillColor
            self.underlineColor = underlineColor
        }
    }

    public var suraHeaders: [SuraHeaderLocation]
    public var ayahNumbers: [AyahNumberLocation]
    public var ayahNumberWidthRatio: CGFloat
    public var drawsAyahNumbersAndSuraHeaders: Bool
    public var chromeStyle: QuranPageChromeStyle
    public var wordFrames: WordFrameCollection
    /// The page's text extent in image coordinates, for the header to line up with.
    public var textColumn: ClosedRange<CGFloat>?
    public var verseHighlights: [AyahNumber: Color]
    /// Word-level mistake heatmap highlights (image glyph numbering).
    public var wordHeatmapHighlights: [WordHeatmapHighlight]
    public var wordHighlight: Word?
    /// The last glyph of a word the image draws as several, from `wordHighlight` on.
    public var wordHighlightEnd: Word?
    public var undimmedVerses: Set<AyahNumber>?
    /// A meaning drawn under `wordHighlight`, for word-by-word recitation.
    public var wordCaption: String?
    /// A word content keeps in view, such as the recited word.
    public var scrollWord: Word?
    /// Page-image words Hifz practice hides (image glyph numbering).
    public var maskedWords: Set<Word>

    public init(
        suraHeaders: [SuraHeaderLocation],
        ayahNumbers: [AyahNumberLocation],
        ayahNumberWidthRatio: CGFloat = AyahMarkerWidthRatio.imagePage,
        drawsAyahNumbersAndSuraHeaders: Bool,
        chromeStyle: QuranPageChromeStyle,
        wordFrames: WordFrameCollection,
        textColumn: ClosedRange<CGFloat>? = nil,
        verseHighlights: [AyahNumber: Color] = [:],
        wordHeatmapHighlights: [WordHeatmapHighlight] = [],
        wordHighlight: Word? = nil,
        wordHighlightEnd: Word? = nil,
        undimmedVerses: Set<AyahNumber>? = nil,
        wordCaption: String? = nil,
        scrollWord: Word? = nil,
        maskedWords: Set<Word> = []
    ) {
        self.suraHeaders = suraHeaders
        self.ayahNumbers = ayahNumbers
        self.ayahNumberWidthRatio = ayahNumberWidthRatio
        self.drawsAyahNumbersAndSuraHeaders = drawsAyahNumbersAndSuraHeaders
        self.chromeStyle = chromeStyle
        self.wordFrames = wordFrames
        self.textColumn = textColumn
        self.verseHighlights = verseHighlights
        self.wordHeatmapHighlights = wordHeatmapHighlights
        self.wordHighlight = wordHighlight
        self.wordHighlightEnd = wordHighlightEnd
        self.undimmedVerses = undimmedVerses
        self.wordCaption = wordCaption
        self.scrollWord = scrollWord
        self.maskedWords = maskedWords
    }
}
