//
//  SearchViewController.swift
//
//
//  Created by Mohamed Afifi on 2023-07-20.
//

import Combine
import Foundation
import Localization
import NoorUI
import QuranKit
import SwiftUI
import VLogging

final class SearchViewController: UIViewController, UISearchBarDelegate {
    // MARK: Lifecycle

    init(viewModel: SearchViewModel, makeVoiceSearch: @escaping (@escaping (AyahNumber) -> Void) -> VoiceSearchViewModel) {
        self.viewModel = viewModel
        self.makeVoiceSearch = makeVoiceSearch
        searchResultsViewController = UIHostingController(rootView: SearchView(viewModel: viewModel))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    @MainActor
    dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .portrait
        } else {
            return super.supportedInterfaceOrientations
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = lAndroid("menu_search")

        addFullScreenChild(searchResultsViewController)

        search.install(in: navigationItem, hidesSearchBarWhenScrolling: false)
        navigationItem.rightBarButtonItems = [voiceSearchItem] + [search.barButtonItem].compactMap { $0 }
        definesPresentationContext = true

        viewModel.$searchTerm
            .receive(on: DispatchQueue.main)
            .sink { [weak self] searchTerm in
                self?.search.searchBar.text = searchTerm
            }
            .store(in: &cancellables)

        viewModel.$keyboardState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .closed:
                    self?.search.searchBar.endEditing(true)
                case .open:
                    self?.search.searchBar.becomeFirstResponder()
                }
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Deactivating the search controller when leaving clears the search bar text.
        search.searchBar.text = viewModel.searchTerm
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        search.deactivate()
    }

    // MARK: - Voice search

    private func presentVoiceSearch() {
        logger.info("[Search] voice search opened")
        search.deactivate()
        let voiceSearch = makeVoiceSearch { [weak self] verse in
            self?.dismiss(animated: true) {
                self?.viewModel.selectRecitedVerse(verse)
            }
        }
        let view = VoiceSearchView(
            viewModel: voiceSearch,
            quranFont: viewModel.reading.quranFont,
            dismiss: { [weak self] in self?.dismiss(animated: true) }
        )
        let sheet = UIHostingController(rootView: view)
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    // MARK: - Search delegate methods

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Debug only: search text must not reach Crashlytics, which receives info and above.
        logger.debug("[Search] textDidChange to \(searchText)")
        viewModel.autocomplete(searchText)
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        logger.info("[Search] searchBarTextDidBeginEditing")
        viewModel.keyboardState = .open
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        logger.info("[Search] searchBarTextDidEndEditing")
        viewModel.keyboardState = .closed
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        logger.info("[Search] searchBarSearchButtonClicked")
        // Debug only: search text must not reach Crashlytics, which receives info and above.
        logger.debug("[Search] searchBarSearchButtonClicked \(searchBar.text ?? "")")
        viewModel.searchForUserTypedTerm()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        logger.info("[Search] searchBarCancelButtonClicked")
        viewModel.reset()
    }

    // MARK: Private

    private lazy var voiceSearchItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: NoorSystemImage.voiceSearch.uiImage,
            primaryAction: UIAction { [weak self] _ in self?.presentVoiceSearch() }
        )
        item.accessibilityLabel = l("voice_search.title")
        return item
    }()

    private var cancellables: Set<AnyCancellable> = []
    private let viewModel: SearchViewModel
    private let makeVoiceSearch: (@escaping (AyahNumber) -> Void) -> VoiceSearchViewModel
    private lazy var search = NavigationSearch(
        placeholder: l("search.placeholder.text"),
        delegate: self,
        hidesNavigationBarDuringPresentation: true
    )
    private let searchResultsViewController: UIHostingController<SearchView>
}
