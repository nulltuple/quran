//
//  ImageDecorationsView.swift
//

import SwiftUI
import UIx

struct ImageDecorationsView: View {
    let layout: ImageDecorationsLayout
    let chromeStyle: QuranPageChromeStyle

    var body: some View {
        ZStack(alignment: .topLeading) {
            highlights
            suraHeaders
            ayahNumbers
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: Private

    @Environment(\.quranPageColorScheme) private var quranPageColorScheme
    @Environment(\.themeColors) private var themeColors

    private var chromePalette: QuranPageChromePalette {
        chromeStyle.palette(for: quranPageColorScheme, text: themeColors.text)
    }

    private var highlights: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.verseHighlights) { placement in
                QuranHighlightShape(lineRects: placement.lineRects)
                    .fill(placement.color)
            }
            ForEach(layout.wordHeatmaps) { placement in
                QuranHighlightShape.word(placement.frame)
                    .fill(placement.fillColor)
                if placement.dottedUnderline {
                    Path { path in
                        let y = placement.frame.maxY - 1
                        path.move(to: CGPoint(x: placement.frame.minX + 2, y: y))
                        path.addLine(to: CGPoint(x: max(placement.frame.minX + 6, placement.frame.maxX - 2), y: y))
                    }
                    .stroke(
                        placement.underlineColor,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5])
                    )
                } else {
                    let barHeight = max(2, min(3, placement.frame.height * 0.08))
                    Capsule()
                        .fill(placement.underlineColor)
                        .placed(in: CGRect(
                            x: placement.frame.minX + 2,
                            y: placement.frame.maxY - barHeight,
                            width: max(4, placement.frame.width - 4),
                            height: barHeight
                        ))
                }
            }
            if let word = layout.wordHighlight {
                QuranHighlightShape.word(word.frame)
                    .fill(word.color)
            }
        }
    }

    private var suraHeaders: some View {
        ForEach(layout.suraHeaders) { placement in
            SuraHeaderView(tint: chromePalette.header)
                .placed(in: placement.frame)
        }
    }

    private var ayahNumbers: some View {
        ForEach(layout.drawnAyahMarkers, id: \.ayah) { placement in
            AyahNumberView(number: placement.ayah.ayah, palette: chromePalette)
                .placed(in: placement.frame)
        }
    }
}
