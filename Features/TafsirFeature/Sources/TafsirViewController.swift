//
//  TafsirViewController.swift
//

import Combine
import Localization
import NoorUI
import SwiftUI
import TranslationsFeature
import UIKit
import VLogging

final class TafsirViewController: UIHostingController<TafsirView> {
    // MARK: Lifecycle

    init(viewModel: TafsirViewModel, translationsListBuilder: TranslationsListBuilder) {
        self.viewModel = viewModel
        self.translationsListBuilder = translationsListBuilder
        var downloadTafsir: () -> Void = {}
        super.init(rootView: TafsirView(viewModel: viewModel, downloadTafsir: { downloadTafsir() }))
        downloadTafsir = { [weak self] in self?.presentTranslationsList() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = l("tafsir.title")
        configureNavigationBar()

        viewModel.$content
            .combineLatest(viewModel.$verse)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateArrows() }
            .store(in: &cancellables)

        Task { await viewModel.reloadTafsirs() }
    }

    // MARK: Private

    private let viewModel: TafsirViewModel
    private let translationsListBuilder: TranslationsListBuilder
    private var cancellables: Set<AnyCancellable> = []

    private var nextButton: UIBarButtonItem?
    private var previousButton: UIBarButtonItem?

    private func configureNavigationBar() {
        let next = NavigationBarButton.secondary(
            image: .nextVerse,
            accessibilityLabel: l("translation.verse.next")
        ) { [weak self] in
            guard let self else { return }
            Task { await self.viewModel.next() }
        }
        let previous = NavigationBarButton.secondary(
            image: .previousVerse,
            accessibilityLabel: l("translation.verse.previous")
        ) { [weak self] in
            guard let self else { return }
            Task { await self.viewModel.previous() }
        }
        // The same order as the translation sheet's arrows.
        let arrows: [UIBarButtonItem] = switch view.effectiveUserInterfaceLayoutDirection {
        case .rightToLeft: [previous, next]
        default: [next, previous]
        }
        navigationItem.trailingItemGroups = [UIBarButtonItemGroup(barButtonItems: arrows, representativeItem: nil)]
        nextButton = next
        previousButton = previous
    }

    private func updateArrows() {
        nextButton?.isEnabled = viewModel.nextVerse != nil
        previousButton?.isEnabled = viewModel.previousVerse != nil
    }

    private func presentTranslationsList() {
        logger.info("Tafsir: open translations list to download a tafsir")
        let controller = translationsListBuilder.build()
        let navigationController = UINavigationController(rootViewController: controller)
        controller.navigationItem.leftBarButtonItem = NavigationBarButton.close { [weak self] in
            self?.dismiss(animated: true) {
                guard let self else { return }
                Task { await self.viewModel.reloadTafsirs() }
            }
        }
        present(navigationController, animated: true)
    }
}
