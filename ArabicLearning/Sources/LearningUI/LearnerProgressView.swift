//
//  LearnerProgressView.swift
//  ArabicLearning (Arabican app)
//

import Localization
import NoorUI
import SwiftUI

struct LearnerProgressView: View {
    let viewModel: ProgressViewModel
    let profileName: String
    let switchProfile: @MainActor @Sendable () -> Void

    var body: some View {
        NoorList {
            NoorSection(title: profileName, viewModel.units) { unit in
                NoorListItem(
                    title: "\(unit.unit.title)",
                    subtitle: .init(text: "\(detail(unit))", location: .bottom)
                )
            }
            NoorBasicSection {
                NoorListItem(
                    image: .init(.profile),
                    title: "\(String(localized: "profile.switch", bundle: .module))",
                    action: .sync(switchProfile)
                )
            }
        }
        .task { await viewModel.load() }
    }

    private func detail(_ unit: ProgressViewModel.UnitProgress) -> String {
        String(
            format: String(localized: "progress.unit.detail", bundle: .module),
            NumberFormatter.shared.format(unit.mastered),
            NumberFormatter.shared.format(unit.total),
            NumberFormatter.shared.format(unit.practicing)
        )
    }
}
