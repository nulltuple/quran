//
//  WordPointerBuilder.swift
//  Quran
//
//  Created by Afifi, Mohamed on 4/13/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import AppDependencies
import WordTextService

@MainActor
public struct WordPointerBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build(withListener listener: WordPointerListener) -> WordPointerViewController {
        let viewModel = WordPointerViewModel(service: WordTextService(fileURL: container.wordByWordDatabase))
        let viewController = WordPointerViewController(viewModel: viewModel)
        viewModel.listener = listener
        return viewController
    }

    // MARK: Private

    private let container: AppDependencies
}
