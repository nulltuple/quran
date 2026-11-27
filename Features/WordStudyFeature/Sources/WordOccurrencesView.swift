//
//  WordOccurrencesView.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Localization
import NoorUI
import QuranKit
import QuranLocalization
import QuranText
import SwiftUI
import WordTextService

/// Every word sharing a root or dictionary form, in Quran order; a row opens that word's study.
struct WordOccurrencesView: View {
    // MARK: Internal

    @ObservedObject var viewModel: WordOccurrencesViewModel
    let arabic: String
    let quranFont: QuranFont
    let fontSize: FontSize

    var body: some View {
        if viewModel.failed, viewModel.occurrences.isEmpty {
            DataUnavailableView(title: l("word_study.unavailable"), text: "", image: .wordStudy)
        } else {
            list
        }
    }

    // MARK: Private

    private var list: some View {
        List {
            Section {
                header
            }
            Section {
                ForEach(viewModel.occurrences, id: \.word) { occurrence in
                    row(occurrence)
                }
                if !viewModel.isComplete, !viewModel.failed {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        // Runs again after each page while the row stays on screen; cancelled when it scrolls away.
                        .task(id: viewModel.occurrences.count) {
                            await viewModel.loadNextPage()
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var header: some View {
        VStack(spacing: 4) {
            QuranTextView(QuranText(arabic), quranFont: quranFont)
                .dynamicTypeSize(fontSize.dynamicTypeSize)
                .environment(\.layoutDirection, .rightToLeft)
            Text(lFormat("word_study.occurrences", NumberFormatter.shared.format(viewModel.term.occurrences)))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func row(_ occurrence: WordOccurrence) -> some View {
        Button {
            viewModel.select(occurrence)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let meaning = occurrence.meaning {
                        Text(meaning)
                            .foregroundStyle(Color.primary)
                    }
                    Text(lFormat(
                        "word_study.word_reference",
                        occurrence.word.verse.localizedName,
                        NumberFormatter.shared.format(occurrence.word.wordNumber)
                    ))
                    .font(.footnote)
                    // A button label takes the tint; keep the row's text neutral.
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer()
                QuranTextView(QuranText(occurrence.arabic), quranFont: quranFont)
                    .dynamicTypeSize(fontSize.dynamicTypeSize)
                    .environment(\.layoutDirection, .rightToLeft)
                    .foregroundStyle(Color.primary)
                NoorSystemImage.disclosure.image
                    .flipsForRightToLeftLayoutDirection(true)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
    }
}
