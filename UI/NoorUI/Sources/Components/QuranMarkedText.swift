//
//  QuranMarkedText.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import NoorFont
import SwiftUI

/// Quran text in the Quran font, flowing right to left, with some words marked by color, an
/// underline or a strikethrough (recite and check's result).
public struct QuranMarkedText: View {
    // MARK: Lifecycle

    public init(_ segments: [Segment], quranFont: QuranFont = .uthmanicHafs) {
        self.segments = segments
        self.quranFont = quranFont
    }

    // MARK: Public

    public struct Segment: Hashable {
        public enum Style: Hashable {
            case plain
            /// Colored and underlined.
            case marked(Color)
            /// Colored and struck through: a word left out.
            case struck(Color)
            /// Faded: a word not reached.
            case faded
        }

        public init(text: String, style: Style) {
            self.text = text
            self.style = style
        }

        public let text: String
        public let style: Style
    }

    public var body: some View {
        Text(attributed)
            .font(.custom(quranFont.fontName, size: fontSize, relativeTo: .title3))
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: Private

    @ScaledMetric private var lineSpacing = 8.0

    private let segments: [Segment]
    private let quranFont: QuranFont
    private let fontSize: CGFloat = 24

    private var attributed: AttributedString {
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result += AttributedString(" ")
            }
            var piece = AttributedString(segment.text)
            switch segment.style {
            case .plain:
                break
            case .marked(let color):
                piece.foregroundColor = color
                piece.underlineStyle = .single
            case .struck(let color):
                piece.foregroundColor = color
                piece.strikethroughStyle = .single
            case .faded:
                piece.foregroundColor = .secondary
            }
            result += piece
        }
        return result
    }
}

#Preview {
    QuranMarkedText([
        .init(text: "قُلۡ", style: .plain),
        .init(text: "هُوَ", style: .struck(.red)),
        .init(text: "ٱللَّهُ", style: .marked(.orange)),
        .init(text: "أَحَدٌ", style: .faded),
    ])
    .padding()
}
