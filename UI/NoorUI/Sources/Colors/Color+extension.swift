//
//  Color+extension.swift
//
//
//  Created by Afifi, Mohamed on 7/23/21.
//

import SwiftUI
import UIx

extension Color {
    /// Text and glyphs drawn on a filled `accentColor` background.
    @MainActor public static var onAccent: Color {
        Color(UIColor.onAccent)
    }

    /// Amber for icons and text that need attention without being an error, such as items that don't sync.
    public static var caution: Color {
        Color(UIColor(light: UIColor(rgb: 0xA04B00), dark: UIColor(rgb: 0xFFB35C)))
    }

    /// The background of a card that holds ``caution`` content.
    public static var cautionBackground: Color {
        Color(UIColor(light: UIColor(rgb: 0xFFF4E5), dark: UIColor(rgb: 0x2E2210)))
    }

    /// Separates the rows of a ``cautionBackground`` card.
    public static var cautionSeparator: Color {
        Color(UIColor(light: UIColor(rgb: 0xF3DDBF), dark: UIColor(rgb: 0x4A3A20)))
    }

    /// Highlights the recited verse and word. It stays the same whatever the app icon.
    static var recitation: Color {
        Color(UIColor.recitation)
    }

    // MARK: Live practice palette (matched to Tarteel recording)

    /// Active recited word glyph color (`#1AC962` light, `#27D970` dark).
    public static let practiceActiveWord = Color(UIColor(light: UIColor(rgb: 0x1AC962), dark: UIColor(rgb: 0x27D970)))

    /// Mistake word glyph, dotted underline, and badge color (`#ED4C4D` light, `#FF6364` dark).
    public static let practiceMistakeWord = Color(UIColor(light: UIColor(rgb: 0xED4C4D), dark: UIColor(rgb: 0xFF6364)))

    /// Soft coral wash behind revealed mistake words.
    public static let practiceMistakeGlow = Color(UIColor(
        light: UIColor(rgb: 0xED4C4D).withAlphaComponent(0.13),
        dark: UIColor(rgb: 0xFF6364).withAlphaComponent(0.22)
    ))

    /// Subtle horizontal baseline rule drawn under hidden words during Practice (`#DCDBDC` light).
    public static let practiceHiddenBaseline = Color(UIColor(
        light: UIColor(rgb: 0xDCDBDC),
        dark: UIColor.white.withAlphaComponent(0.18)
    ))

    /// Circular live-practice microphone button gradient colors (`#63DE84` → `#55DE98`).
    public static let practiceMicStart = Color(UIColor(rgb: 0x63DE84))

    public static let practiceMicEnd = Color(UIColor(rgb: 0x55DE98))
}

public extension UIColor {
    /// Text and glyphs drawn on a filled accent background.
    @MainActor static var onAccent: UIColor {
        AppIconAccent.current.onColor
    }
}

extension UIColor {
    static var recitation: UIColor {
        UIColor(light: UIColor(rgb: 0xDC7702), dark: UIColor(rgb: 0xEF911D))
    }

    static var themeCalmText: UIColor {
        UIColor(named: "theme-calm-text", in: .module, compatibleWith: nil)!
    }

    static var themeCalmBackground: UIColor {
        UIColor(named: "theme-calm-bg", in: .module, compatibleWith: nil)!
    }

    static var themeFocusText: UIColor {
        UIColor(named: "theme-focus-text", in: .module, compatibleWith: nil)!
    }

    static var themeFocusBackground: UIColor {
        UIColor(named: "theme-focus-bg", in: .module, compatibleWith: nil)!
    }

    static var themeOriginalText: UIColor {
        UIColor(named: "theme-original-text", in: .module, compatibleWith: nil)!
    }

    static var themeOriginalBackground: UIColor {
        UIColor(named: "theme-original-bg", in: .module, compatibleWith: nil)!
    }

    static var themePaperText: UIColor {
        UIColor(named: "theme-paper-text", in: .module, compatibleWith: nil)!
    }

    static var themePaperBackground: UIColor {
        UIColor(named: "theme-paper-bg", in: .module, compatibleWith: nil)!
    }

    static var themeQuietText: UIColor {
        UIColor(named: "theme-quiet-text", in: .module, compatibleWith: nil)!
    }

    static var themeQuietBackground: UIColor {
        UIColor(named: "theme-quiet-bg", in: .module, compatibleWith: nil)!
    }
}
