//
//  SimilarVersesBuilder.swift
//

import AppDependencies
import Localization
import MemorizationPersistence
import MemorizationService
import QuranKit
import SwiftUI
import UIKit

@MainActor
public struct SimilarVersesBuilder {
    private let container: AppDependencies

    public init(container: AppDependencies) {
        self.container = container
    }

    public func build(
        origin: AyahNumber,
        jump: @escaping (AyahNumber) -> Void,
        play: @escaping (AyahNumber) -> Void,
        stop: @escaping () -> Void
    ) -> (controller: UIViewController, didDismiss: () -> Void) {
        let model = SimilarVersesViewModel(
            origin: origin,
            similarities: SimilarVerseService(uthmaniDatabase: container.quranUthmaniV2Database),
            memorization: MemorizationService(
                persistence: CoreDataMemorizationPersistence(stack: container.coreDataStack)
            ),
            jump: jump,
            play: play,
            stop: stop
        )
        let controller = UIHostingController(rootView: SimilarVersesView(model: model))
        controller.navigationItem.title = l("similar_verses.title")
        return (UINavigationController(rootViewController: controller), { model.close() })
    }
}
