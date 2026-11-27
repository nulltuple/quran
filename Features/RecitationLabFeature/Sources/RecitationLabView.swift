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

// A developer screen behind Settings > Diagnostics > debug logging: its text is English only and
// not in the localization catalogs (V0 (c) trail, Decisions).

struct RecitationLabView: View {
    @StateObject var viewModel: RecitationLabViewModel

    var body: some View {
        RecitationLabViewUI(
            modelState: viewModel.modelState,
            recordingState: viewModel.recordingState,
            canRecord: viewModel.canRecord,
            result: viewModel.result,
            error: $viewModel.error,
            download: { await viewModel.downloadModel() },
            start: { await viewModel.startRecording() },
            stop: { await viewModel.stopRecording() }
        )
        .task { await viewModel.load() }
    }
}

private struct RecitationLabViewUI: View {
    let modelState: RecitationLabViewModel.ModelState
    let recordingState: RecitationLabViewModel.RecordingState
    let canRecord: Bool
    let result: RecitationLabViewModel.Result?
    @Binding var error: Error?
    let download: AsyncAction
    let start: AsyncAction
    let stop: AsyncAction

    var body: some View {
        NoorList {
            NoorBasicSection(footer: "Recordings stay in memory on this device and are discarded; nothing is saved or sent.") {
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

            if let result {
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
                        title: .text("Recognition"),
                        subtitle: .init(text: .text("\(result.recognitionMilliseconds) ms"), location: .trailing)
                    )
                    NoorListItem(
                        title: .text("Real-time factor"),
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
}
