//
//  QuranAudioPlayerWordTests.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import AVFoundation
import QuranAudio
import QuranKit
import ReciterServiceFake
import Utilities
import XCTest
@testable import QueuePlayer
@testable import QuranAudioKit

/// Word-by-word recitation with the real QUL timings for Al-Fatiha (`qul_afasy.db` in TestResources):
/// 1:1 words start at 0, 0.8, 1.6 and 2.76 s; 1:2 starts at 5.684 s.
final class QuranAudioPlayerWordTests: XCTestCase {
    // MARK: Internal

    @MainActor
    override func setUp() async throws {
        queuePlayer = QueuePlayerFake()
        player = QuranAudioPlayer(player: queuePlayer)
        words = []
        player.setActions(QuranAudioPlayerActions(
            playbackEnded: {},
            playbackPaused: {},
            playbackResumed: {},
            playing: { _ in },
            playingWord: { [weak self] in self?.words.append($0) }
        ))
    }

    @MainActor
    override func tearDown() async throws {
        Reciter.cleanUpAudio()
    }

    @MainActor
    func test_followsTheRecitedWordByMediaTime() async throws {
        try await play(.wordTimingReciter, from: verse(1, 1), to: verse(1, 7))

        frameChanged(0)
        time(0.1)
        time(0.5) // Same word; not reported again.
        time(0.9)
        time(1.57) // Between words 2 and 3; word 2 stays.
        time(2.8)

        XCTAssertEqual(words, [word(1, 1, 1), word(1, 1, 2), word(1, 1, 4)])
    }

    @MainActor
    func test_aNewAyahClearsTheWordUntilItsFirstWord() async throws {
        try await play(.wordTimingReciter, from: verse(1, 1), to: verse(1, 7))
        frameChanged(0)
        time(3)

        frameChanged(1)
        time(5.69)

        XCTAssertEqual(words, [word(1, 1, 4), nil, word(1, 2, 1)])
    }

    @MainActor
    func test_aRepeatedAyahHighlightsItsWordsAgain() async throws {
        try await play(.wordTimingReciter, from: verse(1, 1), to: verse(1, 1), verseRuns: .finite(2))
        frameChanged(0)
        time(3)

        // The player seeks back to the ayah's start for the second run.
        frameChanged(0)
        time(0.1)

        XCTAssertEqual(words, [word(1, 1, 4), nil, word(1, 1, 1)])
    }

    @MainActor
    func test_aRepeatedRangeStartsAgainFromItsFirstAyah() async throws {
        // 1:2 and 1:3 repeated twice: frames 0 and 1 of the sura's file.
        try await play(.wordTimingReciter, from: verse(1, 2), to: verse(1, 3), listRuns: .finite(2))
        frameChanged(0)
        time(5.7)
        frameChanged(1)
        time(11.5)

        frameChanged(0)
        time(5.7)

        XCTAssertEqual(words, [word(1, 2, 1), nil, word(1, 3, 1), nil, word(1, 2, 1)])
    }

    @MainActor
    func test_playbackEndClearsTheWord() async throws {
        try await play(.wordTimingReciter, from: verse(1, 1), to: verse(1, 7))
        frameChanged(0)
        time(0.1)

        queuePlayer.actions?.playbackEnded()

        XCTAssertEqual(words, [word(1, 1, 1), nil])
    }

    @MainActor
    func test_noWordsForAReciterWithoutWordTimings() async throws {
        let reciter = Reciter.gaplessReciter
        try reciter.prepareGaplessReciterForTests()
        try await play(reciter, from: verse(1, 1), to: verse(1, 7))

        frameChanged(0)
        time(0.1)

        XCTAssertEqual(words, [])
    }

    @MainActor
    func test_onlyAReciterWithWordTimingsAsksForPlaybackTime() async throws {
        try await play(.wordTimingReciter, from: verse(1, 1), to: verse(1, 7))
        XCTAssertEqual(playingRequest?.reportsPlaybackTime, true)

        let reciter = Reciter.gaplessReciter
        try reciter.prepareGaplessReciterForTests()
        try await play(reciter, from: verse(1, 1), to: verse(1, 7))
        XCTAssertEqual(playingRequest?.reportsPlaybackTime, false, "No time observer wakes the app for other reciters")
    }

    @MainActor
    func test_aTimeFromAnotherAyahNeverLeaksAcrossAyahs() async throws {
        try await play(.wordTimingReciter, from: verse(1, 1), to: verse(1, 7))

        frameChanged(1)
        // A late time from the end of 1:1 (still word 4 there) arrives after 1:2 started.
        time(2.8)

        XCTAssertEqual(words.compactMap { $0 }.map(\.verse), [], "1:1's words aren't 1:2's")
    }

    @MainActor
    func test_aBundledTimingDatabaseNeedsNoDownload() {
        let reciter = Reciter.wordTimingReciter

        let files = reciter.audioFiles(baseURL: URL(validURL: "https://example.com"), from: verse(1, 1), to: verse(1, 7))

        XCTAssertEqual(files.map(\.local.url.lastPathComponent), ["001.mp3"])
        XCTAssertNil(reciter.localDatabasePath)
        XCTAssertEqual(reciter.timingDatabaseURL, reciter.bundledTimingDatabase)
    }

    // MARK: Private

    private var player: QuranAudioPlayer!
    private var queuePlayer: QueuePlayerFake!
    private var words: [Word?] = []

    private let quran = Quran.hafsMadani1405

    private func verse(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: verse(sura, ayah), wordNumber: number)
    }

    @MainActor
    private func play(
        _ reciter: Reciter,
        from start: AyahNumber,
        to end: AyahNumber,
        verseRuns: Runs = .finite(1),
        listRuns: Runs = .finite(1)
    ) async throws {
        try await player.play(reciter: reciter, rate: 1, from: start, to: end, verseRuns: verseRuns, listRuns: listRuns)
    }

    @MainActor private var playingRequest: AudioRequest? {
        if case .playing(let request) = queuePlayer.state {
            return request
        }
        return nil
    }

    @MainActor
    private func frameChanged(_ frame: Int) {
        queuePlayer.actions?.audioFrameChanged(0, frame, AVPlayerItem(url: FileManager.documentsURL), nil)
    }

    @MainActor
    private func time(_ seconds: TimeInterval) {
        queuePlayer.actions?.playbackTimeChanged(0, seconds)
    }
}
