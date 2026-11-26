//
//  LearnerProgressView.swift
//  ArabicLearning (Arabican app)
//

import Foundation
import LearningModel
import Localization
import NoorUI
import SwiftUI

struct LearnerProgressView: View {
    let viewModel: ProgressViewModel
    let profileName: String
    @Binding var meaningLanguage: MeaningLanguage
    let switchProfile: @MainActor @Sendable () -> Void

    var body: some View {
        NoorList {
            NoorSection(title: profileName, viewModel.units) { unit in
                NoorListItem(
                    title: "\(unit.unit.title)",
                    subtitle: .init(text: "\(detail(unit))", location: .bottom)
                )
            }
            NoorBasicSection(footer: String(localized: "progress.meaningLanguage.footer", bundle: .module)) {
                Picker(selection: $meaningLanguage) {
                    ForEach(MeaningLanguage.allCases, id: \.self) { language in
                        Text(language.name).tag(language)
                    }
                } label: {
                    Label { Text("progress.meaningLanguage", bundle: .module) } icon: { NoorSystemImage.translation.image }
                }
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

extension MeaningLanguage {
    /// The language's own name (its endonym, from Foundation), so a reader of either finds it.
    var name: String {
        let code = switch self {
        case .english: "en"
        case .bengali: "bn"
        }
        return Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
    }
}
