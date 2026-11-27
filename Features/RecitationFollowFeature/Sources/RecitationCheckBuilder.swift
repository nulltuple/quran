//
//  RecitationCheckBuilder.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import AppDependencies
import Localization
import QuranKit
import RecitationRecognition
import SwiftUI
import UIKit

/// Recite and check (roadmap V3a): a sheet where the person recites a passage from memory and
/// sees the words they left out or said differently.
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
    public func build(selection: [AyahNumber]) -> (UIViewController, RecitationCheckViewModel) {
        let viewModel = RecitationCheckViewModel(
            loader: RecitationEngineLoader(
                downloadManager: container.downloadManager,
                quranUthmaniV2Database: container.quranUthmaniV2Database,
                wordByWordDatabase: container.wordByWordDatabase
            ),
            microphone: RecitationMicrophone(maximumSeconds: RecitationCheckViewModel.maximumSeconds),
            verses: RecitationCheckViewModel.passage(for: selection)
        )
        let controller = UIHostingController(rootView: RecitationCheckView(viewModel: viewModel))
        controller.navigationItem.title = l("recitation_check.title")
        // The reader's sheet presentation adds the Close button to the navigation bar.
        return (UINavigationController(rootViewController: controller), viewModel)
    }

    // MARK: Private

    private let container: AppDependencies
}
