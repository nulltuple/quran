//
//  ImageDecorationsLayout.swift
//

import QuranAnnotations
import QuranGeometry
import QuranKit
import SwiftUI

/// Decoration rectangles in the image view's local coordinate space.
struct ImageDecorationsLayout {
    let verseHighlights: [VerseHighlightPlacement]
    let wordHighlight: WordHighlightPlacement?
    let wordCaption: WordCaptionPlacement?
    let scrollWord: ScrollWordPlacement?
    let undimmedLineRects: [CGRect]?
    let suraHeaders: [SuraHeaderPlacement]
    let ayahMarkers: [AyahMarkerPlacement]

    var drawnAyahMarkers: [AyahMarkerPlacement] {
        drawsAyahNumbersAndSuraHeaders ? ayahMarkers : []
    }

    private let drawsAyahNumbersAndSuraHeaders: Bool

    init(decorations: ImageDecorations, imageSize: CGSize, scale: WordFrameScale) {
        drawsAyahNumbersAndSuraHeaders = decorations.drawsAyahNumbersAndSuraHeaders
        ayahMarkers = decorations.ayahNumbers.map {
            AyahMarkerPlacement(
                ayah: $0.ayah,
                frame: $0.scaledRectangle(imageSize: imageSize, widthRatio: decorations.ayahNumberWidthRatio, scale: scale)
            )
        }
        suraHeaders = decorations.drawsAyahNumbersAndSuraHeaders ? decorations.suraHeaders.map {
            SuraHeaderPlacement(id: $0, frame: $0.rect.scaled(by: scale))
        } : []
        verseHighlights = decorations.verseHighlights
            .sorted { $0.key < $1.key }
            .compactMap { verse, color in
                let lineRects = Self.lineRects(of: decorations.wordFrames.wordFramesForVerse(verse), scale: scale)
                return lineRects.isEmpty ? nil : VerseHighlightPlacement(id: verse, lineRects: lineRects, color: color)
            }
        undimmedLineRects = decorations.undimmedVerses.map { undimmedVerses in
            undimmedVerses.sorted().flatMap {
                Self.lineRects(of: decorations.wordFrames.wordFramesForVerse($0), scale: scale)
            }
        }
        wordHighlight = Self.wordRect(from: decorations.wordHighlight, to: decorations.wordHighlightEnd, in: decorations.wordFrames)
            .map { WordHighlightPlacement(frame: $0.scaled(by: scale), color: VerseOverlays.wordHighlightColor) }
        wordCaption = zip(decorations.wordCaption, wordHighlight).map { text, highlight in
            WordCaptionPlacement(text: text, wordFrame: highlight.frame)
        }
        scrollWord = decorations.scrollWord.flatMap { word in
            decorations.wordFrames.wordFrameForWord(word).map {
                ScrollWordPlacement(word: word, frame: $0.rect.scaled(by: scale))
            }
        }
    }

    /// The frame of glyph `first`, joined with the glyphs up to `last` on the same line.
    private static func wordRect(from first: Word?, to last: Word?, in frames: WordFrameCollection) -> CGRect? {
        guard let first, let firstFrame = frames.wordFrameForWord(first) else {
            return nil
        }
        guard let last, last.verse == first.verse, last.wordNumber > first.wordNumber else {
            return firstFrame.rect
        }
        return (first.wordNumber + 1 ... last.wordNumber).reduce(firstFrame.rect) { rect, number in
            guard let frame = frames.wordFrameForWord(Word(verse: first.verse, wordNumber: number)),
                  frame.line == firstFrame.line
            else {
                return rect
            }
            return rect.union(frame.rect)
        }
    }

    struct WordCaptionPlacement {
        let text: String
        let wordFrame: CGRect
    }

    struct ScrollWordPlacement {
        let word: Word
        let frame: CGRect
    }

    struct VerseHighlightPlacement: Identifiable {
        let id: AyahNumber
        /// The union of the verse's word frames on each line, top to bottom.
        let lineRects: [CGRect]
        let color: Color
    }

    struct WordHighlightPlacement {
        let frame: CGRect
        let color: Color
    }

    struct SuraHeaderPlacement: Identifiable {
        let id: SuraHeaderLocation
        let frame: CGRect
    }

    private static func lineRects(of frames: [WordFrame], scale: WordFrameScale) -> [CGRect] {
        Dictionary(grouping: frames, by: \.line)
            .sorted { $0.key < $1.key }
            .map { _, frames in
                frames.map(\.rect).reduce(CGRect.null) { $0.union($1) }.scaled(by: scale)
            }
    }
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
