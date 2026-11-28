//
//  RecitationLabBuilder.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import AppDependencies
import Foundation
import RecitationRecognition
import SwiftUI
import UIKit

/// The developer recitation screen (V0 deliverable 8, extended with V4 pronunciation assessment):
/// live microphone recognition with the on-device models, reached from Settings > Diagnostics while
/// developer tools are on.
@MainActor
public struct RecitationLabBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build() -> UIViewController {
        let viewModel = RecitationLabViewModel(
            loader: RecitationEngineLoader(
                downloadManager: container.downloadManager,
                quranUthmaniV2Database: container.quranUthmaniV2Database,
                wordByWordDatabase: container.wordByWordDatabase
            ),
            phoneticLoader: PhoneticEngineLoader(downloadManager: container.downloadManager),
            microphone: RecitationMicrophone()
        )
        let viewController = UIHostingController(rootView: RecitationLabView(viewModel: viewModel))
        viewController.title = "Recitation Lab"
        return viewController
    }

    // MARK: Private

    private let container: AppDependencies
}
