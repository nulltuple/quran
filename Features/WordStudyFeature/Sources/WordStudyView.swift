//
//  WordStudyView.swift
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

struct WordStudyView: View {
    @ObservedObject var viewModel: WordStudyViewModel
    let quranFont: QuranFont
    let fontSize: FontSize

    var body: some View {
        content
            .task { await viewModel.load() }
            .onAppear { viewModel.didAppear() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            DataUnavailableView(
                title: l("word_study.unavailable"),
                text: "",
                image: .wordStudy
            )
        case .loaded(let study):
            WordStudyContent(study: study, quranFont: quranFont, fontSize: fontSize, select: viewModel.select)
        }
    }
}

private struct WordStudyContent: View {
    // MARK: Internal

    let study: WordStudy
    let quranFont: QuranFont
    let fontSize: FontSize
    let select: (WordStudyTerm) -> Void

    var body: some View {
        List {
            Section {
                header
            }
            Section(l("word_study.parts")) {
                ForEach(Array(study.morphology.segments.enumerated()), id: \.offset) { _, segment in
                    segmentRow(segment)
                }
            }
            if let head = study.morphology.headSegment, head.root != nil || head.lemma != nil {
                Section {
                    if let root = head.root {
                        termRow(title: l("word_study.root"), arabic: root.spacedLetters, term: .root(root))
                    }
                    if let lemma = head.lemma {
                        termRow(title: l("word_study.lemma"), arabic: lemma.text, term: .lemma(lemma))
                    }
                } footer: {
                    Text(l("word_study.source"))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Private

    private var header: some View {
        VStack(spacing: 4) {
            QuranTextView(QuranText(study.arabic), quranFont: quranFont)
                .dynamicTypeSize(fontSize.dynamicTypeSize)
                .environment(\.layoutDirection, .rightToLeft)
            if let transliteration = study.transliteration {
                Text(transliteration)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            if let meaning = study.meaning {
                Text(meaning)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            Text(lFormat("word_study.word_reference", study.word.verse.localizedName, NumberFormatter.shared.format(study.word.wordNumber)))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func segmentRow(_ segment: MorphologySegment) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let role = roleName(segment.grammar.role) {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(WordGrammarText.description(segment.grammar))
                // A second stem (مِمَّا: مِن + مَا) names its own dictionary form; the head's is below.
                if let lemma = segment.lemma, segment.grammar.role == .stem, segment != study.morphology.headSegment {
                    QuranTextView(QuranText(lemma.text), quranFont: quranFont)
                        .foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            Spacer()
            if !segment.text.isEmpty {
                QuranTextView(QuranText(segment.text), quranFont: quranFont)
                    .dynamicTypeSize(fontSize.dynamicTypeSize)
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A root or dictionary form row; it opens every word in the Quran that shares it.
    private func termRow(title: String, arabic: String, term: WordStudyTerm) -> some View {
        Button {
            select(term)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.primary)
                    Text(lFormat("word_study.occurrences", NumberFormatter.shared.format(term.occurrences)))
                        .font(.footnote)
                        // A button label takes the tint; keep the row's text neutral.
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer()
                QuranTextView(QuranText(arabic), quranFont: quranFont)
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
        .accessibilityHint(l("word_study.occurrences_hint"))
    }

    private func roleName(_ role: WordGrammar.Role) -> String? {
        switch role {
        case .prefix: l("word_study.prefix")
        case .suffix: l("word_study.suffix")
        case .stem: nil
        }
    }
}
