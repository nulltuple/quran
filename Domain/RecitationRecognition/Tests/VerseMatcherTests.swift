//
//  VerseMatcherTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import QuranKit
import QuranResources
import VerseTextPersistence
import XCTest
@testable import RecitationRecognition

/// The matcher over the app's real verse text (`quran.ar.uthmani.v2.db`, table `verses`).
final class VerseMatcherTests: XCTestCase {
    // MARK: Internal

    static func makeMatcher() async throws -> VerseMatcher {
        if let shared = await SharedMatcher.shared.matcher {
            return shared
        }
        let persistence = GRDBQuranVerseTextPersistence(fileURL: QuranResources.quranUthmaniV2Database)
        let verses = try await persistence.searchTextOfAllVerses(quran: .hafsMadani1405)
        let matcher = VerseMatcher(verses: verses)
        await SharedMatcher.shared.set(matcher)
        return matcher
    }

    func testAWholeVerseIsIdentifiedWithConfidence() async throws {
        let result = try await Self.makeMatcher().identify(transcript: "قل هو الله احد")
        XCTAssertEqual(result.candidates.first.map(range), "112:1")
        XCTAssertTrue(result.isConfident)
    }

    func testAMisheardLetterStillIdentifiesTheVerse() async throws {
        let result = try await Self.makeMatcher().identify(transcript: "الحمد لله رب العالمين الرحمن الرحين")
        XCTAssertEqual(result.candidates.first.map(range), "1:2–1:3")
        XCTAssertTrue(result.isConfident)
    }

    func testAFragmentOfALongVerseIsIdentified() async throws {
        let result = try await Self.makeMatcher().identify(transcript: "من ذا الذي يشفع عنده الا باذنه يعلم ما بين ايديهم")
        XCTAssertEqual(result.candidates.first.map(range), "2:255")
        XCTAssertTrue(result.isConfident)
    }

    func testVersesWithIdenticalTextTieInQuranOrder() async throws {
        let result = try await Self.makeMatcher().identify(transcript: "فباي الاء ربكما تكذبان", limit: 3)
        XCTAssertEqual(result.candidates.map(range), ["55:13", "55:16", "55:18"])
        XCTAssertEqual(Set(result.candidates.map(\.score)).count, 1)
        XCTAssertTrue(result.isConfident)
    }

    func testTwoVersesRecitedTogetherMatchTheRun() async throws {
        let result = try await Self.makeMatcher().identify(transcript: "قل هو الله احد الله الصمد")
        XCTAssertEqual(result.candidates.first.map(range), "112:1–112:2")
        XCTAssertTrue(result.isConfident)
    }

    func testASurasFirstVerseIsMatchedWithoutTheBasmala() async throws {
        // 39:1, 45:2 and 46:2 have the same words once the search text's basmala is set aside.
        let result = try await Self.makeMatcher().identify(transcript: "تنزيل الكتاب من الله العزيز الحكيم", limit: 3)
        XCTAssertEqual(result.candidates.map(range), ["39:1", "45:2", "46:2"])
        XCTAssertTrue(result.isConfident)
    }

    func testARecitationThatOpensWithTheBasmalaMatchesTheVerseAfterIt() async throws {
        let matcher = try await Self.makeMatcher()
        let withBasmala = matcher.identify(transcript: "بسم الله الرحمن الرحيم قل هو الله احد")
        XCTAssertEqual(withBasmala.candidates.first.map(range), "112:1")
        XCTAssertTrue(withBasmala.isConfident)
        let basmalaAlone = matcher.identify(transcript: "بسم الله الرحمن الرحيم")
        XCTAssertEqual(basmalaAlone.candidates.first.map(range), "1:1")
        XCTAssertTrue(basmalaAlone.isConfident)
    }

    func testTooFewLettersAreNeverConfident() async throws {
        let matcher = try await Self.makeMatcher()
        XCTAssertFalse(matcher.identify(transcript: "الم").isConfident)
        XCTAssertFalse(matcher.identify(transcript: "لا.").isConfident)
        XCTAssertTrue(matcher.identify(transcript: "").candidates.isEmpty)
    }

    func testUnrelatedSpeechIsNotConfident() async throws {
        let result = try await Self.makeMatcher().identify(transcript: "مرحبا كيف حالك اليوم يا صديقي العزيز")
        XCTAssertFalse(result.isConfident)
    }

    // MARK: Private

    private actor SharedMatcher {
        static let shared = SharedMatcher()
        var matcher: VerseMatcher?
        func set(_ matcher: VerseMatcher) {
            self.matcher = matcher
        }
    }

    private func range(_ candidate: VerseCandidate) -> String {
        let first = "\(candidate.firstVerse.sura.suraNumber):\(candidate.firstVerse.ayah)"
        guard candidate.lastVerse != candidate.firstVerse else { return first }
        return first + "–\(candidate.lastVerse.sura.suraNumber):\(candidate.lastVerse.ayah)"
    }
}
