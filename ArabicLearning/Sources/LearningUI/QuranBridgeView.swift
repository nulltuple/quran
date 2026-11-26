//
//  QuranBridgeView.swift
//  ArabicLearning (Arabican app)
//

import LearningModel
import Localization
import NoorFont
import NoorUI
import QuranKit
import SwiftUI
import UIx

/// The Quran tab: the bridge suras; each opens the learning-mode reader.
struct QuranBridgeView: View {
    let viewModel: BridgeViewModel

    var body: some View {
        content
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .failed:
            DataUnavailableView(
                title: String(localized: "bridge.error.title", bundle: .module),
                text: String(localized: "bridge.error.text", bundle: .module),
                image: .study
            )
        case .loaded(let suras):
            List(suras) { sura in
                NavigationLink {
                    BridgeReaderView(viewModel: viewModel.reader(for: sura))
                } label: {
                    VStack(alignment: .leading) {
                        Text(sura.title)
                        Text(String(
                            format: String(localized: "bridge.sura.subtitle", bundle: .module),
                            NumberFormatter.shared.format(sura.sura),
                            NumberFormatter.shared.format(sura.ayahs.count)
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// One sura, word by word: Arabic with its meaning under each word (or, in the meaning line, the
/// ayah's meaning with known words in Arabic: progressive substitution), the recited word
/// highlighted, and per ayah: listen, record yourself, play your recording.
struct BridgeReaderView: View {
    @State var viewModel: BridgeReaderViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if meaningLine {
                        knownWordsNote
                    }
                    ForEach(viewModel.sura.ayahs, id: \.ayah) { ayah in
                        ayahView(ayah)
                            .id(ayah.ayah)
                    }
                    Text("bridge.recording.privacy", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            // Follow the recitation one ayah at a time, only when a new ayah starts.
            .onChange(of: viewModel.recitedWord?.verse) { _, verse in
                guard let verse else { return }
                withAnimation(NoorAnimation.standard) { proxy.scrollTo(verse, anchor: .top) }
            }
        }
        .navigationTitle(viewModel.sura.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Picker(selection: $meaningLine) {
                    Text("bridge.display.underWords", bundle: .module).tag(false)
                    Text("bridge.display.line", bundle: .module).tag(true)
                } label: {
                    Label { Text("bridge.display", bundle: .module) } icon: { NoorSystemImage.translation.image }
                }
                // Both choices in the overflow menu itself, not in a submenu.
                .pickerStyle(.inline)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { viewModel.togglePlayback() } label: {
                    Label {
                        Text(viewModel.isPlaying ? "bridge.pause" : "bridge.play", bundle: .module)
                    } icon: {
                        (viewModel.isPlaying ? NoorSystemImage.pause : NoorSystemImage.play).image
                    }
                }
            }
        }
        .sheet(item: $viewModel.selected) { selected in
            WordSheet(selected: selected, language: viewModel.meaningLanguage) { viewModel.playWord(selected.word) }
                .presentationDetents([.medium, .large])
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.close() }
    }

    @ScaledMetric private var wordSize = 30.0
    @ScaledMetric private var lineWordSize = 24.0
    /// How meanings show; a per-device reading preference, like a reader's text size.
    @AppStorage("bridge.meaningLine") private var meaningLine = false

    /// The meaning line's key: a count of known words, never a share of the Quran (spec risk 8).
    private var knownWordsNote: some View {
        let known = viewModel.sura.words.filter { viewModel.knownWords.contains($0.word.word) }.count
        return Group {
            if known == 0 {
                Text("bridge.line.none", bundle: .module)
            } else {
                Text(String(
                    format: String(localized: "bridge.line.known", bundle: .module),
                    NumberFormatter.shared.format(known),
                    NumberFormatter.shared.format(viewModel.sura.words.count)
                ))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// The ayah's meaning word by word in reading order, each known word in Arabic instead.
    private func meaningLine(_ ayah: BridgeAyah) -> some View {
        WrappingHStack(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 6) {
            // Separate Texts: one string mixing Arabic and English would reorder by bidi rules.
            ForEach(Array(viewModel.meaningLine(ayah).enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .arabic(let run):
                    Text(run)
                        .font(.custom(.uthmanicHafs, size: lineWordSize, relativeTo: .body))
                        .foregroundStyle(Color.accentColor)
                case .meaning(let text):
                    Text(text)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func ayahView(_ ayah: BridgeAyah) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            WrappingHStack(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 12) {
                ForEach(ayah.words, id: \.word.word) { word in
                    wordButton(word)
                }
                Text(NumberFormatter.shared.format(ayah.ayah.ayah))
                    .font(.footnote.monospacedDigit())
                    .padding(6)
                    .background(Circle().stroke(.secondary))
                    .accessibilityLabel(String(
                        format: String(localized: "bridge.ayah", bundle: .module),
                        NumberFormatter.shared.format(ayah.ayah.ayah)
                    ))
            }
            .environment(\.layoutDirection, .rightToLeft)
            .frame(maxWidth: .infinity, alignment: .trailing)
            if meaningLine {
                meaningLine(ayah)
            }
            ayahControls(ayah)
        }
    }

    private func wordButton(_ word: BridgeWord) -> some View {
        let recited = viewModel.recitedWord == word.word.word
        return Button { viewModel.select(word) } label: {
            VStack(spacing: 4) {
                Text(word.word.text.text)
                    .font(.custom(.uthmanicHafs, size: wordSize, relativeTo: .title))
                if !meaningLine {
                    Text(viewModel.meaning(word))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(recited ? Color.accentColor.opacity(0.2) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word.word.text.text)
        .accessibilityValue(viewModel.meaning(word))
        .accessibilityHint(Text("bridge.word.hint", bundle: .module))
    }

    private func ayahControls(_ ayah: BridgeAyah) -> some View {
        let recorder = viewModel.recorder
        let mine = viewModel.recordingAyah == ayah.ayah
        let buttons = HStack {
            Button { viewModel.playAyah(ayah) } label: {
                Label { Text("bridge.listen", bundle: .module) } icon: { NoorSystemImage.play.image }
            }
            Button {
                Task { await viewModel.toggleRecording(ayah) }
            } label: {
                if mine, recorder.state == .recording {
                    Label { Text("bridge.record.stop", bundle: .module) } icon: { NoorSystemImage.stop.image }
                } else {
                    Text("bridge.record", bundle: .module)
                }
            }
            .tint(mine && recorder.state == .recording ? .red : nil)
            if mine, recorder.state == .recorded {
                Button { viewModel.playRecording() } label: {
                    Text("bridge.record.play", bundle: .module)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        return VStack(alignment: .trailing) {
            buttons
            if mine, recorder.state == .denied {
                Text("bridge.record.denied", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// A tapped word: meaning in context (English and Bengali), transliteration, and its parts with
/// lemma, root, part of speech and how often the lemma occurs in the Quran (a count, never a
/// percentage of the Quran "understood": spec risk 8).
private struct WordSheet: View {
    let selected: BridgeReaderViewModel.SelectedWord
    let language: MeaningLanguage
    let play: () -> Void

    @ScaledMetric private var wordSize = 44.0

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text(selected.word.word.text.text)
                        .font(.custom(.uthmanicHafs, size: wordSize, relativeTo: .largeTitle))
                    Text(selected.word.meaning.transliteration)
                        .font(.headline)
                    Button(action: play) {
                        Label { Text("bridge.listen", bundle: .module) } icon: { NoorSystemImage.play.image }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                // The profile's language first.
                ForEach(language == .english ? [MeaningLanguage.english, .bengali] : [.bengali, .english], id: \.self) { shown in
                    LabeledContent(shown.name, value: shown.text(selected.word.meaning))
                }
            } header: {
                Text("bridge.word.meaning", bundle: .module)
            }
            if !selected.segments.isEmpty {
                Section {
                    ForEach(Array(selected.segments.enumerated()), id: \.offset) { _, segment in
                        segmentRow(segment)
                    }
                } header: {
                    Text("bridge.word.parts", bundle: .module)
                }
            }
        }
    }

    private func segmentRow(_ segment: WordSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(segment.partOfSpeech).font(.headline)
                Spacer()
                Text(segment.text).font(.custom(.uthmanicHafs, size: wordSize * 0.6, relativeTo: .title2))
            }
            if let lemma = segment.lemma {
                let gloss = language.gloss(lemma)
                if !gloss.isEmpty {
                    Text(gloss)
                }
                // Arabic and English in separate Texts: one mixed string would reorder by bidi rules.
                HStack {
                    Text("bridge.word.lemma", bundle: .module)
                    Text(lemma.text).font(.custom(.uthmanicHafs, size: wordSize * 0.45, relativeTo: .subheadline))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(String(format: String(localized: "bridge.word.count", bundle: .module), NumberFormatter.shared.format(lemma.occurrences)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !segment.root.isEmpty {
                Text(String(format: String(localized: "bridge.word.root", bundle: .module), segment.root.map(String.init).joined(separator: " ")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
