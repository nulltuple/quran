//
//  ReadableWord.swift
//  ArabicLearning (Arabican app)
//

/// What a reader must know to sound out one grapheme of a Quran word.
public enum ReadingFeature: String, CaseIterable, Sendable {
    /// A letter with fatha, kasra or damma.
    case shortVowel
    /// A letter that lengthens the vowel before it (alif after fatha, waw after damma, ya after
    /// kasra, optionally with maddah), a dagger alif, or alif maqsura with a dagger alif.
    case longVowel
    case sukun
    case shadda
    case tanwin
    /// The alif (or alif maqsura) written after fathatan, which is not read when the reader goes on.
    case tanwinAlif
    /// Alif wasla (ٱ): read only when starting from it.
    case hamzatWasl
    /// The lam of ٱل before a "sun" letter (which then carries shadda): written, never read.
    case sunLam
    /// An alif, waw or ya under the small rounded zero (U+0652 in this text): written, never read.
    case silentLetter
    /// Hamza on a seat: أ إ ؤ ئ آ.
    case hamzaSeat
    /// ة, read as t.
    case taMarbuta
}

/// A Quran word split into graphemes, each with the reading features it needs. Only words the
/// literacy units (U4–U6) teach every part of are readable; anything else (pause signs, the iqlab
/// meem, small waw and ya, tatweel, hamza written as a mark) makes `init` return nil.
public struct ReadableWord: Hashable, Sendable {
    // MARK: Lifecycle

    public init?(_ text: String) {
        guard let graphemes = ArabicScript.graphemes(of: text), !graphemes.isEmpty else {
            return nil
        }
        var features: [Set<ReadingFeature>] = []
        for index in graphemes.indices {
            let previous = index > 0 ? graphemes[index - 1] : nil
            let next = index + 1 < graphemes.count ? graphemes[index + 1] : nil
            guard let found = Self.features(of: graphemes[index], previous: previous, next: next) else {
                return nil
            }
            features.append(found)
        }
        self.graphemes = graphemes
        self.features = features
    }

    // MARK: Public

    public let graphemes: [ArabicGrapheme]
    /// The features of each grapheme, parallel to `graphemes`.
    public let features: [Set<ReadingFeature>]

    /// Every feature the word needs.
    public var allFeatures: Set<ReadingFeature> {
        features.reduce(into: []) { $0.formUnion($1) }
    }

    /// Whether the grapheme at `index` is written but not read when the word is read on its own:
    /// a sun lam, a letter under the rounded zero, or alif wasla after a prefix (`وَٱ`).
    public func isSilent(at index: Int) -> Bool {
        let found = features[index]
        return found.contains(.sunLam) || found.contains(.silentLetter) || (index > 0 && found.contains(.hamzatWasl))
    }

    /// The first syllable when the word starts with a plain letter carrying one short vowel and
    /// nothing else, such as `خَ` in `خَلَقَ`.
    public var onset: (letter: ArabicLetter, vowel: ArabicMark)? {
        guard let first = graphemes.first, case .letter(let letter) = first.base, first.marks.count == 1,
              first.marks[0].kind == .shortVowel
        else {
            return nil
        }
        return (letter, first.marks[0])
    }

    // MARK: Private

    private static let tanwinFath: Set<ArabicMark> = [.fathatan, .invertedDamma]

    private static func features(
        of grapheme: ArabicGrapheme,
        previous: ArabicGrapheme?,
        next: ArabicGrapheme?
    ) -> Set<ReadingFeature>? {
        let marks = grapheme.marks
        switch grapheme.base {
        case .letter(let letter):
            if marks == [.sukun], [.alif, .waw, .ya].contains(letter) {
                return [.silentLetter]
            }
            if marks.isEmpty || marks == [.maddah] {
                if let previous, let long = lengthening(letter, after: previous, marks: marks) {
                    return long
                }
                if letter == .lam, marks.isEmpty, previous?.base == .variant("ٱ", of: .alif), next?.has(.shadda) == true {
                    return [.sunLam]
                }
                return nil
            }
            return vowelFeatures(marks)
        case .variant(let scalar, of: _):
            switch scalar {
            case "ٱ":
                return marks.isEmpty ? [.hamzatWasl] : nil
            case "آ":
                return marks.isEmpty ? [.hamzaSeat, .longVowel] : nil
            case "أ", "إ", "ؤ", "ئ":
                return vowelFeatures(marks).map { $0.union([.hamzaSeat]) }
            case "ة":
                return vowelFeatures(marks).map { $0.union([.taMarbuta]) }
            case "ى":
                if marks == [.daggerAlif] || marks == [.daggerAlif, .maddah] {
                    return [.longVowel]
                }
                if marks.isEmpty, let previous, !tanwinFath.isDisjoint(with: previous.marks) {
                    return [.tanwinAlif]
                }
                return nil
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// A bare (or maddah-carrying) alif, waw or ya after its matching vowel, or an alif after fathatan.
    private static func lengthening(_ letter: ArabicLetter, after previous: ArabicGrapheme, marks: [ArabicMark]) -> Set<ReadingFeature>? {
        let before = Set(previous.marks)
        switch letter {
        case .alif where before.contains(.fatha): return [.longVowel]
        case .alif where marks.isEmpty && !tanwinFath.isDisjoint(with: before): return [.tanwinAlif]
        case .waw where before.contains(.damma): return [.longVowel]
        case .ya where before.contains(.kasra): return [.longVowel]
        default: return nil
        }
    }

    /// A letter's vowel marks: one short vowel, sukun or tanwin, optionally with shadda; a short
    /// vowel may also carry a dagger alif (and maddah), which lengthens it.
    private static func vowelFeatures(_ marks: [ArabicMark]) -> Set<ReadingFeature>? {
        var rest = marks
        var result: Set<ReadingFeature> = []
        if let shadda = rest.firstIndex(of: .shadda) {
            rest.remove(at: shadda)
            result.insert(.shadda)
        }
        guard let first = rest.first else {
            return nil
        }
        switch first.kind {
        case .shortVowel:
            result.insert(.shortVowel)
            let after = Array(rest.dropFirst())
            if after.isEmpty {
                return result
            }
            if after == [.daggerAlif] || after == [.daggerAlif, .maddah] {
                return result.union([.longVowel])
            }
            return nil
        case .sukun where rest.count == 1 && !result.contains(.shadda):
            return [.sukun]
        case .tanwin where rest.count == 1:
            return result.union([.tanwin])
        default:
            return nil
        }
    }
}
