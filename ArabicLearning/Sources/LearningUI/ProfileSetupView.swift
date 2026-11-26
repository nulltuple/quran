//
//  ProfileSetupView.swift
//  ArabicLearning (Arabican app)
//

import LearningModel
import NoorUI
import SwiftUI

/// Create a local profile, or pick an existing one. No account; everything stays on this device.
struct ProfileSetupView: View {
    let existing: [LearnerProfile]
    let create: (String, PresentationProfile) -> Void
    let choose: (LearnerProfile) -> Void

    @State private var name = ""
    @State private var presentation: PresentationProfile = .adult

    var body: some View {
        Form {
            if !existing.isEmpty {
                Section(String(localized: "profile.existing", bundle: .module)) {
                    ForEach(existing) { profile in
                        Button(profile.name) { choose(profile) }
                    }
                }
            }
            Section {
                TextField(String(localized: "profile.name", bundle: .module), text: $name)
                    .textContentType(.givenName)
                Picker(String(localized: "profile.presentation", bundle: .module), selection: $presentation) {
                    Text("profile.presentation.adult", bundle: .module).tag(PresentationProfile.adult)
                    Text("profile.presentation.child", bundle: .module).tag(PresentationProfile.child)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("profile.new", bundle: .module)
            } footer: {
                Text("profile.footer", bundle: .module)
            }
            Section {
                Button(String(localized: "profile.create", bundle: .module)) {
                    create(name.trimmingCharacters(in: .whitespacesAndNewlines), presentation)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(String(localized: "profile.title", bundle: .module))
    }
}
