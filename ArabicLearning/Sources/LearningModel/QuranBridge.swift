//
//  QuranBridge.swift
//  ArabicLearning (Arabican app)
//

import Foundation
import QuranKit

/// A stretch of a bundled recording, in seconds.
public struct RecitationSegment: Hashable, Sendable {
    public init(url: URL, start: TimeInterval, end: TimeInterval) {
        self.url = url
        self.start = start
        self.end = end
    }

    public let url: URL
    public let start: TimeInterval
    public let end: TimeInterval
}

/// A word's meaning in context and its transliteration (QUL word by word, as the reader shows them).
public struct WordMeaning: Hashable, Sendable {
    public init(english: String, bengali: String, transliteration: String) {
        self.english = english
        self.bengali = bengali
        self.transliteration = transliteration
    }

    public let english: String
    public let bengali: String
    public let transliteration: String
}

/// A word of a bridge sura: its canonical text, meaning, and when the reciter first says it.
public struct BridgeWord: Hashable, Sendable {
    public init(word: QuranWordText, meaning: WordMeaning, start: TimeInterval, end: TimeInterval) {
        self.word = word
        self.meaning = meaning
        self.start = start
        self.end = end
    }

    public let word: QuranWordText
    public let meaning: WordMeaning
    public let start: TimeInterval
    public let end: TimeInterval
}

public struct BridgeAyah: Hashable, Sendable {
    public init(ayah: AyahNumber, start: TimeInterval, end: TimeInterval, words: [BridgeWord]) {
        self.ayah = ayah
        self.start = start
        self.end = end
        self.words = words
    }

    public let ayah: AyahNumber
    public let start: TimeInterval
    public let end: TimeInterval
    public let words: [BridgeWord]
}

/// One recited word, repeats included, in recording order (QUL word segments).
public struct WordTiming: Hashable, Sendable {
    public init(word: Word, start: TimeInterval, end: TimeInterval) {
        self.word = word
        self.start = start
        self.end = end
    }

    public let word: Word
    public let start: TimeInterval
    public let end: TimeInterval
}

/// A sura of the Quran bridge (U8) with its bundled recitation and word timings.
public struct BridgeSura: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(sura: Int, title: String, recording: URL, ayahs: [BridgeAyah], timings: [WordTiming]) {
        self.sura = sura
        self.title = title
        self.recording = recording
        self.ayahs = ayahs
        self.timings = timings
    }

    // MARK: Public

    public let sura: Int
    /// The transliterated name, such as "Al-Fatihah".
    public let title: String
    public let recording: URL
    public let ayahs: [BridgeAyah]
    public let timings: [WordTiming]

    public var id: Int { sura }

    public var words: [BridgeWord] {
        ayahs.flatMap(\.words)
    }

    /// When the recitation ends.
    public var end: TimeInterval {
        ayahs.last?.end ?? 0
    }

    public func segment(_ word: BridgeWord) -> RecitationSegment {
        RecitationSegment(url: recording, start: word.start, end: word.end)
    }

    public func segment(_ ayah: BridgeAyah) -> RecitationSegment {
        RecitationSegment(url: recording, start: ayah.start, end: ayah.end)
    }

    /// The word being recited at `time`: the last word started, held through the pause before
    /// the next one; nil before the first word and after the recitation ends.
    public func word(at time: TimeInterval) -> Word? {
        guard time < end else { return nil }
        // Timings are in recording order; find the last one that started.
        var low = 0
        var high = timings.count
        while low < high {
            let middle = (low + high) / 2
            if timings[middle].start <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low == 0 ? nil : timings[low - 1].word
    }
}

/// A Quran lemma (Quranic Arabic Corpus) with its Quran-wide count and glosses.
public struct Lemma: Hashable, Sendable {
    public init(text: String, rank: Int, root: String, partOfSpeech: String, occurrences: Int, english: String, bengali: String) {
        self.text = text
        self.rank = rank
        self.root = root
        self.partOfSpeech = partOfSpeech
        self.occurrences = occurrences
        self.english = english
        self.bengali = bengali
    }

    /// As QAC writes it, such as `رَبّ`; also the subject of its skill, `lemma.meaning.<text>`.
    public let text: String
    /// 1 is the most frequent lemma.
    public let rank: Int
    /// Root letters without separators, or empty for particles and pronouns.
    public let root: String
    /// An English label such as "noun" or "verb, form IV".
    public let partOfSpeech: String
    public let occurrences: Int
    /// May be empty for a lemma outside the vocabulary list.
    public let english: String
    public let bengali: String
}

/// One morphological segment of a Quran word, such as the prefix `بِ` of `بِسۡمِ`.
public struct WordSegment: Hashable, Sendable {
    public enum Role: String, Sendable {
        case prefix
        case stem
        case suffix
    }

    public init(text: String, role: Role, lemma: Lemma?, root: String, partOfSpeech: String) {
        self.text = text
        self.role = role
        self.lemma = lemma
        self.root = root
        self.partOfSpeech = partOfSpeech
    }

    /// QAC's spelling of the segment (it may differ in small marks from the canonical word).
    public let text: String
    public let role: Role
    /// Nil for pronoun suffixes, which QAC gives no lemma.
    public let lemma: Lemma?
    public let root: String
    public let partOfSpeech: String
}
