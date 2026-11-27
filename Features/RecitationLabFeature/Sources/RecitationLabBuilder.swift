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

/// The developer recitation screen (V0 deliverable 8): live microphone recognition with the
/// on-device model, reached from Settings > Diagnostics while debug logging is on.
@MainActor
public struct RecitationLabBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    /// Where the model is installed: `Application Support/RecitationModel`.
    public static var modelDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("RecitationModel", isDirectory: true)
    }

    public func build() -> UIViewController {
        let viewModel = RecitationLabViewModel(
            modelStore: RecitationModelStore(directory: Self.modelDirectory),
            verseText: RecitationVerseText(
                quranUthmaniV2Database: container.quranUthmaniV2Database,
                wordByWordDatabase: container.wordByWordDatabase
            ),
            microphone: RecitationMicrophone()
        )
        let viewController = UIHostingController(rootView: RecitationLabView(viewModel: viewModel))
        viewController.title = "Recitation Lab"
        return viewController
    }

    // MARK: Private

    private let container: AppDependencies
}
