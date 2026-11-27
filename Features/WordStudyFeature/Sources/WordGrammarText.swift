//
//  WordGrammarText.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import Localization
import QuranText

/// A segment's grammar in plain words, such as "Verb · form IV · imperfect (ongoing action) ·
/// 3rd person masculine plural · indicative". Terms come from the `Grammar` strings table, which is
/// English only for now: other languages fall back to English (`l(_:table:)`).
enum WordGrammarText {
    // MARK: Internal

    /// The part of speech: "Noun", "Proper noun", "Preposition", ...; with the derivation for
    /// participles and verbal nouns: "Adjective (active participle)".
    static func partOfSpeech(_ grammar: WordGrammar) -> String {
        let name = term(tagKey(grammar))
        guard let derivation = grammar.derivation else {
            return name
        }
        return lFormat("grammar.with_derivation", table: .grammar, name, term("grammar.derivation.\(derivation)"))
    }

    /// The part of speech followed by every feature the corpus gives.
    static func description(_ grammar: WordGrammar) -> String {
        var parts = [partOfSpeech(grammar)]
        if let form = grammar.verbForm, (1 ... romanNumerals.count).contains(form) {
            parts.append(lFormat("grammar.verb_form", table: .grammar, romanNumerals[form - 1]))
        }
        if let aspect = grammar.aspect {
            parts.append(term("grammar.aspect.\(aspect.rawValue)"))
        }
        if grammar.voice == .passive {
            parts.append(term("grammar.voice.passive"))
        }
        if let personGenderNumber = personGenderNumber(grammar) {
            parts.append(personGenderNumber)
        }
        if let mood = grammar.mood {
            parts.append(term("grammar.mood.\(mood.rawValue)"))
        }
        if let grammaticalCase = grammar.grammaticalCase {
            parts.append(term("grammar.case.\(grammaticalCase.rawValue)"))
        }
        if grammar.isIndefinite {
            parts.append(term("grammar.indefinite"))
        }
        if let family = grammar.family {
            parts.append(term("grammar.family.\(family.rawValue)"))
        }
        return parts.joined(separator: term("grammar.separator"))
    }

    /// The `Grammar` table key of the segment's part of speech.
    static func tagKey(_ grammar: WordGrammar) -> String {
        "grammar.tag.\(grammar.part.rawValue).\(grammar.tag)"
    }

    // MARK: Private

    private static let romanNumerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]

    private static func term(_ key: String) -> String {
        l(key, table: .grammar)
    }

    /// "3rd person masculine plural", "masculine singular", "dual", ...; `nil` when none is given.
    private static func personGenderNumber(_ grammar: WordGrammar) -> String? {
        let parts = [
            grammar.person.map { term("grammar.person.\($0)") },
            grammar.gender.map { term("grammar.gender.\($0.rawValue)") },
            grammar.number.map { term("grammar.number.\($0.rawValue)") },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
