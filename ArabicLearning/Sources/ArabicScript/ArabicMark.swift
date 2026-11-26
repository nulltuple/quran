//
//  ArabicMark.swift
//  ArabicLearning (Arabican app)
//

/// The combining marks found in the bundled Uthmani (KFGQPC Hafs) text, grouped by what a
/// learner must know to read them. The set is exactly the marks the canonical text uses
/// (inventory of `quran.ar.uthmani.v2.db`, 2026-11-25); `ArabicMark(scalar:)` returns nil for
/// anything else so new text cannot slip through unclassified.
public enum ArabicMark: UInt32, CaseIterable, Sendable, Codable {
    case fathatan = 0x064B
    case dammatan = 0x064C
    case kasratan = 0x064D
    case fatha = 0x064E
    case damma = 0x064F
    case kasra = 0x0650
    case shadda = 0x0651
    /// Not a sukun in the canonical text: the KFGQPC Hafs encoding draws U+0652 as the small rounded
    /// zero over an alif, waw or ya that is written but never read (103:3 `ءَامَنُواْ`); it appears on
    /// no other letter. The sukun is `quranicSukun`.
    case sukun = 0x0652
    case maddah = 0x0653
    case hamzaAbove = 0x0654
    case hamzaBelow = 0x0655
    /// Drawn as the staggered (open) kasratan by the KFGQPC Hafs font the canonical text targets.
    case subscriptAlif = 0x0656
    /// Drawn as the staggered (open) fathatan by the KFGQPC Hafs font.
    case invertedDamma = 0x0657
    case dotBelow = 0x065C
    /// Drawn as the staggered (open) dammatan by the KFGQPC Hafs font.
    case fathaWithTwoDots = 0x065E
    case daggerAlif = 0x0670
    case smallHighLigatureSadLamAlif = 0x06D6
    case smallHighLigatureQafLamAlif = 0x06D7
    case smallHighMeemInitial = 0x06D8
    case smallHighJeem = 0x06DA
    case smallHighThreeDots = 0x06DB
    case smallHighSeen = 0x06DC
    case smallHighUprightRectangularZero = 0x06E0
    /// The Uthmani sukun (small high dotless head of khah).
    case quranicSukun = 0x06E1
    /// Iqlab: noon sakinah or tanwin read as meem.
    case smallHighMeemIsolated = 0x06E2
    case smallHighMadda = 0x06E4
    case smallHighYa = 0x06E7
    case smallHighNoon = 0x06E8
    case roundedHighStopFilledCentre = 0x06EC
    case smallLowMeem = 0x06ED

    // MARK: Lifecycle

    public init?(scalar: Unicode.Scalar) {
        self.init(rawValue: scalar.value)
    }

    // MARK: Public

    public enum Kind: String, Sendable, Codable {
        /// fatha, kasra, damma.
        case shortVowel
        case tanwin
        case sukun
        case shadda
        /// Marks that lengthen or carry a vowel: dagger alif, maddah, and the small letters.
        case longVowel
        case hamza
        /// Pause (waqf) signs written above the line.
        case pause
        /// Recitation signs: iqlab meem, the rounded zero over an unread letter, and similar.
        case recitation
    }

    public var scalar: Unicode.Scalar {
        Unicode.Scalar(rawValue)!
    }

    public var kind: Kind {
        switch self {
        case .fatha, .damma, .kasra: .shortVowel
        // The staggered tanwin (three code points the KFGQPC encoding reuses, for example 95:4 `تَقۡوِيمٖ`,
        // 94:6 `يُسۡرٗا`, 93:4 `خَيۡرٞ`) is still tanwin; the stagger tells a reciter the noon sound merges
        // into the next word.
        case .fathatan, .dammatan, .kasratan, .subscriptAlif, .invertedDamma, .fathaWithTwoDots: .tanwin
        case .quranicSukun: .sukun
        case .shadda: .shadda
        case .daggerAlif, .maddah, .smallHighMadda, .smallHighYa, .smallHighNoon: .longVowel
        case .hamzaAbove, .hamzaBelow: .hamza
        case .smallHighLigatureSadLamAlif, .smallHighLigatureQafLamAlif, .smallHighMeemInitial, .smallHighJeem,
             .smallHighThreeDots, .smallHighSeen:
            .pause
        case .sukun, .smallHighUprightRectangularZero, .smallHighMeemIsolated, .roundedHighStopFilledCentre, .smallLowMeem,
             .dotBelow:
            .recitation
        }
    }
}
