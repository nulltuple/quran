//
//  Tajweed.swift
//  ArabicLearning (Arabican app)
//

import QuranKit

/// A tajweed rule taught in the tajweed unit (U9, milestone L6), such as `noonIkhfa`.
public struct TajweedRule: Hashable, Sendable {
    public init(id: String, group: String, name: String, explanation: String) {
        self.id = id
        self.group = group
        self.name = name
        self.explanation = explanation
    }

    /// The subject of the rule's skills, `tajweed.spot.<id>` and `tajweed.listen.<id>`.
    public let id: String
    /// Rules of one group (`madd`, `noon`, `meem`, `letters`) are the confusions that matter, so
    /// they are offered as distractors first.
    public let group: String
    public let name: String
    /// English only: the exercise shows the Arabic in the Quran font.
    public let explanation: String
}

/// One place in a bridge sura where a rule applies, found by Tools/learning/tajweed.py.
public struct TajweedExample: Hashable, Sendable {
    /// How the two sources agreed (spec 03 §5.2 L6).
    public enum Agreement: String, Sendable {
        /// The phonetizer and Quran.com's markup both mark it.
        case both
        /// Quran.com never marks this rule (izhar, the alif after tanwin at a stop, and natural
        /// madd on a full letter); the phonetizer does.
        case phonetizer
        /// The sources disagree; the review in `tajweed_review.toml` says teach.
        case reviewed
    }

    public init(rule: TajweedRule, ayah: [QuranWordText], highlights: [Word: ClosedRange<Int>], recitation: RecitationSegment, agreement: Agreement) {
        self.rule = rule
        self.ayah = ayah
        self.highlights = highlights
        self.recitation = recitation
        self.agreement = agreement
    }

    public let rule: TajweedRule
    /// Every word of the ayah, in order.
    public let ayah: [QuranWordText]
    /// The graphemes (as `ArabicScript.graphemes` splits) the rule colors, per word.
    public let highlights: [Word: ClosedRange<Int>]
    /// The rule's words, recited.
    public let recitation: RecitationSegment
    public let agreement: Agreement

    /// The words the rule touches, in order.
    public var words: [QuranWordText] {
        ayah.filter { highlights[$0.word] != nil }
    }

    /// Whether `other` (in the same ayah) colors a grapheme this example colors.
    public func overlaps(_ other: TajweedExample) -> Bool {
        highlights.contains { word, range in other.highlights[word]?.overlaps(range) == true }
    }

    /// Whether `other` (in the same ayah) touches a word this example's recitation plays.
    public func sharesWords(with other: TajweedExample) -> Bool {
        !Set(highlights.keys).isDisjoint(with: other.highlights.keys)
    }
}
