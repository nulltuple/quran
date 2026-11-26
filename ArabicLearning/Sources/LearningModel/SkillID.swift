//
//  SkillID.swift
//  ArabicLearning (Arabican app)
//

/// The unit of learning evidence, such as `letter.recognize.ب` or `lemma.meaning.رَبّ`.
///
/// A skill id is dot-separated: a family (`letter`, `sound`, `syllable`, `word`, `lemma`,
/// `tajweed`), an ability, and one or more subjects. See ADR-0001 §4.4.
public struct SkillID: Hashable, Sendable, Codable, CustomStringConvertible {
    // MARK: Lifecycle

    /// Returns nil unless `rawValue` has at least a family and one more component, with no
    /// empty component and no whitespace.
    public init?(_ rawValue: String) {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty }),
              !rawValue.contains(where: \.isWhitespace)
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let id = SkillID(rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid skill id '\(rawValue)'")
        }
        self = id
    }

    // MARK: Public

    public let rawValue: String

    /// The first component, such as `letter`.
    public var family: Substring {
        rawValue.prefix { $0 != "." }
    }

    public var description: String { rawValue }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
