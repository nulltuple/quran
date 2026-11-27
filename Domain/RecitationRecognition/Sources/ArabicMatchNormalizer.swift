//
//  ArabicMatchNormalizer.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Foundation

/// Arabic text reduced for comparing a recognizer's transcript with the Quran's plain (imla'i)
/// text: no BOM, harakat, Quranic annotation marks or tatweel; alef forms, ta marbuta and alef
/// maqsura folded; no punctuation; single spaces. Matching only: displayed Quran text never goes
/// through it. Tools/recitation-model.py `normalize` applies the same rules to benchmarks.
public enum ArabicMatchNormalizer {
    // MARK: Public

    public static func normalize(_ text: String) -> String {
        var words: [String] = []
        var word = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !word.isEmpty {
                    words.append(String(word))
                    word = String.UnicodeScalarView()
                }
                continue
            }
            if let folded = fold(scalar) {
                word.append(folded)
            }
        }
        if !word.isEmpty {
            words.append(String(word))
        }
        return words.joined(separator: " ")
    }

    /// The normalized text without spaces, as UTF-16 code units (every kept letter is one unit).
    public static func letters(_ text: String) -> [UInt16] {
        Array(normalize(text).utf16.filter { $0 != space })
    }

    // MARK: Private

    private static let space = UInt16(UInt8(ascii: " "))

    /// The scalar to keep for `scalar`, or nil to drop it: only Arabic letters U+0621–U+064A remain.
    private static func fold(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        switch scalar.value {
        case 0x0623, 0x0625, 0x0622, 0x0671: // أ إ آ ٱ -> ا
            return "\u{0627}"
        case 0x0629: // ة -> ه
            return "\u{0647}"
        case 0x0649: // ى -> ي
            return "\u{064A}"
        case 0x0621 ... 0x063A, 0x0641 ... 0x064A: // letters (0x0640 is tatweel)
            return scalar
        default: // marks, tatweel, BOM, punctuation, digits, Latin
            return nil
        }
    }
}
