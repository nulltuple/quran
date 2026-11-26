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

/// One sura, word by word: Arabic with its meaning under each word, the recited word highlighted,
/// and per ayah: listen, record yourself, play your recording.
struct BridgeReaderView: View {
    @State var viewModel: BridgeReaderViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
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
            WordSheet(selected: selected) { viewModel.playWord(selected.word) }
                .presentationDetents([.medium, .large])
        }
        .task { await viewModel.loadSegments() }
        .onDisappear { viewModel.close() }
    }

    @ScaledMetric private var wordSize = 30.0

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
            ayahControls(ayah)
        }
    }

    private func wordButton(_ word: BridgeWord) -> some View {
        let recited = viewModel.recitedWord == word.word.word
        return Button { viewModel.select(word) } label: {
            VStack(spacing: 4) {
                Text(word.word.text.text)
                    .font(.custom(.uthmanicHafs, size: wordSize, relativeTo: .title))
                Text(word.meaning.english)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(recited ? Color.accentColor.opacity(0.2) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word.word.text.text)
        .accessibilityValue(word.meaning.english)
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
                LabeledContent(String(localized: "bridge.word.english", bundle: .module), value: selected.word.meaning.english)
                LabeledContent(String(localized: "bridge.word.bengali", bundle: .module), value: selected.word.meaning.bengali)
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
                if !lemma.english.isEmpty {
                    Text(lemma.english)
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
