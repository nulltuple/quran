//
//  DiagnosticsViewModelTests.swift
//
//
//  Created by Mohamed Afifi on 2026-10-12.
//

import AppDependenciesFake
import Localization
import RecitationLabFeature
import SystemDependenciesFake
import XCTest
@testable import SettingsFeature

@MainActor
final class DiagnosticsViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        originalEnableDebugLogging = DiagnosticsPreferences.shared.enableDebugLogging
        originalShowDeveloperTools = DiagnosticsPreferences.shared.showDeveloperTools
    }

    override func tearDownWithError() throws {
        DiagnosticsPreferences.shared.enableDebugLogging = originalEnableDebugLogging
        DiagnosticsPreferences.shared.showDeveloperTools = originalShowDeveloperTools
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func test_enableDebugLoggingFooter_saysAlwaysOnWhenTheBuildAlwaysLogsDebug() {
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: true)

        XCTAssertEqual(sut.enableDebugLoggingFooter, l("diagnostics.enable_debug_logs.always_on"))
    }

    func test_enableDebugLoggingFooter_asksForARestartOtherwise() {
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: false)

        XCTAssertEqual(sut.enableDebugLoggingFooter, l("diagnostics.enable_debug_logs.details"))
    }

    func test_enableDebugLogging_isOnAndDisabledWhenTheBuildAlwaysLogsDebug() {
        DiagnosticsPreferences.shared.enableDebugLogging = false

        let sut = makeSUT(isDebugLoggingAlwaysEnabled: true)

        XCTAssertTrue(sut.enableDebugLogging)
        XCTAssertTrue(sut.isDebugLoggingAlwaysEnabled)
    }

    func test_enableDebugLogging_keepsTheSavedPreferenceWhenTheBuildAlwaysLogsDebug() {
        DiagnosticsPreferences.shared.enableDebugLogging = false
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: true)

        sut.enableDebugLogging = true

        XCTAssertFalse(DiagnosticsPreferences.shared.enableDebugLogging)
    }

    func test_enableDebugLogging_followsTheSavedPreferenceOtherwise() {
        DiagnosticsPreferences.shared.enableDebugLogging = true
        XCTAssertTrue(makeSUT(isDebugLoggingAlwaysEnabled: false).enableDebugLogging)

        DiagnosticsPreferences.shared.enableDebugLogging = false
        XCTAssertFalse(makeSUT(isDebugLoggingAlwaysEnabled: false).enableDebugLogging)
    }

    func test_enableDebugLogging_savesThePreferenceOtherwise() {
        DiagnosticsPreferences.shared.enableDebugLogging = false
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: false)

        sut.enableDebugLogging = true

        XCTAssertTrue(sut.enableDebugLogging)
        XCTAssertTrue(DiagnosticsPreferences.shared.enableDebugLogging)
    }

    func test_appVersion_showsTheVersionAndBuildLeftToRight() {
        bundle.info["CFBundleShortVersionString"] = "2.4.0"
        bundle.info["CFBundleVersion"] = "310"
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: false)

        XCTAssertEqual(sut.appVersion, "\u{2066}2.4.0 (310)\u{2069}")
    }

    func test_appVersion_showsTheVersionAloneWithoutABuild() {
        bundle.info["CFBundleShortVersionString"] = "2.4.0"
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: false)

        XCTAssertEqual(sut.appVersion, "\u{2066}2.4.0\u{2069}")
    }

    func test_appVersion_isEmptyWithoutAVersion() {
        bundle.info["CFBundleVersion"] = "310"
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: false)

        XCTAssertEqual(sut.appVersion, "")
    }

    func test_copyableAppVersion_isThePlainVersionAndBuildWithoutIsolates() {
        bundle.info["CFBundleShortVersionString"] = "2.4.0"
        bundle.info["CFBundleVersion"] = "310"
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: false)

        XCTAssertEqual(sut.copyableAppVersion, "2.4.0 (310)")
    }

    func test_developerTools_areOffByDefaultAndSaved() {
        DiagnosticsPreferences.shared.showDeveloperTools = false
        // Debug logging is on in every app build, so it must not reveal developer screens.
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: true)
        XCTAssertFalse(sut.showDeveloperTools)

        sut.showDeveloperTools = true

        XCTAssertTrue(DiagnosticsPreferences.shared.showDeveloperTools)
        XCTAssertTrue(makeSUT(isDebugLoggingAlwaysEnabled: true).showDeveloperTools)
    }

    func test_openRecitationLab_pushesTheDeveloperScreen() {
        let navigationController = UINavigationController(rootViewController: UIViewController())
        let sut = makeSUT(isDebugLoggingAlwaysEnabled: true, navigationController: navigationController)

        sut.openRecitationLab()

        XCTAssertEqual(navigationController.viewControllers.count, 2)
        XCTAssertEqual(navigationController.topViewController?.title, "Recitation Lab")
    }

    // MARK: Private

    private var directory: URL!
    private var originalEnableDebugLogging = false
    private var originalShowDeveloperTools = false
    private let bundle = SystemBundleFake()

    private func makeSUT(
        isDebugLoggingAlwaysEnabled: Bool,
        navigationController: UINavigationController? = nil
    ) -> DiagnosticsViewModel {
        DiagnosticsViewModel(
            diagnosticsService: DiagnosticsService(
                logsDirectory: directory.appendingPathComponent("logs", isDirectory: true),
                databasesDirectory: directory.appendingPathComponent("databases", isDirectory: true)
            ),
            isDebugLoggingAlwaysEnabled: isDebugLoggingAlwaysEnabled,
            bundle: bundle,
            navigationController: navigationController,
            recitationLabBuilder: RecitationLabBuilder(container: AppDependenciesFake())
        )
    }
}
