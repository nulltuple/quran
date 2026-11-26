//
//  ArabicanRootView.swift
//  ArabicLearning (Arabican app)
//

import SwiftUI

/// The Arabican app's root: one tab per `AppTab`.
public struct ArabicanRootView: View {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    TabPlaceholderView(tab: tab)
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
    ArabicanRootView()
}
