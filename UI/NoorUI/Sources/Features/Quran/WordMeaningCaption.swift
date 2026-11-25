//
//  WordMeaningCaption.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import SwiftUI
import UIx

/// A word's meaning in a small label centered under the word on a page image.
struct WordMeaningCaption: View {
    let text: String
    let wordFrame: CGRect

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .fixedSize()
            // Centered under the word, overflowing its width when the meaning is wider.
            .frame(width: max(wordFrame.width, 1), alignment: .top)
            .offset(x: wordFrame.minX, y: wordFrame.maxY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.layoutDirection, .leftToRight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ScaledMetric private var horizontalPadding = 6
    @ScaledMetric private var verticalPadding = 2
    @ScaledMetric private var cornerRadius = 6
}
