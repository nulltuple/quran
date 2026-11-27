//
//  WordStudyHearingTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import AVFoundation
import QuranAudio
import QuranAudioKit
import QuranKit
import ReciterServiceFake
import TestResources
import WordTextService
import XCTest
@testable import WordStudyFeature

/// Hearing a word with the real QUL timings (`qul_afasy.db`: 1:1 word 1 is 0–0.8 s, 1:2 word 1 is
/// 5.684–7.230 s, 2:27 word 18 has none) and a real `WordRecitationPlayer` on local files.
@MainActor
final class WordStudyHearingTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_aWordWithATimingCanBeHeard() async {
        let viewModel = makeViewModel(word: word(1, 2, 1), reciter: .wordTimingReciter)

        await viewModel.load()

        XCTAssertEqual(viewModel.hearing, .ready(WordRecitation(
            word: word(1, 2, 1),
            reciter: .wordTimingReciter,
            url: Reciter.wordTimingReciter.remoteURL(sura: quran.suras[0]),
            start: 5.684,
            end: 7.230
        )))
    }

    func test_aWordWithoutItsOwnTimingCannotBeHeard() async {
        let viewModel = makeViewModel(word: word(2, 27, 18), reciter: .wordTimingReciter)

        await viewModel.load()

        XCTAssertEqual(viewModel.hearing, .unavailable)
    }

    func test_withoutAPlayerTheWordCannotBeHeard() async {
        let viewModel = WordStudyViewModel(
            word: word(1, 2, 1),
            service: service(),
            language: .english,
            recitations: WordRecitationRetriever(reciter: .wordTimingReciter)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.hearing, .unavailable)
    }

    func test_hearingPausesTheRecitationAndPlaysTheExcerptToItsEnd() async throws {
        try writeSilence(seconds: 2, to: directory.appendingPathComponent("001.mp3"))
        var pauses = 0
        let viewModel = makeViewModel(word: word(1, 1, 1), reciter: reciter(audioURL: directory)) { pauses += 1 }
        await viewModel.load()
        guard case .ready(let recitation) = viewModel.hearing else {
            return XCTFail("Expected a recitation, got \(viewModel.hearing)")
        }

        let start = Date()
        await viewModel.toggleHearing()

        XCTAssertEqual(pauses, 1)
        XCTAssertEqual(viewModel.hearing, .ready(recitation), "Played to its end, not failed")
        // The excerpt is 0.8 s of a 2 s file: it stops at its end, not the file's.
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.9)
    }

    func test_aRecordingThatCannotBeLoadedFailsAndCanBeTriedAgain() async {
        var pauses = 0
        let missing = directory.appendingPathComponent("missing", isDirectory: true)
        let viewModel = makeViewModel(word: word(1, 2, 1), reciter: reciter(audioURL: missing)) { pauses += 1 }
        await viewModel.load()
        guard case .ready(let recitation) = viewModel.hearing else {
            return XCTFail("Expected a recitation, got \(viewModel.hearing)")
        }

        await viewModel.toggleHearing()
        XCTAssertEqual(viewModel.hearing, .failed(recitation))

        await viewModel.toggleHearing()
        XCTAssertEqual(viewModel.hearing, .failed(recitation))
        XCTAssertEqual(pauses, 2)
    }

    func test_leavingTheStudyStopsTheWord() async throws {
        try writeSilence(seconds: 10, to: directory.appendingPathComponent("001.mp3"))
        // 1:2 word 1 starts at 5.684 s and lasts 1.5 s.
        let viewModel = makeViewModel(word: word(1, 2, 1), reciter: reciter(audioURL: directory))
        await viewModel.load()
        guard case .ready(let recitation) = viewModel.hearing else {
            return XCTFail("Expected a recitation, got \(viewModel.hearing)")
        }

        let hearing = Task { await viewModel.toggleHearing() }
        for _ in 0 ..< 100 where viewModel.hearing == .ready(recitation) {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.hearing, .playing(recitation))
        viewModel.didDisappear()
        await hearing.value

        XCTAssertEqual(viewModel.hearing, .ready(recitation))
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405
    private var directory: URL!

    private func makeViewModel(word: Word, reciter: Reciter, pauseRecitation: @escaping () -> Void = {}) -> WordStudyViewModel {
        WordStudyViewModel(
            word: word,
            service: service(),
            language: .english,
            recitations: WordRecitationRetriever(reciter: reciter),
            recitationPlayer: WordRecitationPlayer(),
            pauseRecitation: pauseRecitation
        )
    }

    /// The word-timing reciter, with its sura files at `audioURL`.
    private func reciter(audioURL: URL) -> Reciter {
        Reciter(
            id: 1001,
            nameKey: "qari_afasy_qul_word_by_word",
            directory: "word-study-hearing-tests",
            audioURL: audioURL,
            audioType: .gapless(databaseName: "qul_afasy"),
            hasGaplessAlternative: false,
            category: .arabic,
            bundledTimingDatabase: TestResources.resourceURL("qul_afasy.db")
        )
    }

    /// A silent mono AAC file (in an MP4 container, which AVFoundation reads whatever its name).
    private func writeSilence(seconds: Double, to url: URL) throws {
        let sampleRate = 22050.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let m4a = url.deletingPathExtension().appendingPathExtension("m4a")
        do {
            let file = try AVAudioFile(forWriting: m4a, settings: settings)
            let frames = AVAudioFrameCount(seconds * sampleRate)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            try file.write(from: buffer)
        }
        try FileManager.default.moveItem(at: m4a, to: url)
    }

    private func service() -> WordStudyService {
        WordStudyService(
            morphologyFileURL: TestResources.resourceURL("quran_morphology.db"),
            wordByWordFileURL: TestResources.resourceURL("word_by_word.db")
        )
    }

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: AyahNumber(quran: quran, sura: sura, ayah: ayah)!, wordNumber: number)
    }
}
