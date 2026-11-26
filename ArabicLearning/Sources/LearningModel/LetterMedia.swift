//
//  LetterMedia.swift
//  ArabicLearning (Arabican app)
//

import ArabicScript
import Foundation

/// One recording of a letter (Antura, CC-BY-4.0): its name, or the letter with a short vowel or
/// sukun. The audition log is `Documentation/ArabicLearning/04-audio-audition.md`.
public struct AudioClip: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case name
        case fatha
        case kasra
        case damma
        case sukun
    }

    public init(letter: ArabicLetter, kind: Kind, url: URL) {
        self.letter = letter
        self.kind = kind
        self.url = url
    }

    public let letter: ArabicLetter
    public let kind: Kind
    /// The bundled audio file.
    public let url: URL
}

/// A point on the tracing canvas, as fractions of its side: x to the right, y down.
public struct CanvasPoint: Hashable, Sendable {
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public let x: Double
    public let y: Double

    public func distance(to other: CanvasPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// One stroke of a letter's guide (Noorine, MIT), in writing order and direction.
public struct GuideStroke: Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// A polyline drawn from its first point to its last.
        case path
        /// One tap.
        case dot
    }

    public init(kind: Kind, points: [CanvasPoint]) {
        self.kind = kind
        self.points = points
    }

    public let kind: Kind
    public let points: [CanvasPoint]
}

/// The letters a Quran word holds. `exact` letters are written with their own character; the
/// others are only implied by a spelling variant or small letter (ٱ, أ, ة, ى, ۥ, dagger alif),
/// so they are never asked for and never offered as wrong answers.
public struct WordLetters: Hashable, Sendable {
    public init(word: QuranWordText, exact: Set<ArabicLetter>, implied: Set<ArabicLetter>) {
        self.word = word
        self.exact = exact
        self.implied = implied
    }

    public let word: QuranWordText
    public let exact: Set<ArabicLetter>
    public let implied: Set<ArabicLetter>

    /// Whether the word holds `letter` in any spelling.
    public func holds(_ letter: ArabicLetter) -> Bool {
        exact.contains(letter) || implied.contains(letter)
    }
}
