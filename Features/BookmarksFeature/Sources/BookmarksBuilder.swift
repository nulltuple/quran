//
//  BookmarksBuilder.swift
//  Quran
//
//  Created by Afifi, Mohamed on 3/31/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import AnnotationsService
import AppDependencies
import FeaturesSupport
import Localization
import QuranKit
import UIKit

@MainActor
public struct BookmarksBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build(
        withListener listener: QuranNavigator,
        navigationController: UINavigationController
    ) -> UIViewController {
        BookmarkCollectionsBuilder(container: container).build(
            withListener: listener,
            navigationController: navigationController
        )
    }

    // MARK: Internal

    let container: AppDependencies
}
