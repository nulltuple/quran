//
//  MistakeDetailBuilder.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import AppDependencies
import Localization
import MemorizationPersistence
import MemorizationService
import QuranKit
import SwiftUI
import UIKit

/// Builds the H7 Mistake Detail sheet for one ayah.
@MainActor
public struct MistakeDetailBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build(
        verse: AyahNumber,
        practicePassage: ((Passage) -> Void)? = nil,
        openNote: (() -> Void)? = nil,
        openInReader: ((AyahNumber) -> Void)? = nil,
        onHistoryChanged: (() -> Void)? = nil
    ) -> UIViewController {
        let viewModel = MistakeDetailViewModel(
            verse: verse,
            service: MemorizationService(
                persistence: CoreDataMemorizationPersistence(stack: container.coreDataStack)
            ),
            textLoader: SpotTestTextLoader(
                uthmaniDatabase: container.quranUthmaniV2Database,
                wordByWordDatabase: container.wordByWordDatabase
            ),
            practicePassage: practicePassage,
            openNote: openNote,
            openInReader: openInReader,
            onHistoryChanged: onHistoryChanged
        )
        let controller = UIHostingController(rootView: MistakeDetailView(viewModel: viewModel))
        controller.navigationItem.title = l("mistake_history.title")
        return UINavigationController(rootViewController: controller)
    }

    // MARK: Private

    private let container: AppDependencies
}
