//
//  RecitationCheckBuilder.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import AppDependencies
import Localization
import MemorizationPersistence
import MemorizationService
import QuranKit
import RecitationRecognition
import SwiftUI
import UIKit

/// Recite and check (roadmap V3a + V3b): a sheet where the person recites a passage from memory,
/// sees or silently records confirmed mistakes as `.model` evidence, and can dispute any mistake.
@MainActor
public struct RecitationCheckBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    /// `selection`: the ayah menu's verses (`RecitationCheckViewModel.passage(for:)` turns them into
    /// the passage). The view model is returned so the presenter can stop the microphone when the
    /// sheet goes away.
    public func build(
        selection: [AyahNumber],
        onHistoryChanged: (() -> Void)? = nil
    ) -> (UIViewController, RecitationCheckViewModel) {
        let memorizationService = MemorizationService(
            persistence: CoreDataMemorizationPersistence(stack: container.coreDataStack)
        )
        let viewModel = RecitationCheckViewModel(
            loader: RecitationEngineLoader(
                downloadManager: container.downloadManager,
                quranUthmaniV2Database: container.quranUthmaniV2Database,
                wordByWordDatabase: container.wordByWordDatabase
            ),
            microphone: RecitationMicrophone(maximumSeconds: RecitationCheckViewModel.maximumSeconds),
            verses: RecitationCheckViewModel.passage(for: selection),
            memorizationService: memorizationService,
            onHistoryChanged: onHistoryChanged
        )
        let controller = UIHostingController(rootView: RecitationCheckView(viewModel: viewModel))
        controller.navigationItem.title = l("recitation_check.title")
        // The reader's sheet presentation adds the Close button to the navigation bar.
        return (UINavigationController(rootViewController: controller), viewModel)
    }

    // MARK: Private

    private let container: AppDependencies
}
