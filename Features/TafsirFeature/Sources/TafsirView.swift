//
//  TafsirView.swift
//

import Localization
import NoorUI
import QuranKit
import QuranText
import QuranTextKit
import QuranTranslationFeature
import ReadingService
import SwiftUI
import UIx

struct TafsirView: View {
    // MARK: Lifecycle

    init(viewModel: TafsirViewModel, downloadTafsir: @escaping () -> Void) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.downloadTafsir = downloadTafsir
    }

    // MARK: Internal

    var body: some View {
        Group {
            switch viewModel.content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .noTafsirs:
                noTafsirs
            case .failed:
                failed
            case .loaded(let passage):
                ScrollView {
                    passageView(passage)
                }
            }
        }
        .populateReadableInsets()
        .themedBackground()
        .themedForeground()
        .populateThemeStyle()
    }

    // MARK: Private

    @ObservedObject private var viewModel: TafsirViewModel
    private let fontSizePreferences = FontSizePreferences.shared
    private let readingPreferences = ReadingPreferences.shared

    private let downloadTafsir: () -> Void

    private var noTafsirs: some View {
        VStack(spacing: 12) {
            NoorSystemImage.tafsir.image
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(l("tafsir.empty.title"))
                .font(.headline)
            Text(l("tafsir.empty.message"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(l("tafsir.empty.download"), action: downloadTafsir)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failed: some View {
        VStack(spacing: 12) {
            Text(l("error.translation.text-retrieval"))
                .multilineTextAlignment(.center)
            Button(lAndroid("download_retry")) {
                Task { await viewModel.retry() }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func passageView(_ passage: TafsirPassage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(passage)
            QuranArabicText(
                verse: passage.text.lastVerse,
                text: passage.arabicText,
                quranFont: readingPreferences.reading.quranFont,
                fontSize: fontSizePreferences.arabicFontSize
            )
            .padding(.vertical)
            tafsirText(passage)
        }
        .padding(.bottom)
    }

    private func header(_ passage: TafsirPassage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.tafsirs.count > 1 {
                Picker(l("tafsir.title"), selection: selection) {
                    ForEach(viewModel.tafsirs, id: \.id) { tafsir in
                        Text(tafsir.displayName).tag(tafsir.id)
                    }
                }
                .pickerStyle(.menu)
            }
            let range: MultipartText = "\(ayahRange: passage.text.firstVerse ... passage.text.lastVerse)"
            range.view(ofSize: .body)
            if passage.text.coversSeveralVerses {
                Text(l("tafsir.passage-note"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top)
        .readableInsetsPadding(.horizontal)
    }

    @ViewBuilder
    private func tafsirText(_ passage: TafsirPassage) -> some View {
        let tafsir = passage.tafsir
        let fontSize = fontSizePreferences.translationFontSize
        if let text = passage.text.text {
            QuranTranslationTextChunk(
                text: text.text,
                chunk: text.text.startIndex ..< text.text.endIndex,
                footnoteRanges: text.footnoteRanges,
                quranRanges: text.quranRanges,
                firstChunk: true,
                readMoreURL: nil,
                footnoteURL: { _ in Self.footnoteAnchor },
                font: tafsir.textFont,
                fontSize: fontSize,
                characterDirection: tafsir.characterDirection
            )
            // Every footnote is shown below the text, so a footnote marker has nothing to open.
            .tryOpenURL { _ in .handled }
            ForEach(Array(zip(text.footnoteRanges, text.footnotes.indices)), id: \.1) { markerRange, index in
                let footnote = text.footnoteText(at: index)
                QuranTranslationFootnoteChunk(
                    text: footnote,
                    chunk: footnote.startIndex ..< footnote.endIndex,
                    marker: String(text.text[markerRange]),
                    font: tafsir.footnoteFont,
                    fontSize: fontSize,
                    characterDirection: tafsir.characterDirection
                )
            }
        } else {
            Text(l("tafsir.no-text"))
                .foregroundColor(.secondary)
                .padding(.vertical)
                .readableInsetsPadding(.horizontal)
        }
        QuranTranslatorName(name: tafsir.translationName, fontSize: fontSize, characterDirection: tafsir.characterDirection)
    }

    private static let footnoteAnchor = URL(string: "quran-tafsir://footnote")!

    private var selection: Binding<Translation.ID> {
        Binding(
            get: { viewModel.selectedTafsir?.id ?? 0 },
            set: { id in
                guard let tafsir = viewModel.tafsirs.first(where: { $0.id == id }) else {
                    return
                }
                Task { await viewModel.select(tafsir) }
            }
        )
    }
}
