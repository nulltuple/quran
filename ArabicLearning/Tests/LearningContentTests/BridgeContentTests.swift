import LearningContent
import LearningModel
import QuranKit
import XCTest

/// L5 content: bridge suras with recitation timings, word meanings, lemmas and morphology.
final class BridgeContentTests: XCTestCase {
    private let store = LearningContentStore()

    func test_bridgeSurasHaveRecordingsAndEveryWordIsTimedInsideItsAyah() async throws {
        let suras = try await store.bridgeSuras()
        XCTAssertEqual(suras.map(\.sura), [1, 112, 113, 114, 108, 103, 110, 111])
        XCTAssertEqual(suras.first?.title, "Al-Fatihah")
        for sura in suras {
            XCTAssertTrue(FileManager.default.fileExists(atPath: sura.recording.path), "\(sura.sura)")
            let canonical = try await store.quranWords(sura: sura.sura)
            XCTAssertEqual(sura.words.map(\.word), canonical, "bridge words are the canonical words of \(sura.sura)")
            for ayah in sura.ayahs {
                XCTAssertLessThan(ayah.start, ayah.end)
                for word in ayah.words {
                    XCTAssertTrue(ayah.start <= word.start && word.start < word.end, "\(word.word.word)")
                    XCTAssertFalse(word.meaning.english.isEmpty, "\(word.word.word)")
                    XCTAssertFalse(word.meaning.bengali.isEmpty, "\(word.word.word)")
                    // Halfway through a word's first recitation, that word is the one recited.
                    XCTAssertEqual(sura.word(at: (word.start + word.end) / 2), word.word.word)
                }
            }
        }
        let fatihah = try XCTUnwrap(suras.first)
        XCTAssertEqual(fatihah.ayahs.count, 7)
        XCTAssertEqual(fatihah.words.count, 29)
        XCTAssertEqual(fatihah.end, 46.347, accuracy: 0.001, "the timing database's sura end")
    }

    func test_lemmasAreRankedAndTheVocabularyListIsGlossed() async throws {
        let lemmas = try await store.lemmas()
        XCTAssertEqual(lemmas.first?.text, "و")
        XCTAssertEqual(lemmas.first?.occurrences, 9594)
        XCTAssertEqual(lemmas.map(\.rank), lemmas.map(\.rank).sorted())
        let top = lemmas.filter { $0.rank <= 300 }
        XCTAssertEqual(top.count, 300)
        XCTAssertTrue(top.allSatisfy { !$0.english.isEmpty && !$0.bengali.isEmpty })
        let lord = try XCTUnwrap(lemmas.first { $0.text == "رَبّ" })
        XCTAssertEqual(lord.root, "ربب")
        XCTAssertEqual(lord.english, "Lord")
    }

    func test_wordSegmentsGiveEachPartItsLemmaAndRole() async throws {
        let segments = try await store.wordSegments(sura: 1)
        let verse = try XCTUnwrap(AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 1))
        let bismi = try XCTUnwrap(segments[Word(verse: verse, wordNumber: 1)])
        XCTAssertEqual(bismi.map(\.role), [.prefix, .stem])
        XCTAssertEqual(bismi.map(\.lemma?.text), ["ب", "اسْم"])
        XCTAssertEqual(bismi[1].root, "سمو")
        XCTAssertEqual(bismi[0].partOfSpeech, "preposition")
        XCTAssertEqual(segments.count, 29, "every word of Al-Fatihah")
        // 1:6:1 ٱهۡدِنَا: a verb with a pronoun suffix, which has no lemma.
        let guide = try XCTUnwrap(segments[Word(verse: AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 6)!, wordNumber: 1)])
        XCTAssertEqual(guide.map(\.role), [.stem, .suffix])
        XCTAssertNil(guide[1].lemma)
        XCTAssertTrue(guide[0].partOfSpeech.hasPrefix("verb, command"), guide[0].partOfSpeech)
    }
}
