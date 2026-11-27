//
//  QuranPracticeMask.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import SwiftUI

/// Covers hidden words on a Quran page during Hifz practice: the page background, so the text is
/// gone and the layout never moves, with a faint tint showing where the words are.
public struct QuranPracticeMask: View {
    // MARK: Lifecycle

    public init(rects: [CGRect]) {
        self.rects = rects
    }

    // MARK: Public

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: min(rect.height / 4, 6))
                    .fill(themeColors.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: min(rect.height / 4, 6))
                            .fill(themeColors.text.opacity(0.07))
                    }
                    // A little taller than the glyph frames, which clip some diacritics.
                    .frame(width: rect.width + 2, height: rect.height + 4)
                    .offset(x: rect.minX - 1, y: rect.minY - 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    // MARK: Private

    @Environment(\.themeColors) private var themeColors

    private let rects: [CGRect]
}
