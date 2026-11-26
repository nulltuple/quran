import LearningModel
import QuranKit
import QuranText
import XCTest

final class BridgeSuraTests: XCTestCase {
    private let quran = Quran.hafsMadani1405

    private func word(_ ayah: Int, _ number: Int) -> Word {
        Word(verse: AyahNumber(quran: quran, sura: 112, ayah: ayah)!, wordNumber: number)
    }

    private func bridgeWord(_ ayah: Int, _ number: Int, _ start: TimeInterval, _ end: TimeInterval) -> BridgeWord {
        let text = QuranWordText(word: word(ayah, number), text: QuranText("w\(number)"), sharesToken: false)
        return BridgeWord(word: text, meaning: WordMeaning(english: "", bengali: "", transliteration: ""), start: start, end: end)
    }

    /// Two ayahs; the reciter repeats 1:2 after 1:3, and pauses between words.
    private var sura: BridgeSura {
        let url = URL(fileURLWithPath: "/tmp/112.mp3")
        let first = BridgeAyah(ayah: AyahNumber(quran: quran, sura: 112, ayah: 1)!, start: 0, end: 3, words: [
            bridgeWord(1, 1, 0.5, 1.0), bridgeWord(1, 2, 1.2, 1.8), bridgeWord(1, 3, 2.0, 2.5),
        ])
        let second = BridgeAyah(ayah: AyahNumber(quran: quran, sura: 112, ayah: 2)!, start: 3, end: 5, words: [
            bridgeWord(2, 1, 3.1, 4.0),
        ])
        let timings = [
            WordTiming(word: word(1, 1), start: 0.5, end: 1.0),
            WordTiming(word: word(1, 2), start: 1.2, end: 1.8),
            WordTiming(word: word(1, 3), start: 2.0, end: 2.3),
            WordTiming(word: word(1, 2), start: 2.4, end: 2.9),
            WordTiming(word: word(2, 1), start: 3.1, end: 4.0),
        ]
        return BridgeSura(sura: 112, title: "Al-Ikhlas", recording: url, ayahs: [first, second], timings: timings)
    }

    func test_theRecitedWordFollowsTheClockThroughPausesAndRepeats() {
        let sura = sura
        XCTAssertNil(sura.word(at: 0.2), "before the first word")
        XCTAssertEqual(sura.word(at: 0.5), word(1, 1))
        XCTAssertEqual(sura.word(at: 1.1), word(1, 1), "a pause keeps the last word")
        XCTAssertEqual(sura.word(at: 2.1), word(1, 3))
        XCTAssertEqual(sura.word(at: 2.5), word(1, 2), "a repeated word is highlighted again")
        XCTAssertEqual(sura.word(at: 4.9), word(2, 1))
        XCTAssertNil(sura.word(at: 5.0), "after the recitation ends")
    }

    func test_segmentsCoverAWordOrAnAyahOfTheRecording() {
        let sura = sura
        let second = sura.ayahs[0].words[1]
        XCTAssertEqual(sura.segment(second), RecitationSegment(url: sura.recording, start: 1.2, end: 1.8))
        XCTAssertEqual(sura.segment(sura.ayahs[1]), RecitationSegment(url: sura.recording, start: 3, end: 5))
        XCTAssertEqual(sura.words.count, 4)
        XCTAssertEqual(sura.end, 5)
    }
}
