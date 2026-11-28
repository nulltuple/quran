//
//  PracticeRecitationTrackerTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import QuranKit
import QuranResources
import TestResources
import XCTest
@testable import RecitationRecognition

final class PracticeRecitationTrackerTests: XCTestCase {
    // MARK: Internal

    func testRevealsWordByWordAndAdvancesAcrossAlIkhlas() async throws {
        var tracker = try await makeTracker(sura: 112, ayahs: 1 ... 4)
        XCTAssertEqual(tracker.currentVerse, verse(112, 1))
        XCTAssertEqual(tracker.currentRevealedWords, 0)

        let first = tracker.update(with: recognized("قل هو الله"))
        XCTAssertEqual(first.completedVerses, [])
        XCTAssertEqual(first.revealedWords, 3)
        XCTAssertFalse(first.isOffTrack)

        let finishFirst = tracker.update(with: recognized("قل هو الله احد"))
        XCTAssertEqual(finishFirst.completedVerses, [verse(112, 1)])
        XCTAssertEqual(tracker.currentVerse, verse(112, 2))
        XCTAssertEqual(finishFirst.revealedWords, 0)

        let intoSecond = tracker.update(with: recognized("الله احد الله"))
        XCTAssertEqual(intoSecond.completedVerses, [])
        XCTAssertEqual(intoSecond.revealedWords, 1)

        let finishSecond = tracker.update(with: recognized("الله احد الله الصمد"))
        XCTAssertEqual(finishSecond.completedVerses, [verse(112, 2)])
        XCTAssertEqual(tracker.currentVerse, verse(112, 3))

        let finishThird = tracker.update(with: recognized("الله الصمد لم يلد ولم يولد"))
        XCTAssertEqual(finishThird.completedVerses, [verse(112, 3)])
        XCTAssertEqual(tracker.currentVerse, verse(112, 4))

        let finishFourth = tracker.update(with: recognized("ولم يولد ولم يكن له كفوا احد"))
        XCTAssertEqual(finishFourth.completedVerses, [verse(112, 4)])
        XCTAssertNil(tracker.currentVerse)
    }

    func testOneWordAndTwoWordSoleStretchesComplete() async throws {
        // 103:1 is a single canonical word (وَٱلۡعَصۡرِ).
        var single = try await makeTracker(sura: 103, ayahs: 1 ... 1)
        let singleUpdate = single.update(with: recognized("والعصر"))
        XCTAssertEqual(singleUpdate.completedVerses, [verse(103, 1)])
        XCTAssertNil(single.currentVerse)

        // 112:2 is two words (ٱللَّهُ ٱلصَّمَدُ).
        var pair = try await makeTracker(sura: 112, ayahs: 2 ... 2)
        let partial = pair.update(with: recognized("الله"))
        XCTAssertEqual(partial.completedVerses, [], "one word of a two-word ayah does not finish it")
        XCTAssertEqual(partial.revealedWords, 0)

        let done = pair.update(with: recognized("الله الصمد"))
        XCTAssertEqual(done.completedVerses, [verse(112, 2)])
        XCTAssertNil(pair.currentVerse)
    }

    func testSkippingTheCurrentAyahDoesNotCompleteIt() async throws {
        var tracker = try await makeTracker(sura: 112, ayahs: 1 ... 4)

        let skipped = tracker.update(with: recognized("الله الصمد"))
        XCTAssertEqual(skipped.completedVerses, [], "112:1 was never matched so reciting 112:2 must not pass 112:1")
        XCTAssertEqual(tracker.currentVerse, verse(112, 1))
        XCTAssertEqual(skipped.revealedWords, 0)
    }

    func testSeamlessCrossingAdvancesWhenCurrentAyahWasAlreadyMatched() async throws {
        var tracker = try await makeTracker(sura: 112, ayahs: 1 ... 4)

        // User matched 112:1 words 1..3, then word 4 was missed between hops and the next window reaches 112:2.
        let part = tracker.update(with: recognized("قل هو الله"))
        XCTAssertEqual(part.revealedWords, 3)

        let crossed = tracker.update(with: recognized("قل هو الله الله الصمد"))
        XCTAssertEqual(crossed.completedVerses, [verse(112, 1), verse(112, 2)])
        XCTAssertEqual(tracker.currentVerse, verse(112, 3))
    }

    func testManualSyncOverridesLiveProgressAndNeverUnreveals() async throws {
        var tracker = try await makeTracker(sura: 112, ayahs: 1 ... 4)
        tracker.sync(verse: verse(112, 1), revealedWords: 3)
        XCTAssertEqual(tracker.currentRevealedWords, 3)

        // An earlier window that only matches words 1..2 must not hide word 3.
        let earlier = tracker.update(with: recognized("قل هو"))
        XCTAssertEqual(earlier.revealedWords, 3)
        XCTAssertFalse(earlier.isOffTrack)

        // Manual advance to 112:2 moves the tracker cleanly.
        tracker.sync(verse: verse(112, 2), revealedWords: 0)
        XCTAssertEqual(tracker.currentVerse, verse(112, 2))
        XCTAssertEqual(tracker.currentRevealedWords, 0)
    }

    func testBasmalaAndSilenceDoNotMarkOffTrackAndRecoveryClearsIt() async throws {
        var tracker = try await makeTracker(sura: 112, ayahs: 1 ... 4)

        // Basmala before the sura is ignored.
        for _ in 0 ..< 4 {
            let opening = tracker.update(with: recognized("بسم الله الرحمن الرحيم"), isSpeaking: true)
            XCTAssertFalse(opening.isOffTrack)
        }

        // Silence with hallucinated words is not a miss.
        for _ in 0 ..< 4 {
            let quiet = tracker.update(with: recognized("رب العالمين مالك يوم الدين"), isSpeaking: false)
            XCTAssertFalse(quiet.isOffTrack)
        }

        // Three speaking misses mark off-track; matching the current ayah clears it.
        XCTAssertFalse(tracker.update(with: recognized("رب العالمين مالك"), isSpeaking: true).isOffTrack)
        XCTAssertFalse(tracker.update(with: recognized("رب العالمين مالك"), isSpeaking: true).isOffTrack)
        XCTAssertTrue(tracker.update(with: recognized("رب العالمين مالك"), isSpeaking: true).isOffTrack)

        let recovered = tracker.update(with: recognized("قل هو الله"), isSpeaking: true)
        XCTAssertFalse(recovered.isOffTrack)
        XCTAssertEqual(recovered.revealedWords, 3)
    }

    func testSelfCorrectionAtEndOfWindowStillMatches() async throws {
        var tracker = try await makeTracker(sura: 112, ayahs: 1 ... 4)
        let update = tracker.update(with: recognized("مالك يوم الدين قل هو الله"))
        XCTAssertEqual(update.revealedWords, 3)
        XCTAssertFalse(update.isOffTrack)
    }

    func testLongAyahBoundedLookaheadDoesNotJumpFarAhead() {
        // A 30-word ayah: saying a phrase from its ending (words 26..30) while at word 0
        // is outside the 15-unit forward bound and must not reveal the ayah.
        let ayah = verse(2, 255)
        let prefix = (1 ... 25).map { number in
            ExpectedWordText(words: [Word(verse: ayah, wordNumber: number)], text: "كلمة")
        }
        let ending = ["ولا", "يؤوده", "حفظهما", "وهو", "العلي"].enumerated().map { index, text in
            ExpectedWordText(words: [Word(verse: ayah, wordNumber: 26 + index)], text: text)
        }
        var tracker = PracticeRecitationTracker(expected: prefix + ending)
        let farEnd = tracker.update(with: recognized("ولا يؤوده حفظهما وهو العلي"))
        XCTAssertEqual(farEnd.completedVerses, [])
        XCTAssertEqual(farEnd.revealedWords, 0)
    }

    @MainActor
    func testClearBufferEmptiesRollingMicrophoneSamples() async throws {
        let microphone = RecitationMicrophone(keepingLatestSeconds: 4)
        let clip = TestResources.resourceURL("recitation/Husary_112001.mp3")
        try microphone.startSimulatedInput([clip])
        defer { _ = try? microphone.stop() }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(try microphone.recentSamples(seconds: 2).isEmpty)

        microphone.clearBuffer()
        XCTAssertTrue(try microphone.recentSamples(seconds: 2).isEmpty)
    }

    func testHurufMuqattaatThreeTokenSplitMatchesAndAdvances() {
        var tracker = makeInlineTracker([
            (verse(42, 1), ["حمٓ"]),
            (verse(42, 2), ["عٓسٓقٓ"]),
            (verse(42, 3), ["كَذَٰلِكَ", "يُوحِيٓ", "إِلَيۡكَ", "وَإِلَى", "ٱلَّذِينَ", "مِن", "قَبۡلِكَ", "ٱللَّهُ", "ٱلۡعَزِيزُ", "ٱلۡحَكِيمُ"]),
        ])
        let first = tracker.update(with: recognized("حم"))
        XCTAssertEqual(first.completedVerses, [verse(42, 1)])
        XCTAssertEqual(tracker.currentVerse, verse(42, 2))

        let second = tracker.update(with: recognized("حم ع س ق كذلك يوحي إليك"))
        XCTAssertEqual(second.completedVerses, [verse(42, 2)])
        XCTAssertEqual(tracker.currentVerse, verse(42, 3))
        XCTAssertGreaterThanOrEqual(second.revealedWords, 3)
        XCTAssertTrue(second.liveMistakes.isEmpty)
    }

    func testLiveInflectionSubstitutionFlagsZaliminVsZalimunAndDisputeClearsIt() throws {
        var tracker = makeInlineTracker([
            (verse(42, 8), ["وَلَوۡ", "شَآءَ", "ٱللَّهُ", "لَجَعَلَهُمۡ", "أُمَّةٗ", "وَٰحِدَةٗ", "وَلَٰكِن", "يُدۡخِلُ", "مَن", "يَشَآءُ", "فِي", "رَحۡمَتِهِۦۚ", "وَٱلظَّٰلِمُونَ", "مَا", "لَهُم", "مِّن", "وَلِيّٖ", "وَلَا", "نَصِيرٍ"]),
        ])
        let prefix = "ولو شاء الله لجعلهم امة واحدة ولكن يدخل من يشاء في رحمته"
        _ = tracker.update(with: recognized(prefix))

        // Two consecutive streaming windows hear والظالمين (instead of وَٱلظَّٰلِمُونَ) followed by the next words.
        _ = tracker.update(with: recognized("في رحمته والظالمين ما لهم من ولي"))
        let detected = tracker.update(with: recognized("في رحمته والظالمين ما لهم من ولي ولا نصير"))

        let target = Word(verse: verse(42, 8), wordNumber: 13)
        let mistake = try XCTUnwrap(detected.liveMistakes.first { $0.word == target })
        XCTAssertEqual(mistake.kind, .substitution)
        XCTAssertEqual(mistake.recitedText, "والظالمين")

        // Disputing removes the mistake and prevents re-flagging.
        tracker.removeMistake(for: target)
        XCTAssertTrue(tracker.activeMistakes.isEmpty)
    }

    func testLiveStumbleAndRestartHesitationAreFlaggedAtExactExpectedWord() {
        var tracker = makeInlineTracker([
            (verse(42, 5), ["تَكَادُ", "ٱلسَّمَٰوَٰتُ", "يَتَفَطَّرۡنَ", "مِن", "فَوۡقِهِنَّۚ", "وَٱلۡمَلَٰٓئِكَةُ", "يُسَبِّحُونَ", "بِحَمۡدِ", "رَبِّهِمۡ", "وَيَسۡتَغۡفِرُونَ", "لِمَن", "فِي", "ٱلۡأَرۡضِۗ"]),
        ])
        _ = tracker.update(with: recognized("تكاد السماوات يتفطرن من فوقهن والملائكة يسبحون بحمد ربهم"))

        // Reciter slips into 40:7 (ويؤمن به) right before 42:5:10 (وَيَسۡتَغۡفِرُونَ).
        _ = tracker.update(with: recognized("يسبحون بحمد ربهم ويؤمن به"))
        let stumbled = tracker.update(with: recognized("يسبحون بحمد ربهم ويؤمن به"))
        let expectedWord = Word(verse: verse(42, 5), wordNumber: 10)
        XCTAssertTrue(stumbled.liveMistakes.contains { $0.word == expectedWord && $0.kind == .stumble })
    }

    func testCleanWordConfirmedBehindLiveEdgeIsNeverRetroactivelyFlagged() {
        var tracker = makeInlineTracker([
            (verse(42, 9), ["أَمِ", "ٱتَّخَذُواْ", "مِن", "دُونِهِۦٓ", "أَوۡلِيَآءَۖ", "فَٱللَّهُ", "هُوَ", "ٱلۡوَلِيُّ", "وَهُوَ", "يُحۡيِ", "ٱلۡمَوۡتَىٰ", "وَهُوَ", "عَلَىٰ", "كُلِّ", "شَيۡءٖ", "قَدِيرٞ"]),
        ])
        _ = tracker.update(with: recognized("ام اتخذوا من دونه اولياء فالله هو الولي وهو يحيي الموتى"))
        // Even if a later sliding window mishears يحيي as المحيي, it was already confirmed clean.
        let later = tracker.update(with: recognized("فالله هو الولي وهو المحيي الموتى وهو على كل شيء قدير"))
        let yuhyi = Word(verse: verse(42, 9), wordNumber: 10)
        XCTAssertFalse(later.liveMistakes.contains { $0.word == yuhyi })
    }

    func testQuietAnchoredWindowCutsAtPauseInsteadOfMidSpeech() {
        let sr = RecitationAudio.sampleRate
        // 18 seconds of speech (0.2 amplitude) with a silent 0.2s pause at t=4.0s (rawStart = 4.0s for 14s target).
        var audio = [Float](repeating: 0.2, count: 18 * sr)
        let pauseStart = Int(3.2 * Double(sr))
        for i in pauseStart ..< pauseStart + Int(0.2 * Double(sr)) {
            audio[i] = 0.0001
        }
        let trimmed = RecitationAudio.quietAnchoredWindow(audio, targetSeconds: 14.0, searchSeconds: 4.0)
        // Expected start near 3.2s -> remaining ~14.8s (longer than naive 14.0s slice because pause was at 3.2s).
        XCTAssertGreaterThan(trimmed.count, Int(14.5 * Double(sr)))
        XCTAssertLessThan(trimmed.count, Int(15.0 * Double(sr)))
        XCTAssertLessThan(abs(trimmed[0]), 0.001, "window should start inside the quiet pause")
    }

    // MARK: Private

    private func verse(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: sura, ayah: ayah)!
    }

    private func recognized(_ text: String) -> [RecognizedWord] {
        text.split(separator: " ").map { RecognizedWord(text: String($0), frames: nil) }
    }

    private func makeTracker(sura: Int, ayahs: ClosedRange<Int>) async throws -> PracticeRecitationTracker {
        let verseText = RecitationVerseText(
            quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
            wordByWordDatabase: TestResources.resourceURL("word_by_word.db")
        )
        let verses = ayahs.map { verse(sura, $0) }
        let expected = try await verseText.expectedWords.expectedWords(for: verses)
        return PracticeRecitationTracker(expected: expected)
    }

    private func makeInlineTracker(_ verses: [(AyahNumber, [String])]) -> PracticeRecitationTracker {
        let expected = verses.flatMap { ayah, words in
            words.enumerated().map { index, text in
                ExpectedWordText(words: [Word(verse: ayah, wordNumber: index + 1)], text: text)
            }
        }
        return PracticeRecitationTracker(expected: expected)
    }
}
