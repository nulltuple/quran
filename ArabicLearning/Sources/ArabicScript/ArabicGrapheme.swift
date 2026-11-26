//
//  ArabicGrapheme.swift
//  ArabicLearning (Arabican app)
//

/// One written unit of Quran text: a base character and the marks drawn on it, such as `بِ` or
/// `لَّ`. Joining the graphemes of a text gives back the text, byte for byte.
public struct ArabicGrapheme: Hashable, Sendable {
    public enum Base: Hashable, Sendable {
        /// One of the 28 letters or the standalone hamza.
        case letter(ArabicLetter)
        /// A spelling variant of a letter: alif wasla (ٱ), hamza carriers (أ إ آ ؤ ئ), ta
        /// marbuta (ة), alif maqsura (ى), and the small waw (ۥ) and ya (ۦ).
        case variant(Unicode.Scalar, of: ArabicLetter)
        /// The tatweel (ـ), a joining stroke that can carry marks.
        case tatweel
        /// ۞ and ۩.
        case symbol(Unicode.Scalar)
        case space
        /// Anything else; text the curriculum does not handle yet.
        case unknown(Unicode.Scalar)
    }

    // MARK: Public

    public let base: Base
    public let marks: [ArabicMark]
    /// The exact source text of this grapheme.
    public let text: String

    /// Whether any mark on this grapheme is of `kind`. Marks keep their source order (the
    /// canonical text writes `رَّ` as ra, fatha, shadda), so compare kinds, not positions.
    public func has(_ kind: ArabicMark.Kind) -> Bool {
        marks.contains { $0.kind == kind }
    }

    /// The letter a learner names when reading this grapheme, if any.
    public var letter: ArabicLetter? {
        switch base {
        case .letter(let letter), .variant(_, of: let letter): letter
        default: nil
        }
    }
}

public enum ArabicScript {
    /// Splits `text` into graphemes. Every scalar lands in exactly one grapheme, so
    /// `graphemes(of: text).map(\.text).joined() == text`. Returns nil if a combining mark
    /// outside `ArabicMark` appears, or a mark has no base to sit on.
    public static func graphemes(of text: String) -> [ArabicGrapheme]? {
        var result: [ArabicGrapheme] = []
        var base: ArabicGrapheme.Base?
        var marks: [ArabicMark] = []
        var current = String.UnicodeScalarView()

        func flush() {
            if let base {
                result.append(ArabicGrapheme(base: base, marks: marks, text: String(current)))
            }
            base = nil
            marks = []
            current = String.UnicodeScalarView()
        }

        for scalar in text.unicodeScalars {
            if let mark = ArabicMark(scalar: scalar) {
                guard base != nil else {
                    return nil
                }
                marks.append(mark)
                current.append(scalar)
                continue
            }
            if scalar.properties.generalCategory == .nonspacingMark {
                return nil
            }
            flush()
            base = classify(scalar)
            current.append(scalar)
        }
        flush()
        return result
    }

    /// The base of a non-mark scalar.
    static func classify(_ scalar: Unicode.Scalar) -> ArabicGrapheme.Base {
        if let letter = ArabicLetter(scalar: scalar) {
            return .letter(letter)
        }
        if let letter = variants[scalar.value] {
            return .variant(scalar, of: letter)
        }
        switch scalar.value {
        case 0x0640: return .tatweel
        case 0x06DE, 0x06E9: return .symbol(scalar)
        case 0x0020: return .space
        default: return .unknown(scalar)
        }
    }

    // MARK: Private

    private static let variants: [UInt32: ArabicLetter] = [
        0x0622: .alif, // آ
        0x0623: .alif, // أ
        0x0625: .alif, // إ
        0x0671: .alif, // ٱ alif wasla
        0x0624: .waw, // ؤ
        0x0626: .ya, // ئ
        0x0629: .ta, // ة ta marbuta
        0x0649: .ya, // ى alif maqsura
        0x06E5: .waw, // ۥ small waw
        0x06E6: .ya, // ۦ small ya
    ]
}
