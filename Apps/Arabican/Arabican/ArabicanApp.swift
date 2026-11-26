//
//  ArabicanApp.swift
//  Arabican (App Store Connect "Arabican", bundle com.nulltup.arabican)
//
//  This is the Arabic learning app, not the Quran (MemQuran) app in Example/.
//  Features live in the ArabicLearning package; this target only composes them.
//

import LearningContent
import LearningPersistence
import LearningUI
import SwiftUI

@main
struct ArabicanApp: App {
    init() {
        // The Quran font (KFGQPC Uthmanic Hafs) draws every Arabic letter, as in the Quran app.
        ArabicanRootView.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            if let profiles {
                ArabicanRootView(content: LearningContentStore(), profiles: profiles)
            } else {
                Text(verbatim: "Arabican could not open its storage.")
            }
        }
    }

    /// Learner data in Application Support. Failing to open it shows a message and never deletes anything.
    private let profiles: ProfileStore? = {
        guard let directory = try? ProfileStore.defaultDirectory() else { return nil }
        return try? ProfileStore(directory: directory)
    }()
}
