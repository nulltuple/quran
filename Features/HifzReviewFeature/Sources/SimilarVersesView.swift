//
//  SimilarVersesView.swift
//

import Localization
import MemorizationService
import NoorUI
import QuranKit
import QuranText
import SwiftUI

struct SimilarVersesView: View {
    let model: SimilarVersesViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsMatches = false

    var body: some View {
        Group {
            if model.loadFailed {
                ContentUnavailableView {
                    Text(l("error.dialog.title"))
                } description: {
                    Text(l("error.message.general"))
                } actions: {
                    Button(lAndroid("download_retry")) {
                        Task { await retryLoad() }
                    }
                }
            } else if let matches = model.matches, matches.isEmpty {
                ContentUnavailableView {
                    Text(l("similar_verses.empty"))
                }
            } else if let comparison = model.comparison {
                ScrollView {
                    VStack(alignment: .leading) {
                        if let drill = model.drill {
                            drillContent(drill, comparison: comparison)
                        } else {
                            comparisonContent(comparison)
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.loadMatches() }
        .task(id: model.selection) { await model.compareSelection() }
    }

    @ViewBuilder
    private func comparisonContent(_ comparison: SimilarVerseComparison) -> some View {
        DisclosureGroup(l("similar_verses.compare_with"), isExpanded: $showsMatches) {
            LazyVStack(alignment: .leading) {
                ForEach(model.matches ?? [], id: \.self) { ayah in
                    Button {
                        showsMatches = false
                        model.selection = ayah
                    } label: {
                        reference(ayah)
                    }
                }
            }
        }

        let columns = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) :
            AnyLayout(HStackLayout(alignment: .top))
        columns {
            verseCard(comparison.source, differences: comparison.sourceDifferences)
            verseCard(comparison.match, differences: comparison.matchDifferences)
        }
        .environment(\.layoutDirection, .rightToLeft)

        if model.controlsAudio {
            Button(l("word_study.stop_hearing")) { model.stopPlayback() }
        }

        if comparison.continuation != nil {
            Button(l("similar_verses.continuation")) { model.startContinuation() }
                .buttonStyle(.bordered)
        }
        if comparison.ending != nil {
            Button(l("similar_verses.ending")) { model.startEnding() }
                .buttonStyle(.bordered)
        }
    }

    private func verseCard(_ verse: SimilarVerseComparison.Verse, differences: [Range<String.Index>]) -> some View {
        let marked = Set(differences.map(\.lowerBound))
        let segments = verse.text.text.split(whereSeparator: \.isWhitespace).map { word in
            QuranMarkedText.Segment(
                text: String(word),
                style: marked.contains(word.startIndex) ? .marked(.accentColor) : .plain
            )
        }
        return GroupBox {
            VStack(alignment: .leading) {
                QuranMarkedText(segments)
                VStack(alignment: .leading) {
                    Button(lAndroid("play")) { model.play(verse.id) }
                    Button(l("hifz_review.action.open_reader")) { model.jump(to: verse.id) }
                }
                .font(.subheadline)
            }
        } label: {
            reference(verse.id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func drillContent(_ drill: SimilarVersesViewModel.Drill, comparison: SimilarVerseComparison) -> some View {
        reference(comparison.source.id)
        switch drill {
        case .continuation(let continuation, let choices):
            Text(l("similar_verses.continuation"))
                .font(.headline)
            arabic(comparison.source.text)
            if model.correct == nil {
                ForEach(choices) { choice in
                    Button {
                        Task { await model.chooseContinuation(choice.id) }
                    } label: {
                        arabic(choice.text)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                feedback
                arabic(continuation.expected.text)
                reference(continuation.expected.id)
            }
        case .ending(let ending):
            Text(l("similar_verses.ending"))
                .font(.headline)
            arabic(ending.prompt)
            if model.isEndingRevealed {
                arabic(ending.answer)
                if model.correct == nil {
                    Button(l("hifz_practice.correct")) {
                        Task { await model.gradeEnding(correct: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(l("similar_verses.missed")) {
                        Task { await model.gradeEnding(correct: false) }
                    }
                    .buttonStyle(.bordered)
                } else {
                    feedback
                }
            } else {
                Button(l("similar_verses.reveal")) { model.revealEnding() }
                    .buttonStyle(.borderedProminent)
            }
        }

        Button(l("similar_verses.back")) { model.endDrill() }
            .disabled(model.saveState == .saving)
    }

    @ViewBuilder
    private var feedback: some View {
        Text(model.correct == true ? l("hifz_practice.correct") : l("similar_verses.incorrect"))
            .font(.headline)
        switch model.saveState {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView()
        case .saved:
            Text(l("hifz_test.results.saved_notice"))
                .foregroundStyle(.secondary)
        case .failed:
            Text(l("similar_verses.save_failed"))
            Button(lAndroid("download_retry")) {
                Task { await model.retrySave() }
            }
        }
    }

    private func reference(_ ayah: AyahNumber) -> some View {
        let reference: MultipartText = "\(ayah: ayah)"
        return reference.view(ofSize: .subheadline, allowsWrapping: true)
    }

    private func arabic(_ text: QuranText) -> some View {
        QuranTextView(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
    }

    private func retryLoad() async {
        if model.matches == nil {
            await model.loadMatches()
        } else {
            await model.compareSelection()
        }
    }
}
