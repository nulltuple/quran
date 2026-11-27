//
//  HifzMapView.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Localization
import MemorizationService
import NoorUI
import QuranKit
import QuranLocalization
import SwiftUI
import UIx

/// Juz → Surah → Ayah memorization map with state colors and explicit text labels (roadmap H3).
struct HifzMapView: View {
    let summary: MemorizationMapSummary
    let practiceRange: (ClosedRange<AyahNumber>) -> Void
    let openAyah: (AyahNumber) -> Void

    var body: some View {
        NoorList {
            NoorBasicSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        lFormat(
                            "hifz_review.map.declared_summary",
                            NumberFormatter.shared.format(summary.declaredVerseCount),
                            NumberFormatter.shared.format(summary.totalVerses)
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(
                        lFormat(
                            "hifz_review.map.demonstrated_summary",
                            NumberFormatter.shared.format(summary.demonstratedVerseCount),
                            NumberFormatter.shared.format(summary.totalVerses)
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    StateDistributionBar(counts: summary.counts, total: summary.totalVerses)
                    StateLegendView(counts: summary.counts)
                }
                .padding(.vertical, 4)
            }

            NoorBasicSection(title: lAndroid("quran_juz2")) {
                ForEach(summary.juzs) { juzSummary in
                    NavigationLink {
                        JuzDetailMapView(
                            juzSummary: juzSummary,
                            practiceRange: practiceRange,
                            openAyah: openAyah
                        )
                    } label: {
                        juzRow(juzSummary)
                    }
                }
            }
        }
    }

    private func juzRow(_ juzSummary: JuzMemorizationSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(juzSummary.juz.localizedName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(
                    lFormat(
                        "hifz_review.declare.verse_count",
                        NumberFormatter.shared.format(juzSummary.totalVerses)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(
                lFormat(
                    "hifz_review.map.juz_summary",
                    NumberFormatter.shared.format(juzSummary.declaredCount),
                    NumberFormatter.shared.format(juzSummary.demonstratedCount)
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            StateDistributionBar(counts: juzSummary.counts, total: juzSummary.totalVerses)
        }
        .padding(.vertical, 4)
    }
}

private struct JuzDetailMapView: View {
    let juzSummary: JuzMemorizationSummary
    let practiceRange: (ClosedRange<AyahNumber>) -> Void
    let openAyah: (AyahNumber) -> Void

    var body: some View {
        NoorList {
            NoorBasicSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        lFormat(
                            "hifz_review.map.juz_summary",
                            NumberFormatter.shared.format(juzSummary.declaredCount),
                            NumberFormatter.shared.format(juzSummary.demonstratedCount)
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                    StateDistributionBar(counts: juzSummary.counts, total: juzSummary.totalVerses)
                    StateLegendView(counts: juzSummary.counts)
                }
                .padding(.vertical, 4)
            }

            NoorBasicSection(title: lAndroid("quran_sura")) {
                ForEach(juzSummary.suras) { slice in
                    NavigationLink {
                        SuraAyahMapView(
                            slice: slice,
                            practiceRange: practiceRange,
                            openAyah: openAyah
                        )
                    } label: {
                        suraRow(slice)
                    }
                }
            }
        }
        .navigationTitle(juzSummary.juz.localizedName)
    }

    private func suraRow(_ slice: JuzSuraSlice) -> some View {
        let first = AyahNumber(sura: slice.sura, ayah: slice.firstAyah)!
        let last = AyahNumber(sura: slice.sura, ayah: slice.lastAyah)!
        let title: MultipartText = "\(ayahRange: first ... last)"

        return VStack(alignment: .leading, spacing: 6) {
            title.view(ofSize: .body, allowsWrapping: true)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(
                lFormat(
                    "hifz_review.map.juz_summary",
                    NumberFormatter.shared.format(slice.declaredCount),
                    NumberFormatter.shared.format(slice.demonstratedCount)
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            StateDistributionBar(counts: slice.counts, total: slice.totalVerses)
        }
        .padding(.vertical, 4)
    }
}

struct SuraAyahMapView: View {
    // MARK: Internal

    let slice: JuzSuraSlice
    let practiceRange: (ClosedRange<AyahNumber>) -> Void
    let openAyah: (AyahNumber) -> Void

    var body: some View {
        let first = AyahNumber(sura: slice.sura, ayah: slice.firstAyah)!
        let last = AyahNumber(sura: slice.sura, ayah: slice.lastAyah)!

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        lFormat(
                            "hifz_review.map.juz_summary",
                            NumberFormatter.shared.format(slice.declaredCount),
                            NumberFormatter.shared.format(slice.demonstratedCount)
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                    StateDistributionBar(counts: slice.counts, total: slice.totalVerses)
                    StateLegendView(counts: slice.counts)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cellSize), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(Array(slice.ayahStates.enumerated()), id: \.offset) { offset, state in
                        let ayahNum = slice.firstAyah + offset
                        if let ayah = AyahNumber(sura: slice.sura, ayah: ayahNum) {
                            ayahCell(ayah: ayah, state: state)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(slice.sura.localizedName())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(l("hifz_review.action.practice")) {
                    practiceRange(first ... last)
                }
            }
        }
    }

    // MARK: Private

    @ScaledMetric(relativeTo: .body) private var cellSize: CGFloat = 76

    private func ayahCell(ayah: AyahNumber, state: AyahMemorizationState) -> some View {
        let color = HifzReviewFormatting.stateColor(state)
        let label = HifzReviewFormatting.stateLabel(state)
        let isHighlighted = state != .notMemorized

        return Menu {
            Button {
                practiceRange(ayah ... ayah)
            } label: {
                Label {
                    Text(l("hifz_review.action.practice"))
                } icon: {
                    NoorSystemImage.hifzPractice.image
                }
            }
            Button {
                openAyah(ayah)
            } label: {
                Label {
                    Text(l("hifz_review.action.open_reader"))
                } icon: {
                    NoorSystemImage.book.image
                }
            }
        } label: {
            VStack(spacing: 3) {
                Text(NumberFormatter.shared.format(ayah.ayah))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isHighlighted ? .white : .primary)
                Text(label)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isHighlighted ? .white.opacity(0.92) : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: cellSize)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color)
            )
        }
        .accessibilityLabel("\(ayah.localizedName), \(label)")
    }
}

private struct StateDistributionBar: View {
    let counts: [AyahMemorizationState: Int]
    let total: Int

    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 8

    private static let orderedStates: [AyahMemorizationState] = [
        .strong, .weak, .learning, .declaredUnassessed, .notMemorized,
    ]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Self.orderedStates, id: \.self) { state in
                    let count = counts[state] ?? 0
                    if count > 0, total > 0 {
                        Rectangle()
                            .fill(HifzReviewFormatting.stateColor(state))
                            .frame(width: proxy.size.width * CGFloat(count) / CGFloat(total))
                    }
                }
            }
        }
        .frame(height: barHeight)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

private struct StateLegendView: View {
    let counts: [AyahMemorizationState: Int]

    private static let orderedStates: [AyahMemorizationState] = [
        .strong, .weak, .learning, .declaredUnassessed, .notMemorized,
    ]

    var body: some View {
        WrappingHStack(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(Self.orderedStates, id: \.self) { state in
                let count = counts[state] ?? 0
                HStack(spacing: 4) {
                    Circle()
                        .fill(HifzReviewFormatting.stateColor(state))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("\(HifzReviewFormatting.stateLabel(state)): \(NumberFormatter.shared.format(count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
