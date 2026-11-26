//
//  ArabicanRootView.swift
//  ArabicLearning (Arabican app)
//

import LearningContent
import SwiftUI

/// The Arabican app's root: one tab per `AppTab`.
public struct ArabicanRootView: View {
    // MARK: Lifecycle

    public init(content: LearningContentStore) {
        learn = LearnViewModel(content: content)
    }

    // MARK: Public

    public var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    screen(for: tab)
                        .navigationTitle(tab.title)
                }
                .tabItem {
                    Label { Text(tab.title) } icon: { tab.systemImage.image }
                }
                .tag(tab)
            }
        }
    }

    // MARK: Private

    @State private var selection: AppTab = .learn
    @State private var learn: LearnViewModel

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .learn: LearnView(viewModel: learn)
        case .practice, .quran, .progress: TabPlaceholderView(tab: tab)
        }
    }
}

/// Shown until the tab's milestone lands (Documentation/ArabicLearning/03-spec-roadmap-risks.md §5).
private struct TabPlaceholderView: View {
    let tab: AppTab

    var body: some View {
        ContentUnavailableView {
            Label { Text(tab.title) } icon: { tab.systemImage.image }
        } description: {
            Text("tab.placeholder", bundle: .module)
        }
    }
}

#Preview {
    ArabicanRootView(content: LearningContentStore())
}
