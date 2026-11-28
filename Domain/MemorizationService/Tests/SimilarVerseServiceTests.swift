//
//  SimilarVerseServiceTests.swift
//

import QuranKit
import QuranResources
import QuranText
import XCTest
@testable import MemorizationService

final class SimilarVerseServiceTests: XCTestCase {
    func testFindsReciprocalCorroboratedMatchesWithoutIndexOnlyOrQULOnlyPairs() async throws {
        let service = SimilarVerseService(uthmaniDatabase: QuranResources.quranUthmaniV2Database)
        let fromBasmala = try await service.matches(for: ayah(1, 1))
        let fromLetter = try await service.matches(for: ayah(27, 30))
        let fromGuidance = try await service.matches(for: ayah(1, 6))
        let fromBook = try await service.matches(for: ayah(2, 2))

        XCTAssertTrue(fromBasmala.contains(ayah(27, 30)))
        XCTAssertTrue(fromLetter.contains(ayah(1, 1)))
        XCTAssertFalse(fromGuidance.contains(ayah(10, 25)))
        XCTAssertFalse(fromBook.contains(ayah(10, 37)))
        XCTAssertEqual(Set(fromBasmala).count, fromBasmala.count)
    }

    func testIdenticalAyahsCanHaveDifferentContinuations() async throws {
        let service = SimilarVerseService(uthmaniDatabase: QuranResources.quranUthmaniV2Database)
        let comparison = try await service.compare(ayah(109, 3), with: ayah(109, 5))

        XCTAssertTrue(comparison.sourceDifferences.isEmpty)
        XCTAssertTrue(comparison.matchDifferences.isEmpty)
        XCTAssertEqual(comparison.continuation?.expected.id, ayah(109, 4))
        XCTAssertEqual(comparison.continuation?.alternative.id, ayah(109, 6))
        XCTAssertNil(comparison.ending)
    }

    func testMarksOnlyInsertedAndRemovedWordsAndHidesEnding() {
        let source = SimilarVerseComparison.Verse(id: ayah(1, 1), text: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ")
        let match = SimilarVerseComparison.Verse(id: ayah(1, 2), text: "بِسْمِ اللَّهِ الْعَظِيمِ")
        let comparison = SimilarVerseComparison(source: source, match: match, sourceNext: nil, matchNext: nil)

        XCTAssertEqual(comparison.sourceDifferences.map { String(source.text.text[$0]) }, ["الرَّحْمَٰنِ", "الرَّحِيمِ"])
        XCTAssertEqual(comparison.matchDifferences.map { String(match.text.text[$0]) }, ["الْعَظِيمِ"])
        XCTAssertEqual(comparison.ending?.prompt.text, "بِسْمِ اللَّهِ")
        XCTAssertEqual(comparison.ending?.answer.text, "الرَّحْمَٰنِ الرَّحِيمِ")
    }

    func testContinuationsNeverCrossSurahs() async throws {
        let service = SimilarVerseService(uthmaniDatabase: QuranResources.quranUthmaniV2Database)
        let comparison = try await service.compare(ayah(1, 7), with: ayah(1, 6))
        XCTAssertNil(comparison.continuation)
    }

    private func ayah(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: sura, ayah: ayah)!
    }
}
