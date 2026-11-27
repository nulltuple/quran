//
//  WordRecitationRetriever.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import AudioTimingService
import Foundation
import QuranAudio
import QuranKit
import ReciterService

/// Where one word is recited: a time range inside a reciter's recording of the whole sura.
/// It is an excerpt of connected speech, so its edges can carry sounds of the neighboring words.
public struct WordRecitation: Hashable, Sendable {
    // MARK: Lifecycle

    public init(word: Word, reciter: Reciter, url: URL, start: TimeInterval, end: TimeInterval) {
        self.word = word
        self.reciter = reciter
        self.url = url
        self.start = start
        self.end = end
    }

    // MARK: Public

    public let word: Word
    public let reciter: Reciter
    /// The downloaded sura file when it exists, otherwise its remote URL (streamed).
    public let url: URL
    public let start: TimeInterval
    public let end: TimeInterval

    public var isDownloaded: Bool { url.isFileURL }
}

/// Finds a word's recitation in the recording of the reciter whose bundled timing database has
/// word timings (Mishary Al-Afasy, QUL).
public struct WordRecitationRetriever: Sendable {
    // MARK: Lifecycle

    /// Cuts words from the first of the app's reciters with word timings.
    public init(reciters: ReciterDataRetriever = ReciterDataRetriever()) {
        reciter = { await Self.wordTimingReciter(in: reciters.getReciters()) }
    }

    /// Cuts words from `reciter`'s recordings; `nil` finds no words.
    public init(reciter: Reciter?) {
        self.reciter = { reciter }
    }

    // MARK: Public

    /// The reciter whose recordings this retriever cuts words from: the first with a bundled
    /// timing database, the only kind that has word timings today.
    public static func wordTimingReciter(in reciters: [Reciter]) -> Reciter? {
        reciters.first { $0.bundledTimingDatabase != nil }
    }

    /// `nil` when no reciter has word timings, or the word has no timing of its own (QUL merges
    /// some short words into the previous word's timing).
    public func recitation(of word: Word) async throws -> WordRecitation? {
        guard let reciter = await reciter() else {
            return nil
        }
        let timings = try await ReciterTimingRetriever().wordTimings(for: reciter, suras: [word.verse.sura])
        // A reciter who goes back repeats words; the first recitation is the word in its place.
        guard let timing = timings[word.verse]?.words.first(where: { $0.word == word.wordNumber }) else {
            return nil
        }
        let localFile = reciter.localURL(sura: word.verse.sura)
        let url = localFile.isReachable ? localFile.url : reciter.remoteURL(sura: word.verse.sura)
        return WordRecitation(word: word, reciter: reciter, url: url, start: timing.start, end: timing.end)
    }

    // MARK: Private

    private let reciter: @Sendable () async -> Reciter?
}
