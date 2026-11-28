//
//  ImageDecorations.swift
//

import QuranGeometry
import QuranKit
import SwiftUI

public struct ImageDecorations {
    /// A single word (or multi-glyph word span) highlighted on the page's mistake heatmap or live practice.
    public struct WordHeatmapHighlight: Equatable {
        public let first: Word
        public let last: Word?
        public let fillColor: Color
        public let underlineColor: Color
        public let dottedUnderline: Bool

        public init(
            first: Word,
            last: Word? = nil,
            fillColor: Color,
            underlineColor: Color,
            dottedUnderline: Bool = false
        ) {
            self.first = first
            self.last = last
            self.fillColor = fillColor
            self.underlineColor = underlineColor
            self.dottedUnderline = dottedUnderline
        }
    }

    /// Direct ink recoloring of a word's calligraphy glyphs on the Mushaf image (used for the active
    /// live-practice green cursor and red mistake words).
    public struct WordGlyphTint: Equatable {
        public let first: Word
        public let last: Word?
        public let color: Color

        public init(first: Word, last: Word? = nil, color: Color) {
            self.first = first
            self.last = last
            self.color = color
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
    /// Word-level mistake heatmap / live practice background & underline highlights (image glyph numbering).
    public var wordHeatmapHighlights: [WordHeatmapHighlight]
    /// Word-level glyph ink tints masked onto the Mushaf calligraphy (image glyph numbering).
    public var wordGlyphTints: [WordGlyphTint]
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
    /// Subset of `maskedWords` whose hidden baseline rule renders red (pending live stumble).
    public var pendingMistakeMaskWords: Set<Word>

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
        wordGlyphTints: [WordGlyphTint] = [],
        wordHighlight: Word? = nil,
        wordHighlightEnd: Word? = nil,
        undimmedVerses: Set<AyahNumber>? = nil,
        wordCaption: String? = nil,
        scrollWord: Word? = nil,
        maskedWords: Set<Word> = [],
        pendingMistakeMaskWords: Set<Word> = []
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
        self.wordGlyphTints = wordGlyphTints
        self.wordHighlight = wordHighlight
        self.wordHighlightEnd = wordHighlightEnd
        self.undimmedVerses = undimmedVerses
        self.wordCaption = wordCaption
        self.scrollWord = scrollWord
        self.maskedWords = maskedWords
        self.pendingMistakeMaskWords = pendingMistakeMaskWords
    }
}
