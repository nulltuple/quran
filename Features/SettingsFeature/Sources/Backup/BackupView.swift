//
//  BackupView.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import BackupService
import Localization
import NoorUI
import SwiftUI
import UIx
import UniformTypeIdentifiers

struct BackupView: View {
    @StateObject var viewModel: BackupViewModel

    var body: some View {
        BackupViewUI(
            state: viewModel.state,
            error: $viewModel.error,
            isReplaceConfirmationPresented: $viewModel.isReplaceConfirmationPresented,
            isRestoredAlertPresented: $viewModel.isRestoredAlertPresented,
            exportBackup: { await viewModel.exportBackup() },
            chooseBackup: { viewModel.presentImporter() },
            merge: { await viewModel.restore(.merge) },
            confirmReplace: { viewModel.confirmReplace() },
            replace: { await viewModel.restore(.replace) },
            cancelPreview: { viewModel.cancelPreview() }
        )
        .fileImporter(isPresented: $viewModel.isImporterPresented, allowedContentTypes: [.json]) { result in
            Task { await viewModel.importFile(result) }
        }
    }
}

private struct BackupViewUI: View {
    // MARK: Internal

    let state: BackupViewModel.State
    @Binding var error: Error?
    @Binding var isReplaceConfirmationPresented: Bool
    @Binding var isRestoredAlertPresented: Bool
    let exportBackup: AsyncAction
    let chooseBackup: Action
    let merge: AsyncAction
    let confirmReplace: Action
    let replace: AsyncAction
    let cancelPreview: Action

    var body: some View {
        NoorList {
            NoorBasicSection(footer: l("backup.export.footer")) {
                NoorListItem(
                    image: .init(.exportBackup),
                    title: .text(l("backup.export")),
                    action: .async { await exportBackup() }
                )
            }

            NoorBasicSection(footer: l("backup.restore.footer")) {
                NoorListItem(
                    image: .init(.restoreBackup),
                    title: .text(l("backup.restore")),
                    action: .sync { chooseBackup() }
                )
            }

            if case .preview(let summary) = state {
                preview(summary)
            }

            if state == .working {
                NoorBasicSection {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .disabled(state == .working)
        .noorListIconColumn()
        .errorAlert(error: $error)
        .alert(l("backup.replace.confirm.title"), isPresented: $isReplaceConfirmationPresented) {
            Button(lAndroid("cancel"), role: .cancel) {}
            Button(l("backup.replace"), role: .destructive) {
                Task { await replace() }
            }
        } message: {
            Text(l("backup.replace.confirm.message"))
        }
        .alert(l("backup.restored"), isPresented: $isRestoredAlertPresented) {
            Button(lAndroid("dialog_ok")) {}
        }
    }

    // MARK: Private

    /// A medium date and short time with the app's digits.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .fixedCurrentLocaleNumbers
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    @ViewBuilder
    private func preview(_ summary: BackupSummary) -> some View {
        NoorBasicSection(
            title: lFormat("backup.preview.title", Self.dateFormatter.string(from: summary.exportedAt)),
            footer: summary.isEmpty ? l("backup.preview.empty") : l("backup.preview.footer")
        ) {
            countRow(l("backup.count.notes"), summary.notes)
            countRow(l("backup.count.highlights"), summary.highlights)
            countRow(l("backup.count.page-bookmarks"), summary.pageBookmarks)
            countRow(l("backup.count.collections"), summary.collections)
            countRow(l("backup.count.collection-ayahs"), summary.collectionVerses)
            countRow(l("backup.count.recent-pages"), summary.recentPages)
            countRow(l("backup.count.practice-sessions"), summary.practiceSessions)
            countRow(l("backup.count.memorized-ranges"), summary.memorizedRanges)
            countRow(l("backup.count.goals"), summary.studyGoals)
            countRow(l("backup.count.activity-logs"), summary.activityLogs)
        }

        NoorBasicSection {
            NoorListItem(
                title: .text(l("backup.merge")),
                titleColor: .accentColor,
                action: .async { await merge() }
            )
            .disabled(summary.isEmpty)

            NoorListItem(
                title: .text(l("backup.replace")),
                titleColor: .red,
                action: .sync { confirmReplace() }
            )
            .disabled(summary.isEmpty)

            NoorListItem(
                title: .text(lAndroid("cancel")),
                action: .sync { cancelPreview() }
            )
        }
    }

    private func countRow(_ title: String, _ count: Int) -> some View {
        NoorListItem(
            title: .text(title),
            subtitle: .init(text: .text(NumberFormatter.shared.format(count)), location: .trailing)
        )
    }
}

#Preview {
    BackupViewUI(
        state: .idle,
        error: .constant(nil),
        isReplaceConfirmationPresented: .constant(false),
        isRestoredAlertPresented: .constant(false),
        exportBackup: {},
        chooseBackup: {},
        merge: {},
        confirmReplace: {},
        replace: {},
        cancelPreview: {}
    )
}
