//
//  DiagnosticsView.swift
//
//
//  Created by Mohamed Afifi on 2023-12-09.
//

import Localization
import NoorUI
import SwiftUI
import UIx

struct DiagnosticsView: View {
    @StateObject var viewModel: DiagnosticsViewModel

    var body: some View {
        DiagnosticsViewUI(
            appVersion: viewModel.appVersion,
            error: $viewModel.error,
            enableDebugLogging: $viewModel.enableDebugLogging,
            isDebugLoggingAlwaysEnabled: viewModel.isDebugLoggingAlwaysEnabled,
            enableDebugLoggingFooter: viewModel.enableDebugLoggingFooter,
            showDeveloperTools: $viewModel.showDeveloperTools,
            copyAppVersion: { viewModel.copyAppVersion() },
            shareLog: { viewModel.shareLogs() },
            openRecitationLab: { viewModel.openRecitationLab() }
        )
    }
}

private struct DiagnosticsViewUI: View {
    let appVersion: String
    @Binding var error: Error?
    @Binding var enableDebugLogging: Bool
    let isDebugLoggingAlwaysEnabled: Bool
    let enableDebugLoggingFooter: String
    @Binding var showDeveloperTools: Bool
    let copyAppVersion: Action
    let shareLog: Action
    var openRecitationLab: Action = {}

    var body: some View {
        NoorList {
            NoorBasicSection {
                Text(l("diagnostics.details"))
                    .foregroundColor(Color.secondaryLabel)
                    .listRowBackground(Color.clear)
            }

            NoorBasicSection {
                NoorListItem(
                    title: .text(l("setting.app_version")),
                    subtitle: .init(text: .text(appVersion), location: .trailing)
                )
                .contextMenu {
                    Button(action: copyAppVersion) {
                        Label { Text(l("ayah.menu.copy")) } icon: { NoorSystemImage.copy.image }
                    }
                }
                .accessibilityAction(named: Text(l("ayah.menu.copy")), copyAppVersion)
            }

            NoorBasicSection(footer: enableDebugLoggingFooter) {
                Toggle(isOn: $enableDebugLogging) {
                    Text(l("diagnostics.enable_debug_logs"))
                }
                .disabled(isDebugLoggingAlwaysEnabled)
            }

            NoorBasicSection {
                NoorListItem(
                    title: .text(l("diagnostics.share_app_logs")),
                    action: .sync { shareLog() }
                )
            }

            // Developer screens (V0 deliverable 8): English only, not in the catalogs.
            NoorBasicSection(footer: "Recitation Lab: live recitation recognition with the on-device model.") {
                Toggle(isOn: $showDeveloperTools) {
                    Text("Developer tools")
                }
                if showDeveloperTools {
                    NoorListItem(
                        title: .text("Recitation Lab"),
                        action: .sync { openRecitationLab() }
                    )
                }
            }
        }
        .errorAlert(error: $error)
    }
}

#Preview {
    struct Container: View {
        @State var error: Error?
        @State var enableDebugLogging = true
        @State var showDeveloperTools = true

        var body: some View {
            DiagnosticsViewUI(
                appVersion: "2.4.0 (310)",
                error: $error,
                enableDebugLogging: $enableDebugLogging,
                isDebugLoggingAlwaysEnabled: false,
                enableDebugLoggingFooter: l("diagnostics.enable_debug_logs.details"),
                showDeveloperTools: $showDeveloperTools,
                copyAppVersion: {},
                shareLog: {}
            )
        }
    }
    return Container()
}
