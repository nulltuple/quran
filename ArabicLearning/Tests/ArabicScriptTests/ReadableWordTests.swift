import ArabicScript
import XCTest

/// Words are copied from QuranResources' `quran.ar.uthmani.v2.db` (sura:ayah in each comment).
final class ReadableWordTests: XCTestCase {
    func test_shortVowelWordsNeedOnlyShortVowels() throws {
        let word = try XCTUnwrap(ReadableWord("خَلَقَ")) // 113:2
        XCTAssertEqual(word.allFeatures, [.shortVowel])
        XCTAssertEqual(word.onset?.letter, .kha)
        XCTAssertEqual(word.onset?.vowel, .fatha)
    }

    func test_longVowelsAfterTheirMatchingVowelAndTheDaggerAlif() throws {
        // 1:3 ٱلرَّحۡمَٰنِ: alif wasla, sun lam, ra with shadda, sukun, mim with a dagger alif.
        let rahman = try XCTUnwrap(ReadableWord("ٱلرَّحۡمَٰنِ"))
        XCTAssertEqual(rahman.features, [[.hamzatWasl], [.sunLam], [.shadda, .shortVowel], [.sukun], [.shortVowel, .longVowel], [.shortVowel]])
        // 114:1 ٱلنَّاسِ: alif after fatha is long.
        XCTAssertEqual(try XCTUnwrap(ReadableWord("ٱلنَّاسِ")).features[3], [.longVowel])
        // 112:1 قُلۡ: a short vowel, then sukun.
        XCTAssertEqual(try XCTUnwrap(ReadableWord("قُلۡ")).allFeatures, [.shortVowel, .sukun])
        // 1:7 ٱلضَّالِّينَ: alif with maddah after fatha, ya after kasra.
        // Written with explicit scalars: an editor may compose alif + maddah into U+0622, which the
        // canonical text never uses.
        let dallin = try XCTUnwrap(ReadableWord("ٱلضَّ\u{0627}\u{0653}لِّينَ"))
        XCTAssertEqual(dallin.features[3], [.longVowel])
        XCTAssertEqual(dallin.features[5], [.longVowel])
    }

    func test_moonLamCarriesSukunAndIsNotSilent() throws {
        let hamd = try XCTUnwrap(ReadableWord("ٱلۡحَمۡدُ")) // 1:2
        XCTAssertEqual(hamd.features[1], [.sukun])
        XCTAssertFalse(hamd.allFeatures.contains(.sunLam))
    }

    /// Regression (seen in the simulator, 2026-11-26): U+0652 is the KFGQPC "never read" circle,
    /// not a sukun, so `وَعَمِلُواْ` was offered as a sukun word with its silent alif as the answer.
    func test_theRoundedZeroMarksASilentLetterNotASukun() throws {
        XCTAssertEqual(ArabicMark.sukun.kind, .recitation)
        let amilu = try XCTUnwrap(ReadableWord("وَعَمِلُوا\u{0652}")) // 103:3
        XCTAssertEqual(amilu.features.last, [.silentLetter])
        XCTAssertFalse(amilu.allFeatures.contains(.sukun))
        XCTAssertEqual(amilu.graphemes.count, 6)
        XCTAssertTrue(amilu.isSilent(at: 5))
        XCTAssertEqual(amilu.features[4], [.longVowel], "the waw after damma is a long vowel, read")
        XCTAssertFalse(amilu.isSilent(at: 4))
    }

    func test_alifWaslaIsSilentOnlyAfterAPrefix() throws {
        let nas = try XCTUnwrap(ReadableWord("ٱلنَّاسِ")) // 114:1, read alone: an-nās
        XCTAssertFalse(nas.isSilent(at: 0))
        XCTAssertTrue(nas.isSilent(at: 1), "sun lam")
        let wal = try XCTUnwrap(ReadableWord("وَٱلۡعَصۡرِ")) // 103:1
        XCTAssertTrue(wal.isSilent(at: 1))
        XCTAssertFalse(wal.isSilent(at: 2), "moon lam is read")
    }

    func test_staggeredTanwinAndTheAlifAfterFathatan() throws {
        // 94:6 يُسۡرٗا: staggered fathatan (U+0657) and the unread alif after it.
        let yusra = try XCTUnwrap(ReadableWord("يُسۡرٗا"))
        XCTAssertEqual(yusra.features[2], [.tanwin])
        XCTAssertEqual(yusra.features[3], [.tanwinAlif])
        // 93:4 خَيۡرٞ (staggered dammatan, U+065E) and 95:4 تَقۡوِيمٖ (staggered kasratan, U+0656).
        XCTAssertTrue(try XCTUnwrap(ReadableWord("خَيۡرٞ")).allFeatures.contains(.tanwin))
        XCTAssertTrue(try XCTUnwrap(ReadableWord("تَقۡوِيمٖ")).allFeatures.contains(.tanwin))
        XCTAssertEqual(ArabicMark.invertedDamma.kind, .tanwin)
    }

    func test_hamzaSeatsAndTaMarbuta() throws {
        // 97:4 أَمۡرٖ and 98:3 قَيِّمَةٞ.
        XCTAssertEqual(try XCTUnwrap(ReadableWord("أَمۡرٖ")).features[0], [.hamzaSeat, .shortVowel])
        XCTAssertEqual(try XCTUnwrap(ReadableWord("قَيِّمَةٞ")).features.last, [.taMarbuta, .tanwin])
    }

    func test_wordsWithMarksTheLiteracyUnitsDoNotTeachAreNotReadable() {
        XCTAssertNil(ReadableWord("مِنۢ"), "98:4: the iqlab meem is tajweed (T1)")
        XCTAssertNil(ReadableWord("لَهُۥ"), "112:4: the small waw is not taught yet")
        XCTAssertNil(ReadableWord("خَوۡفِۭ"), "106:4: the small low meem")
        XCTAssertNil(ReadableWord(""))
    }

    func test_wordsStartingWithoutAPlainVowelledLetterHaveNoOnset() throws {
        XCTAssertNil(try XCTUnwrap(ReadableWord("ٱلنَّاسِ")).onset)
        XCTAssertNil(try XCTUnwrap(ReadableWord("أَمۡرٖ")).onset)
    }
}
