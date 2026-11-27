//
//  RecitationFollowerTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import QuranKit
import XCTest
@testable import RecitationRecognition

/// The follower on hand-written windows (plain spellings, as the model writes them) against the
/// bundled Uthmani words of the test word database.
final class RecitationFollowerTests: XCTestCase {
    // MARK: Internal

    func testTheFirstWindowThatFitsStartsFollowingAtItsLastWord() async throws {
        var follower = try await follower(from: verse(112, 1), through: verse(114, 6))
        XCTAssertEqual(follower.state, .searching)

        follower.update(with: words("قل هو الله احد"))

        XCTAssertEqual(follower.state, .following(word(112, 1, 4)))
        XCTAssertEqual(follower.word, word(112, 1, 4))
    }

    func testTheWindowSlidesForwardThroughTheVerses() async throws {
        var follower = try await follower(from: verse(112, 1), through: verse(114, 6))
        follower.update(with: words("قل هو الله احد"))
        follower.update(with: words("هو الله احد الله الصمد"))
        XCTAssertEqual(follower.state, .following(word(112, 2, 2)))
        follower.update(with: words("الله الصمد لم يلد ولم"))
        XCTAssertEqual(follower.state, .following(word(112, 3, 3)))
        // The window's last word is cut off by the window edge: the place is the last word that fits.
        follower.update(with: words("لم يلد ولم يولد ولم يك"))
        XCTAssertEqual(follower.state, .following(word(112, 4, 1)))
    }

    func testFollowingCrossesIntoTheNextSuraAfterTheBasmala() async throws {
        var follower = try await follower(from: verse(112, 1), through: verse(114, 6))
        follower.update(with: words("ولم يكن له كفوا احد"))
        XCTAssertEqual(follower.state, .following(word(112, 4, 5)))
        // The basmala before 113 is not a miss.
        for _ in 0 ..< RecitationFollower.missesBeforeLost {
            follower.update(with: words("كفوا احد بسم الله الرحمن الرحيم"))
        }
        XCTAssertEqual(follower.state, .following(word(112, 4, 5)))
        follower.update(with: words("الرحمن الرحيم قل اعوذ برب الفلق"))
        XCTAssertEqual(follower.state, .following(word(113, 1, 4)))
    }

    func testARepeatedPhraseIsFollowedWhereTheReciterIs() async throws {
        // 114:1–3 are "the Lord / King / God of mankind": "الناس" ends each of them.
        var follower = try await follower(from: verse(114, 1), through: verse(114, 6))
        follower.update(with: words("قل اعوذ برب الناس ملك الناس"))
        XCTAssertEqual(follower.state, .following(word(114, 2, 2)))
        follower.update(with: words("ملك الناس اله الناس"))
        XCTAssertEqual(follower.state, .following(word(114, 3, 2)))
    }

    func testGoingBackToRepeatAVerseFollowsTheRepeat() async throws {
        var follower = try await follower(from: verse(112, 1), through: verse(114, 6))
        follower.update(with: words("قل هو الله احد الله الصمد لم يلد ولم يولد"))
        XCTAssertEqual(follower.state, .following(word(112, 3, 4)))
        follower.update(with: words("لم يلد ولم يولد الله الصمد"))
        XCTAssertEqual(follower.state, .following(word(112, 2, 2)))
    }

    func testSilenceKeepsThePlace() async throws {
        var follower = try await follower(from: verse(112, 1), through: verse(114, 6))
        follower.update(with: words("قل هو الله احد"))
        for _ in 0 ..< 10 {
            follower.update(with: [])
        }
        XCTAssertEqual(follower.state, .following(word(112, 1, 4)))
    }

    func testRecitationElsewhereLosesThePlaceAfterThreeMisses() async throws {
        var follower = try await follower(from: verse(112, 1), through: verse(114, 6))
        follower.update(with: words("قل هو الله احد"))
        // Al-Fatihah is not in the followed passage.
        let elsewhere = words("الحمد لله رب العالمين الرحمن الرحيم مالك يوم الدين")
        for _ in 1 ..< RecitationFollower.missesBeforeLost {
            follower.update(with: elsewhere)
            XCTAssertEqual(follower.state, .following(word(112, 1, 4)), "one or two misses keep the place")
        }
        follower.update(with: elsewhere)
        XCTAssertEqual(follower.state, .lost(lastWord: word(112, 1, 4)))

        // Coming back to the passage finds the place again.
        follower.update(with: words("الله الصمد لم يلد"))
        XCTAssertEqual(follower.state, .following(word(112, 3, 2)))
    }

    func testRecitationBeforeTheFirstFitKeepsSearching() async throws {
        var follower = try await follower(from: verse(112, 1), through: verse(114, 6))
        // Room noise, or recitation of another passage, before the place is found.
        let elsewhere = words("الحمد لله رب العالمين الرحمن الرحيم مالك يوم الدين")
        for _ in 0 ..< RecitationFollower.missesBeforeLost {
            XCTAssertFalse(follower.hasMissedRepeatedly)
            follower.update(with: elsewhere)
        }
        XCTAssertEqual(follower.state, .searching, "there is no place to lose yet")
        XCTAssertTrue(follower.hasMissedRepeatedly, "the caller may look for the passage elsewhere")

        follower.update(with: words("قل هو الله احد"))
        XCTAssertEqual(follower.state, .following(word(112, 1, 4)))
        XCTAssertFalse(follower.hasMissedRepeatedly)
    }

    func testWordsHeardInAPauseAreNotAMiss() async throws {
        var follower = try await follower(from: verse(112, 1), through: verse(114, 6))
        follower.update(with: words("قل هو الله احد"))
        // A noisy room after the reciter stops: the model hears a word or two that fit nothing.
        for _ in 0 ..< 2 * RecitationFollower.missesBeforeLost {
            follower.update(with: words("ها من"), isSpeaking: false)
        }
        XCTAssertEqual(follower.state, .following(word(112, 1, 4)))
        XCTAssertFalse(follower.hasMissedRepeatedly)
    }

    func testSpeechIsMeasuredFromTheRoomsNoise() {
        let second = RecitationAudio.sampleRate
        func window(_ levels: [Float]) -> [Float] {
            // One level a tenth of a second.
            levels.flatMap { [Float](repeating: $0, count: second / 10) }
        }
        var level = SpeechLevel()
        XCTAssertFalse(level.isSpeech(window: window(Array(repeating: 0.005, count: 10))), "below the speech floor")

        var noisyRoom = SpeechLevel()
        XCTAssertFalse(noisyRoom.isSpeech(window: window(Array(repeating: 0.03, count: 10))), "a noisy room alone")
        XCTAssertFalse(noisyRoom.isSpeech(window: window(Array(repeating: 0.06, count: 10))), "twice the room's noise is the room")
        XCTAssertTrue(noisyRoom.isSpeech(window: window(Array(repeating: 0.03, count: 10) + Array(repeating: 0.2, count: 10))))

        // A window recited from its first sample: the gap between two words is the room.
        var recitedAtOnce = SpeechLevel()
        XCTAssertTrue(recitedAtOnce.isSpeech(window: window([0.3, 0.4, 0.02, 0.5, 0.3, 0.4, 0.5, 0.3, 0.2, 0.4])))
        XCTAssertFalse(recitedAtOnce.isSpeech(window: window(Array(repeating: 0.03, count: 10))), "then the pause after it")
        XCTAssertEqual(SpeechLevel.peak(of: [0.1, -0.4, 0.3]), 0.4)
    }

    func testOneCommonWordDoesNotStartFollowing() async throws {
        var follower = try await follower(from: verse(112, 1), through: verse(114, 6))
        follower.update(with: words("الله"))
        follower.update(with: words("الله الناس"))
        XCTAssertEqual(follower.state, .searching)
    }

    func testTheOpeningIsRecognizedByItsWords() {
        XCTAssertTrue(RecitationFollower.isOpening(words("بسم الله الرحمن الرحيم")))
        XCTAssertTrue(RecitationFollower.isOpening(words("اعوذ بالله من الشيطان")))
        XCTAssertFalse(RecitationFollower.isOpening(words("قل هو الله احد")))
    }

    func testAppendingKeepsThePlaceAndDropsOldUnits() async throws {
        let reader = ExpectedWordsReaderTests.makeReader()
        var follower = RecitationFollower(expected: try await reader.expectedWords(for: verses(from: verse(80, 1), through: verse(80, 42))))
        follower.update(with: words("يوم يفر المرء من اخيه"))
        let place = try XCTUnwrap(follower.word)
        XCTAssertEqual(place, word(80, 34, 5))
        XCTAssertTrue(follower.needsMoreText, "80:35–42 leave fewer units ahead than the follower keeps")

        let more = try await reader.expectedWords(for: verses(from: verse(81, 1), through: verse(86, 17)))
        follower.append(more)

        XCTAssertEqual(follower.word, place, "the place is the same word")
        XCTAssertEqual(follower.lastVerse, verse(86, 17))
        XCTAssertFalse(follower.needsMoreText)
        let firstKept = try XCTUnwrap(follower.expected.first?.words.first)
        XCTAssertGreaterThan(firstKept.verse, verse(80, 1), "units long behind the place are dropped")
        XCTAssertEqual(follower.expected.firstIndex { $0.words.contains(place) }, RecitationFollower.unitsBehind)
        // Following goes on from the place.
        follower.update(with: words("يفر المرء من اخيه وامه وابيه"))
        XCTAssertEqual(follower.word, word(80, 35, 2))
    }

    func testAlignWithinCoversOnlyTheRecitedPart() async throws {
        let expected = try await ExpectedWordsReaderTests.makeReader().expectedWords(for: verses(from: verse(112, 1), through: verse(112, 4)))
        let steps = WordAligner().alignWithin(words("الله الصمد لم يلد"), to: expected, preferredEnd: 0)
        XCTAssertEqual(steps.map(\.kind), [.matched, .matched, .matched, .matched])
        XCTAssertEqual(steps.flatMap(\.expected), [word(112, 2, 1), word(112, 2, 2), word(112, 3, 1), word(112, 3, 2)])
        XCTAssertEqual(steps.map(\.expectedUnits), [4 ..< 5, 5 ..< 6, 6 ..< 7, 7 ..< 8])
    }

    func testAlignWithinPrefersTheEqualPlaceNearestThePreferredEnd() async throws {
        let expected = try await ExpectedWordsReaderTests.makeReader().expectedWords(for: verses(from: verse(114, 1), through: verse(114, 6)))
        // "الناس" alone fits the end of 114:1, 2, 3 and 5 equally (114:6 ends with وَٱلنَّاسِ).
        let nearStart = WordAligner().alignWithin(words("الناس"), to: expected, preferredEnd: 0)
        XCTAssertEqual(nearStart.flatMap(\.expected), [word(114, 1, 4)])
        let nearEnd = WordAligner().alignWithin(words("الناس"), to: expected, preferredEnd: expected.count - 1)
        XCTAssertEqual(nearEnd.flatMap(\.expected), [word(114, 5, 5)])
    }

    func testTheMicrophoneKeepsTheLatestSamplesWhenFollowing() {
        var samples: [Float] = []
        for chunk in 0 ..< 10 {
            let incoming = [Float](repeating: Float(chunk), count: 3)
            incoming.withUnsafeBufferPointer { RecitationMicrophone.append($0, to: &samples, capacity: 5, keepsLatest: true) }
            XCTAssertLessThanOrEqual(samples.count, 10, "never more than twice the capacity")
        }
        XCTAssertEqual(Array(samples.suffix(5)), [8, 8, 9, 9, 9])

        var first: [Float] = []
        for chunk in 0 ..< 3 {
            let incoming = [Float](repeating: Float(chunk), count: 3)
            incoming.withUnsafeBufferPointer { RecitationMicrophone.append($0, to: &first, capacity: 5, keepsLatest: false) }
        }
        XCTAssertEqual(first, [0, 0, 0, 1, 1], "a search keeps the first samples")

        var oversized: [Float] = [1, 2]
        [Float](repeating: 7, count: 12).withUnsafeBufferPointer {
            RecitationMicrophone.append($0, to: &oversized, capacity: 5, keepsLatest: true)
        }
        XCTAssertEqual(oversized, [7, 7, 7, 7, 7])
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405

    private func verse(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: verse(sura, ayah), wordNumber: number)
    }

    private func words(_ transcript: String) -> [RecognizedWord] {
        RecognizedWord.words(of: transcript)
    }

    private func verses(from first: AyahNumber, through last: AyahNumber) -> [AyahNumber] {
        first.array(to: last)
    }

    private func follower(from first: AyahNumber, through last: AyahNumber) async throws -> RecitationFollower {
        let expected = try await ExpectedWordsReaderTests.makeReader().expectedWords(for: verses(from: first, through: last))
        return RecitationFollower(expected: expected)
    }
}
