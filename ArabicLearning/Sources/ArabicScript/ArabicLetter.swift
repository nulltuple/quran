//
//  ArabicLetter.swift
//  ArabicLearning (Arabican app)
//

/// The 28 letters of the Arabic alphabet in traditional (abjadi-hijāʾī) teaching order, plus the
/// standalone hamza. A letter's identity is its Unicode scalar; names, transliterations and
/// teaching groups live in the compiled learning content (`Tools/learning/content/letters.toml`),
/// whose tests check that the two agree.
public enum ArabicLetter: String, CaseIterable, Sendable, Codable {
    case alif = "ا"
    case ba = "ب"
    case ta = "ت"
    case tha = "ث"
    case jim = "ج"
    case haLight = "ح"
    case kha = "خ"
    case dal = "د"
    case dhal = "ذ"
    case ra = "ر"
    case zay = "ز"
    case sin = "س"
    case shin = "ش"
    case sad = "ص"
    case dad = "ض"
    case taHeavy = "ط"
    case zaHeavy = "ظ"
    case ayn = "ع"
    case ghayn = "غ"
    case fa = "ف"
    case qaf = "ق"
    case kaf = "ك"
    case lam = "ل"
    case mim = "م"
    case nun = "ن"
    case ha = "ه"
    case waw = "و"
    case ya = "ي"
    case hamza = "ء"

    // MARK: Lifecycle

    public init?(scalar: Unicode.Scalar) {
        self.init(rawValue: String(scalar))
    }

    // MARK: Public

    public var scalar: Unicode.Scalar {
        rawValue.unicodeScalars.first!
    }

    /// Whether the letter connects to the letter after it. Six letters (ا د ذ ر ز و) and the
    /// standalone hamza never do, so they have no initial or medial form of their own.
    public var joinsToNext: Bool {
        switch self {
        case .alif, .dal, .dhal, .ra, .zay, .waw, .hamza: false
        default: true
        }
    }

    /// Whether the letter connects to the letter before it. Only the standalone hamza does not.
    public var joinsToPrevious: Bool {
        self != .hamza
    }

    /// The positional forms the letter has.
    public var forms: [LetterForm] {
        switch (joinsToPrevious, joinsToNext) {
        case (true, true): [.isolated, .initial, .medial, .final]
        case (true, false): [.isolated, .final]
        case (false, _): [.isolated]
        }
    }

    /// The letter drawn in `form`, using zero-width joiners so the system shaper picks the
    /// positional glyph. Nil when the letter has no such form.
    public func text(in form: LetterForm) -> String? {
        guard forms.contains(form) else {
            return nil
        }
        let zwj = "\u{200D}"
        switch form {
        case .isolated: return rawValue
        case .initial: return rawValue + zwj
        case .medial: return zwj + rawValue + zwj
        case .final: return zwj + rawValue
        }
    }
}

/// A letter's position in a word.
public enum LetterForm: String, CaseIterable, Sendable, Codable {
    case isolated
    case initial
    case medial
    case final
}
