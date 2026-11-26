//
//  ArabicanRootView.swift
//  ArabicLearning (Arabican app)
//

import LearningContent
import LearningPersistence
import NoorFont
import NoorUI
import SwiftUI

/// The Arabican app's root: profile setup until a profile is active, then one tab per `AppTab`.
public struct ArabicanRootView: View {
    // MARK: Lifecycle

    public init(content: LearningContentStore, profiles: ProfileStore) {
        _viewModel = State(initialValue: ArabicanRootViewModel(content: content, profiles: profiles))
    }

    // MARK: Public

    /// Registers QuranEngine's bundled fonts (NoorFont). Call once at launch.
    public static func registerFonts() {
        FontName.registerFonts()
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case .needsProfile:
                NavigationStack {
                    ProfileSetupView(existing: viewModel.allProfiles) { name, presentation in
                        Task { await viewModel.createProfile(name: name, presentation: presentation) }
                    } choose: { profile in
                        Task { await viewModel.switchTo(profile) }
                    }
                }
            case .ready(let session):
                tabs(session)
            case .failed:
                DataUnavailableView(
                    title: String(localized: "profile.error.title", bundle: .module),
                    text: String(localized: "profile.error.text", bundle: .module),
                    image: .profile
                )
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: Private

    @State private var selection: AppTab = .learn
    @State private var viewModel: ArabicanRootViewModel

    private func tabs(_ session: ArabicanRootViewModel.Session) -> some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    screen(for: tab, session: session)
                        .navigationTitle(tab.title)
                }
                .tabItem {
                    Label { Text(tab.title) } icon: { tab.systemImage.image }
                }
                .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab, session: ArabicanRootViewModel.Session) -> some View {
        switch tab {
        case .learn: LearnView(viewModel: viewModel.learn)
        case .practice: PracticeView(viewModel: session.practice).id(session.profile.id)
        case .quran: QuranBridgeView(viewModel: viewModel.bridge)
        case .progress:
            LearnerProgressView(viewModel: session.progress, profileName: session.profile.name) {
                viewModel.requestProfileChoice()
            }
            .id(session.profile.id)
        }
    }
}
