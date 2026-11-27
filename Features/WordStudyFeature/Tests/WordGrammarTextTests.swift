//
//  WordGrammarTextTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import GRDB
import Localization
import QuranText
import TestResources
import XCTest
@testable import WordStudyFeature

final class WordGrammarTextTests: XCTestCase {
    func test_nounInPlainWords() {
        let grammar = WordGrammar(part: .noun, tag: "N", role: .stem, gender: .masculine, grammaticalCase: .nominative)

        XCTAssertEqual(WordGrammarText.description(grammar), "Noun · masculine · nominative")
    }

    func test_verbInPlainWords() {
        let grammar = WordGrammar(
            part: .verb, tag: "V", role: .stem, person: 3, gender: .masculine, number: .plural,
            verbForm: 4, aspect: .imperfect, voice: .passive, mood: .jussive
        )

        XCTAssertEqual(
            WordGrammarText.description(grammar),
            "Verb · form IV · imperfect (ongoing action) · passive · 3rd person masculine plural · jussive"
        )
    }

    func test_derivedNounNamesItsDerivation() {
        let grammar = WordGrammar(
            part: .noun, tag: "ADJ", derivation: "ACT_PCPL", role: .stem, gender: .masculine, number: .singular,
            grammaticalCase: .genitive, isIndefinite: true
        )

        XCTAssertEqual(
            WordGrammarText.description(grammar),
            "Adjective (active participle) · masculine singular · genitive · indefinite"
        )
    }

    func test_particleOfAFamily() {
        let grammar = WordGrammar(part: .particle, tag: "ACC", role: .stem, family: .inna)

        XCTAssertEqual(WordGrammarText.description(grammar), "Accusative particle · inna and its sisters")
    }

    func test_everyGrammarInTheCorpusHasATerm() throws {
        // Every part of speech, derivation, aspect, mood, case and family the bundled database uses
        // has an English term; a missing one would show its key.
        let queue = try DatabaseQueue(path: TestResources.resourceURL("quran_morphology.db").path)
        let keys = try queue.read { db in
            try Set(String.fetchAll(db, sql: """
            SELECT 'grammar.tag.' || part || '.' || tag FROM grammar
            UNION SELECT 'grammar.derivation.' || derivation FROM grammar WHERE derivation IS NOT NULL
            UNION SELECT 'grammar.aspect.' || aspect FROM grammar WHERE aspect IS NOT NULL
            UNION SELECT 'grammar.mood.' || mood FROM grammar WHERE mood IS NOT NULL
            UNION SELECT 'grammar.case.' || grammatical_case FROM grammar WHERE grammatical_case IS NOT NULL
            UNION SELECT 'grammar.family.' || family FROM grammar WHERE family IS NOT NULL
            UNION SELECT 'grammar.person.' || person FROM grammar WHERE person IS NOT NULL
            UNION SELECT 'grammar.gender.' || gender FROM grammar WHERE gender IS NOT NULL
            UNION SELECT 'grammar.number.' || number FROM grammar WHERE number IS NOT NULL
            """))
        }

        XCTAssertGreaterThan(keys.count, 60)
        let missing = keys.filter { l($0, table: .grammar, language: .english) == $0 }
        XCTAssertEqual(missing.sorted(), [])
    }
}
