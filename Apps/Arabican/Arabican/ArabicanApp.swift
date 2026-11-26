//
//  ArabicanApp.swift
//  Arabican (App Store Connect "Arabican", bundle com.nulltup.arabican)
//
//  This is the Arabic learning app, not the Quran (MemQuran) app in Example/.
//  Features live in the ArabicLearning package; this target only composes them.
//

import LearningContent
import LearningUI
import SwiftUI

@main
struct ArabicanApp: App {
    var body: some Scene {
        WindowGroup {
            ArabicanRootView(content: LearningContentStore())
        }
    }
}
