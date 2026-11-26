//
//  AppTab.swift
//  ArabicLearning (Arabican app)
//

import NoorUI
import SwiftUI

/// The Arabican app's top-level tabs, in display order.
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case learn
    case practice
    case quran
    case progress

    // MARK: Public

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .learn: String(localized: "tab.learn", bundle: .module)
        case .practice: String(localized: "tab.practice", bundle: .module)
        case .quran: String(localized: "tab.quran", bundle: .module)
        case .progress: String(localized: "tab.progress", bundle: .module)
        }
    }

    public var systemImage: NoorSystemImage {
        switch self {
        case .learn: .learn
        case .practice: .practice
        case .quran: .study
        case .progress: .learningProgress
        }
    }
}
