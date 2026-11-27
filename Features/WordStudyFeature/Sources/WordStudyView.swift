//
//  WordStudyView.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Localization
import NoorUI
import QuranAudioKit
import QuranKit
import QuranLocalization
import QuranText
import ReciterService
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
            .onDisappear { viewModel.didDisappear() }
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
            WordStudyContent(
                study: study,
                hearing: viewModel.hearing,
                quranFont: quranFont,
                fontSize: fontSize,
                toggleHearing: { Task { await viewModel.toggleHearing() } },
                select: viewModel.select
            )
        }
    }
}

private struct WordStudyContent: View {
    // MARK: Internal

    let study: WordStudy
    let hearing: WordStudyViewModel.Hearing
    let quranFont: QuranFont
    let fontSize: FontSize
    let toggleHearing: () -> Void
    let select: (WordStudyTerm) -> Void

    var body: some View {
        List {
            Section {
                header
            }
            if let recitation = hearing.recitation {
                Section {
                    hearRow
                } footer: {
                    hearFooter(recitation)
                }
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

    /// Plays the word, or stops it while it plays.
    private var hearRow: some View {
        Button(action: toggleHearing) {
            HStack {
                Label {
                    Text(hearing.isPlaying ? l("word_study.stop_hearing") : l("word_study.hear"))
                } icon: {
                    (hearing.isPlaying ? NoorSystemImage.stop : NoorSystemImage.hearWord).image
                }
                Spacer()
                if hearing.isPlaying {
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func hearFooter(_ recitation: WordRecitation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if case .failed = hearing {
                Text(l("word_study.hear_failed"))
                    .foregroundStyle(Color(uiColor: .systemRed))
            }
            Text(lFormat("word_study.hear_excerpt", recitation.reciter.localizedName))
            if !recitation.isDownloaded {
                Text(l("word_study.hear_streams"))
            }
        }
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

private extension WordStudyViewModel.Hearing {
    var recitation: WordRecitation? {
        switch self {
        case .unavailable: nil
        case .ready(let recitation), .playing(let recitation), .failed(let recitation): recitation
        }
    }

    var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }
}
