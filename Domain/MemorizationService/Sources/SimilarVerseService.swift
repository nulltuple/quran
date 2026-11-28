//
//  SimilarVerseService.swift
//

import Foundation
import QuranKit
import QuranText
import VerseTextPersistence

public struct SimilarVerseService {
    public init(uthmaniDatabase: URL) {
        index = GRDBSimilarVersePersistence(fileURL: Bundle.module.url(
            forResource: "quran_similar_verses",
            withExtension: "db"
        )!)
        texts = GRDBQuranVerseTextPersistence(fileURL: uthmaniDatabase)
    }

    public func matches(for verse: AyahNumber) async throws -> [AyahNumber] {
        try await index.matches(for: verse)
    }

    public func compare(_ source: AyahNumber, with match: AyahNumber) async throws -> SimilarVerseComparison {
        // A continuation within a sura is meaningful for this drill. Skip the drill at sura boundaries.
        let sourceNext = AyahNumber(sura: source.sura, ayah: source.ayah + 1)
        let matchNext = AyahNumber(sura: match.sura, ayah: match.ayah + 1)
        let references = [source, match] + [sourceNext, matchNext].compactMap { $0 }
        let textByAyah = try await texts.textForVerses(Array(Set(references)))

        func text(for ayah: AyahNumber) -> SimilarVerseComparison.Verse? {
            textByAyah[ayah].map { SimilarVerseComparison.Verse(id: ayah, text: $0) }
        }

        guard let sourceText = text(for: source), let matchText = text(for: match) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return SimilarVerseComparison(
            source: sourceText,
            match: matchText,
            sourceNext: sourceNext.flatMap(text(for:)),
            matchNext: matchNext.flatMap(text(for:))
        )
    }

    private let index: GRDBSimilarVersePersistence
    private let texts: GRDBQuranVerseTextPersistence
}
