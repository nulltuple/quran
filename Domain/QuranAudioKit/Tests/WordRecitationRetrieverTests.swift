//
//  WordRecitationRetrieverTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import QuranAudio
import QuranKit
import ReciterServiceFake
import SystemDependencies
import Utilities
import XCTest
@testable import QuranAudioKit

/// The real QUL word timings in `qul_afasy.db` (TestResources): 1:2 word 1 is 5.684–7.230 s; 2:14
/// recites words 7–11 twice; 2:27 word 18 has no timing of its own.
final class WordRecitationRetrieverTests: XCTestCase {
    // MARK: Internal

    override func tearDown() async throws {
        Reciter.cleanUpAudio()
    }

    func test_aWordIsItsTimingInTheStreamedSuraWhenNotDownloaded() async throws {
        let recitation = try await retriever.recitation(of: word(1, 2, 1))

        XCTAssertEqual(recitation, WordRecitation(
            word: word(1, 2, 1),
            reciter: reciter,
            url: reciter.remoteURL(sura: quran.suras[0]),
            start: 5.684,
            end: 7.230
        ))
        XCTAssertEqual(recitation?.isDownloaded, false)
    }

    func test_aDownloadedSuraPlaysFromItsFile() async throws {
        let file = reciter.localURL(sura: quran.suras[0])
        try DefaultFileSystem().createDirectory(at: reciter.localFolder(), withIntermediateDirectories: true)
        try Data([0]).write(to: file.url)

        let recitation = try await retriever.recitation(of: word(1, 2, 4))

        XCTAssertEqual(recitation?.url, file.url)
        XCTAssertEqual(recitation?.isDownloaded, true)
        XCTAssertEqual(recitation?.start, 8.8)
        XCTAssertEqual(recitation?.end, 11.259)
    }

    func test_aRepeatedWordIsItsFirstRecitation() async throws {
        let recitation = try await retriever.recitation(of: word(2, 14, 7))

        XCTAssertEqual(recitation?.start, 170.92)
        XCTAssertEqual(recitation?.end, 171.51)
    }

    func test_aWordWithoutItsOwnTimingHasNoRecitation() async throws {
        let recitation = try await retriever.recitation(of: word(2, 27, 18))

        XCTAssertNil(recitation)
    }

    func test_noReciterWithWordTimingsHasNoRecitation() async throws {
        let recitation = try await WordRecitationRetriever(reciter: nil).recitation(of: word(1, 2, 1))

        XCTAssertNil(recitation)
    }

    func test_theWordTimingReciterIsTheOneWithABundledTimingDatabase() {
        let reciters = [Reciter.gappedReciter, .gaplessReciter, .wordTimingReciter]

        XCTAssertEqual(WordRecitationRetriever.wordTimingReciter(in: reciters), .wordTimingReciter)
        XCTAssertNil(WordRecitationRetriever.wordTimingReciter(in: [.gappedReciter, .gaplessReciter]))
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405
    private let reciter = Reciter.wordTimingReciter
    private lazy var retriever = WordRecitationRetriever(reciter: reciter)

    private func word(_ sura: Int, _ ayah: Int, _ number: Int) -> Word {
        Word(verse: AyahNumber(quran: quran, sura: sura, ayah: ayah)!, wordNumber: number)
    }
}
