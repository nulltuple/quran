//
//  LearnView.swift
//  ArabicLearning (Arabican app)
//

import LearningModel
import NoorUI
import SwiftUI

struct LearnView: View {
    let viewModel: LearnViewModel

    var body: some View {
        content
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .failed:
            DataUnavailableView(
                title: String(localized: "learn.error.title", bundle: .module),
                text: String(localized: "learn.error.text", bundle: .module),
                image: .learn
            )
        case .loaded(let curriculum):
            NoorList {
                ForEach(curriculum.units) { unit in
                    NoorSection(title: unit.title, curriculum.lessons(in: unit)) { lesson in
                        NoorListItem(title: "\(lesson.title)")
                    }
                }
            }
        }
    }
}
