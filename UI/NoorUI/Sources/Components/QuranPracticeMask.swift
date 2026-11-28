//
//  QuranPracticeMask.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import SwiftUI

/// Covers hidden words on a Quran page during Hifz practice: paints `themeColors.background` so the
/// hidden text disappears without shifting the Mushaf layout, and draws a crisp horizontal baseline
/// rule (`#DCDBDC` light) under each hidden span (or a red baseline when a live stumble was detected
/// on the next hidden word).
public struct QuranPracticeMask: View {
    // MARK: Lifecycle

    public init(rects: [CGRect], pendingMistakeRects: [CGRect] = []) {
        self.rects = rects
        self.pendingMistakeRects = pendingMistakeRects
    }

    // MARK: Public

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                // A little taller than the glyph frames, which clip some diacritics.
                Rectangle()
                    .fill(themeColors.background)
                    .frame(width: rect.width + 2, height: rect.height + 4)
                    .offset(x: rect.minX - 1, y: rect.minY - 2)
                Rectangle()
                    .fill(Color.practiceHiddenBaseline)
                    .frame(width: max(4, rect.width), height: 1)
                    .offset(x: rect.minX, y: rect.maxY - 2)
            }
            ForEach(Array(pendingMistakeRects.enumerated()), id: \.offset) { _, rect in
                Rectangle()
                    .fill(Color.practiceMistakeWord)
                    .frame(width: max(6, rect.width), height: 1.5)
                    .offset(x: rect.minX, y: rect.maxY - 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    // MARK: Private

    @Environment(\.themeColors) private var themeColors

    private let rects: [CGRect]
    private let pendingMistakeRects: [CGRect]
}
