//
//  AppIconCatalog+Example.swift
//  QuranEngineApp
//
//  Created by Mohamed Afifi on 2026-09-29.
//

import Localization
import NoorUI
import UIKit
import UIx

extension AppIconCatalog {
    /// The Quran icons: the black primary icon and a graphite alternate.
    static let example = AppIconCatalog(sections: [
        Section(
            id: "quran",
            title: l("app_icon.section.icons"),
            previewSize: .large,
            options: [.quran, .graphite]
        ),
    ])
}

extension AppIconOption {
    static let quran = AppIconOption(
        id: "quran",
        alternateIconName: nil,
        name: "Quran",
        previewImageName: "app-icon-quran",
        artworkImageName: "app-artwork-quran",
        accent: .amber
    )

    static let graphite = AppIconOption(
        id: "graphite",
        alternateIconName: "AppIcon-Graphite",
        name: l("app_icon.name.graphite"),
        previewImageName: "app-icon-graphite",
        artworkImageName: "app-artwork-graphite",
        accent: .amber
    )
}

private extension AppIconAccent {
    /// Keep in sync with the `AccentColor` colorset, the global accent.
    static let amber = AppIconAccent(
        light: UIColor(rgb: 0x874C00),
        dark: UIColor(rgb: 0xF5B454),
        onDark: UIColor(rgb: 0x3A2200)
    )
}
