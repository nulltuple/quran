//
//  DiagnosticsViewModel.swift
//
//
//  Created by Mohamed Afifi on 2023-12-10.
//

import Combine
import Localization
import RecitationLabFeature
import SystemDependencies
import UIKit

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    // MARK: Lifecycle

    init(
        diagnosticsService: DiagnosticsService,
        isDebugLoggingAlwaysEnabled: Bool,
        bundle: SystemBundle,
        navigationController: UINavigationController?,
        recitationLabBuilder: RecitationLabBuilder
    ) {
        self.diagnosticsService = diagnosticsService
        self.isDebugLoggingAlwaysEnabled = isDebugLoggingAlwaysEnabled
        self.bundle = bundle
        self.navigationController = navigationController
        self.recitationLabBuilder = recitationLabBuilder
    }

    // MARK: Internal

    let isDebugLoggingAlwaysEnabled: Bool

    @Published var error: Error? = nil

    /// The version and build, such as `2.4.0 (310)`, so a bug report can name the exact build.
    var appVersion: String {
        let text = copyableAppVersion
        guard !text.isEmpty else {
            return ""
        }
        // Isolate it left to right, so right-to-left languages don't move the build before the version.
        return "\u{2066}\(text)\u{2069}"
    }

    /// The version and build without the isolates, so it pastes as plain text.
    var copyableAppVersion: String {
        bundle.versionAndBuild ?? ""
    }

    var enableDebugLoggingFooter: String {
        isDebugLoggingAlwaysEnabled
            ? l("diagnostics.enable_debug_logs.always_on")
            : l("diagnostics.enable_debug_logs.details")
    }

    var enableDebugLogging: Bool {
        get { isDebugLoggingAlwaysEnabled || savedEnableDebugLogging }
        set {
            guard !isDebugLoggingAlwaysEnabled else {
                return
            }
            savedEnableDebugLogging = newValue
        }
    }

    /// Developer screens (the V0 Recitation Lab), off by default.
    var showDeveloperTools: Bool {
        get { savedShowDeveloperTools }
        set { savedShowDeveloperTools = newValue }
    }

    func openRecitationLab() {
        navigationController?.pushViewController(recitationLabBuilder.build(), animated: true)
    }

    func copyAppVersion() {
        let text = copyableAppVersion
        guard !text.isEmpty else {
            return
        }
        UIPasteboard.general.string = text
    }

    func shareLogs() {
        do {
            let diagnosticsZip = try diagnosticsService.buildDiagnosticsZip()
            navigationController?.share([diagnosticsZip.url]) {
                diagnosticsZip.cleanUp()
            }
        } catch {
            self.error = error
        }
    }

    // MARK: Private

    private let diagnosticsService: DiagnosticsService
    private let bundle: SystemBundle
    private let recitationLabBuilder: RecitationLabBuilder
    private weak var navigationController: UINavigationController?

    @Published private var savedEnableDebugLogging = DiagnosticsPreferences.shared.enableDebugLogging {
        didSet {
            DiagnosticsPreferences.shared.enableDebugLogging = savedEnableDebugLogging
        }
    }

    @Published private var savedShowDeveloperTools = DiagnosticsPreferences.shared.showDeveloperTools {
        didSet {
            DiagnosticsPreferences.shared.showDeveloperTools = savedShowDeveloperTools
        }
    }
}
