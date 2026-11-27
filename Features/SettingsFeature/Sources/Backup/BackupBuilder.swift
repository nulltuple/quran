//
//  BackupBuilder.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import AppDependencies
import BackupPersistence
import BackupService
import Localization
import SwiftUI
import SystemDependencies
import UIKit

@MainActor
public struct BackupBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies) {
        self.container = container
    }

    // MARK: Public

    public func build(navigationController: UINavigationController?) -> UIViewController {
        let service = BackupService(
            persistence: CoreDataBackupPersistence(stack: container.coreDataStack),
            appVersion: DefaultSystemBundle().versionAndBuild ?? ""
        )
        let viewModel = BackupViewModel(service: service) { [weak navigationController] url, completion in
            guard let navigationController else {
                completion()
                return
            }
            navigationController.share([url], completion: completion)
        }
        let viewController = UIHostingController(rootView: BackupView(viewModel: viewModel))
        viewController.title = l("backup.title")
        return viewController
    }

    // MARK: Internal

    let container: AppDependencies
}
