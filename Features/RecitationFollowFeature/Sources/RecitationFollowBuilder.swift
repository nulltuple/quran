//
//  RecitationFollowBuilder.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import AppDependencies
import QuranKit
import RecitationRecognition
import SwiftUI
import UIKit

/// Live recitation follow (roadmap V2a): the controls the reader shows while it follows the
/// person's recitation, and their view model.
@MainActor
public struct RecitationFollowBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    /// `pages`: the pages in view. `highlight` shows the recited word in the reader (nil clears
    /// it); `close` removes the controls.
    public func build(
        pages: [Page],
        highlight: @escaping (Word?) -> Void,
        close: @escaping () -> Void
    ) -> (UIViewController, RecitationFollowViewModel) {
        let viewModel = RecitationFollowViewModel(
            loader: RecitationEngineLoader(
                downloadManager: container.downloadManager,
                quranUthmaniV2Database: container.quranUthmaniV2Database,
                wordByWordDatabase: container.wordByWordDatabase
            ),
            // A little more than a window, so the window is always full once recording has run that long.
            microphone: RecitationMicrophone(keepingLatestSeconds: RecitationFollowViewModel.windowSeconds + 2),
            pages: pages,
            highlight: highlight,
            close: close
        )
        let viewController = UIHostingController(rootView: RecitationFollowView(viewModel: viewModel))
        viewController.view.backgroundColor = .clear
        viewController.sizingOptions = .intrinsicContentSize
        return (viewController, viewModel)
    }

    // MARK: Private

    private let container: AppDependencies
}
