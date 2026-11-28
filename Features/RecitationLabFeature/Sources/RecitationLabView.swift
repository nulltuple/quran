//
//  RecitationLabView.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import NoorUI
import RecitationRecognition
import SwiftUI
import UIx

// A developer screen behind Settings > Diagnostics > Developer tools: its text is English only and
// not in the localization catalogs (V0 (c) trail, Decisions).

struct RecitationLabView: View {
    @StateObject var viewModel: RecitationLabViewModel

    var body: some View {
        RecitationLabViewUI(
            modelState: viewModel.modelState,
            phoneticModelState: viewModel.phoneticModelState,
            recordingState: viewModel.recordingState,
            canRecord: viewModel.canRecord,
            targetVerseOverride: $viewModel.targetVerseOverride,
            result: viewModel.result,
            error: $viewModel.error,
            download: { await viewModel.downloadModel() },
            downloadPhonetic: { await viewModel.downloadPhoneticModel() },
            start: { await viewModel.startRecording() },
            stop: { await viewModel.stopRecording() }
        )
        .task { await viewModel.load() }
    }
}

private struct RecitationLabViewUI: View {
    let modelState: RecitationLabViewModel.ModelState
    let phoneticModelState: RecitationLabViewModel.ModelState
    let recordingState: RecitationLabViewModel.RecordingState
    let canRecord: Bool
    @Binding var targetVerseOverride: String
    let result: RecitationLabViewModel.Result?
    @Binding var error: Error?
    let download: AsyncAction
    let downloadPhonetic: AsyncAction
    let start: AsyncAction
    let stop: AsyncAction

    var body: some View {
        NoorList {
            NoorBasicSection(
                title: "Recitation Engine (Tilawi V0)",
                footer: "Recordings stay in memory on this device and are discarded; nothing is saved or sent."
            ) {
                Text(modelDescription)
                    .foregroundColor(.secondaryLabel)
                    .textSelection(.enabled)
                switch modelState {
                case .notInstalled, .failed:
                    Button { Task { await download() } } label: {
                        Text("Download the model (84 MB)")
                    }
                case .downloading(let progress):
                    ProgressView(value: progress)
                case .loading, .ready:
                    recordButton
                }
            }

            NoorBasicSection(
                title: "Pronunciation Engine (V4 · Lab Only)",
                footer: "Lab only: clear pronunciation (phonemes & vowels) is kept separate from memorization and tajweed. Qualified reviewer sign-off is required before user release."
            ) {
                Text(phoneticModelDescription)
                    .foregroundColor(.secondaryLabel)
                    .textSelection(.enabled)
                switch phoneticModelState {
                case .notInstalled, .failed:
                    Button { Task { await downloadPhonetic() } } label: {
                        Text("Download phonetic model (21 MB)")
                    }
                case .downloading(let progress):
                    ProgressView(value: progress)
                case .loading, .ready:
                    TextField("Target verse override (optional, e.g. 112:1)", text: $targetVerseOverride)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            if let result {
                if let pronunciation = result.pronunciation {
                    NoorBasicSection(title: "Pronunciation Assessment (\(pronunciation.targetRange))") {
                        NoorListItem(
                            title: .text("Phoneme match"),
                            subtitle: .init(text: .text(String(format: "%.1f%%", pronunciation.phonemeMatchRate * 100)), location: .trailing)
                        )
                        NoorListItem(
                            title: .text("Confirmed mistakes"),
                            subtitle: .init(text: .text("\(pronunciation.confirmedMistakeCount)"), location: .trailing)
                        )
                        NoorListItem(
                            title: .text("Uncertain (not flagged)"),
                            subtitle: .init(text: .text("\(pronunciation.uncertainCount)"), location: .trailing)
                        )
                        NoorListItem(
                            title: .text("Phonetic inference"),
                            subtitle: .init(text: .text("\(pronunciation.inferenceMilliseconds) ms"), location: .trailing)
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Expected QPS")
                                .font(.caption)
                                .foregroundColor(.secondaryLabel)
                            Text(pronunciation.expectedPhonemes)
                                .environment(\.layoutDirection, .rightToLeft)
                                .textSelection(.enabled)
                            Text("Heard QPS")
                                .font(.caption)
                                .foregroundColor(.secondaryLabel)
                            Text(pronunciation.heardPhonemes.isEmpty ? "(nothing heard)" : pronunciation.heardPhonemes)
                                .environment(\.layoutDirection, .rightToLeft)
                                .textSelection(.enabled)
                        }
                        ForEach(pronunciation.words) { word in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(word.displayText)
                                        .environment(\.layoutDirection, .rightToLeft)
                                    Spacer()
                                    Text(statusLabel(word.status))
                                        .font(.caption)
                                        .foregroundColor(statusColor(word.status))
                                }
                                Text("exp: \(word.expectedPhonemes) · heard: \(word.heardPhonemes.isEmpty ? "—" : word.heardPhonemes)")
                                    .font(.caption)
                                    .foregroundColor(.secondaryLabel)
                                ForEach(Array(word.issueSummaries.enumerated()), id: \.offset) { _, summary in
                                    Text(summary)
                                        .font(.caption)
                                        .foregroundColor(statusColor(word.status))
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                NoorBasicSection(title: result.isConfident ? "Verses (confident)" : "Verses (not confident)") {
                    if result.candidates.isEmpty {
                        Text("No verse found")
                    }
                    ForEach(result.candidates) { candidate in
                        NoorListItem(
                            title: .text(candidate.range),
                            subtitle: .init(text: .text(score(candidate.score)), location: .trailing)
                        )
                    }
                }

                NoorBasicSection(title: "Transcript") {
                    Text(result.transcript.isEmpty ? "(nothing heard)" : result.transcript)
                        .environment(\.layoutDirection, .rightToLeft)
                        .textSelection(.enabled)
                }

                if !result.words.isEmpty {
                    NoorBasicSection(title: "Words (first candidate)") {
                        ForEach(result.words) { word in
                            VStack(alignment: .leading) {
                                Text("\(kindName(word.kind)) \(seconds(word.seconds))")
                                    .font(.caption)
                                    .foregroundColor(word.kind == .matched ? .secondaryLabel : .red)
                                Text(word.expected.isEmpty ? "—" : word.expected)
                                Text(word.recognized.isEmpty ? "—" : "heard: \(word.recognized)")
                                    .foregroundColor(.secondaryLabel)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                NoorBasicSection(title: "Measurements") {
                    NoorListItem(title: .text("Audio"), subtitle: .init(text: .text(String(format: "%.1f s", result.audioSeconds)), location: .trailing))
                    NoorListItem(
                        title: .text("Input peak"),
                        subtitle: .init(text: .text(String(format: "%.0f dBFS", result.peakDecibels)), location: .trailing)
                    )
                    NoorListItem(
                        title: .text("Tilawi recognition"),
                        subtitle: .init(text: .text("\(result.recognitionMilliseconds) ms"), location: .trailing)
                    )
                    NoorListItem(
                        title: .text("Tilawi RTF"),
                        subtitle: .init(text: .text(String(format: "%.3f", result.realTimeFactor)), location: .trailing)
                    )
                    if let megabytes = result.footprintMegabytes {
                        NoorListItem(title: .text("Memory footprint"), subtitle: .init(text: .text("\(megabytes) MB"), location: .trailing))
                    }
                }
            }
        }
        .errorAlert(error: $error)
    }

    @ViewBuilder private var recordButton: some View {
        switch recordingState {
        case .idle:
            Button { Task { await start() } } label: {
                Text("Record")
            }
            .disabled(!canRecord)
        case .recording(let seconds):
            Button { Task { await stop() } } label: {
                Text(String(format: "Stop and recognize (%.0f s of %.0f)", seconds, RecitationMicrophone.maximumSeconds))
            }
        case .recognizing:
            HStack {
                ProgressView()
                Text("Recognizing…")
            }
        }
    }

    private var modelDescription: String {
        switch modelState {
        case .loading:
            return "Loading the recitation model…"
        case .notInstalled(let directory):
            return "No recitation model is installed. Download it (GitHub release recitation-model-1, 125 MB once unpacked), or copy \(RecitationModelStore.packageName) and \(RecitationModelStore.vocabularyName) from `make recitation-model` into:\n\(directory)"
        case .downloading(let progress):
            return String(format: "Downloading the recitation model… %.0f%%", progress * 100)
        case .failed(let message):
            return "The recitation model failed to load: \(message)"
        case .ready(let milliseconds):
            return "Model ready (loaded in \(milliseconds) ms). Recite up to \(Int(RecitationMicrophone.maximumSeconds)) s, then stop."
        }
    }

    private var phoneticModelDescription: String {
        switch phoneticModelState {
        case .loading:
            return "Loading the phonetic assessment model…"
        case .notInstalled(let directory):
            return "Phonetic model not installed. Download `phonetic-model-1` (21 MB zip, HisnLabs Tajweed v2 int8 + 6,236-ayah QPS reference), or run `make phonetic-model` and copy into:\n\(directory)"
        case .downloading(let progress):
            return String(format: "Downloading the phonetic model… %.0f%%", progress * 100)
        case .failed(let message):
            return "The phonetic model failed to load: \(message)"
        case .ready(let milliseconds):
            return "Phonetic model ready (loaded in \(milliseconds) ms, HisnLabs Tajweed v2 Core ML int8)."
        }
    }

    private func score(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func seconds(_ range: ClosedRange<Double>?) -> String {
        guard let range else { return "" }
        return String(format: "%.2f–%.2f s", range.lowerBound, range.upperBound)
    }

    private func kindName(_ kind: WordAlignmentStep.Kind) -> String {
        switch kind {
        case .matched: return "matched"
        case .mismatched: return "mismatched"
        case .omitted: return "omitted"
        case .inserted: return "inserted"
        }
    }

    private func statusLabel(_ status: WordPronunciationAssessment.Status) -> String {
        switch status {
        case .correct: "OK"
        case .mistake: "Mistake"
        case .uncertain: "Uncertain"
        }
    }

    private func statusColor(_ status: WordPronunciationAssessment.Status) -> Color {
        switch status {
        case .correct: .secondaryLabel
        case .mistake: .red
        case .uncertain: .orange
        }
    }
}
