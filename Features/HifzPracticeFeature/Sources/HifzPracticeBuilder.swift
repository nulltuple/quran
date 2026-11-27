//
//  HifzPracticeBuilder.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import AppDependencies
import MemorizationPersistence
import MemorizationService
import QuranAnnotations
import QuranKit
import RecitationRecognition
import SwiftUI
import UIKit

/// Hifz practice (roadmap H2): the controls the reader shows while practicing, and their view model.
@MainActor
public struct HifzPracticeBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    /// `verses`: the ayah menu's selection; one ayah practices from it to the end of its page.
    /// `listen` plays an ayah repeated with a pause to repeat it after each; `stopListening` stops it.
    public func build(
        verses: [AyahNumber],
        mask: @escaping (PracticeMask?) -> Void,
        listen: @escaping (AyahNumber) -> Void,
        stopListening: @escaping () -> Void,
        close: @escaping () -> Void
    ) -> (UIViewController, HifzPracticeViewModel)? {
        guard let passage = Self.passage(for: verses) else {
            return nil
        }
        return build(passage: passage, mask: mask, listen: listen, stopListening: stopListening, close: close)
    }

    /// Practices an exact `passage` (for example from the H3 review queue), including single-ayah passages.
    public func build(
        passage: Passage,
        mask: @escaping (PracticeMask?) -> Void,
        listen: @escaping (AyahNumber) -> Void,
        stopListening: @escaping () -> Void,
        close: @escaping () -> Void
    ) -> (UIViewController, HifzPracticeViewModel) {
        let loader = RecitationEngineLoader(
            downloadManager: container.downloadManager,
            quranUthmaniV2Database: container.quranUthmaniV2Database,
            wordByWordDatabase: container.wordByWordDatabase
        )
        let viewModel = HifzPracticeViewModel(
            passage: passage,
            loader: loader,
            microphone: RecitationMicrophone(keepingLatestSeconds: HifzPracticeViewModel.liveWindowSeconds + 2),
            service: MemorizationService(persistence: CoreDataMemorizationPersistence(stack: container.coreDataStack)),
            store: PracticeStateStore(quran: passage.first.quran),
            mask: mask,
            listen: listen,
            stopListening: stopListening,
            close: close
        )
        let viewController = UIHostingController(rootView: HifzPracticeView(viewModel: viewModel))
        viewController.view.backgroundColor = .clear
        viewController.sizingOptions = .intrinsicContentSize
        return (viewController, viewModel)
    }

    // MARK: Internal

    static func passage(for verses: [AyahNumber]) -> Passage? {
        guard let first = verses.min(), let last = verses.max() else {
            return nil
        }
        if first == last {
            return Passage(first, first.page.lastVerse)
        }
        return Passage(first, last)
    }

    // MARK: Private

    private let container: AppDependencies
}
