//
//  SpotTestTextLoader.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import MemorizationService
import QuranGeometry
import QuranKit
import ReadingService
import VerseTextPersistence
import WordFramePersistence
import WordTextService

/// One displayed Arabic word unit inside a spot-test verse, mapped to canonical QUL word numbers.
public struct SpotTestWordUnit: Hashable, Identifiable, Sendable {
    public init(text: String, wordNumbers: [Int]) {
        self.text = text
        self.wordNumbers = wordNumbers
    }

    public let text: String
    /// Canonical QUL word numbers (1-based) represented by this written token unit.
    public let wordNumbers: [Int]

    public var id: Int { wordNumbers.first ?? 0 }
}

/// Loads Uthmani word units and Mushaf line spans off the main actor for H4 spot tests.
public struct SpotTestTextLoader: Sendable {
    // MARK: Lifecycle

    public init(
        uthmaniDatabase: URL,
        wordByWordDatabase: URL,
        ayahInfoDatabase: URL? = Reading.hafs_1405.bundleURL.map { Reading.hafs_1405.ayahInfoDatabase(in: $0) }
    ) {
        self.uthmaniDatabase = uthmaniDatabase
        self.wordByWordDatabase = wordByWordDatabase
        self.ayahInfoDatabase = ayahInfoDatabase
    }

    // MARK: Public

    /// Loads canonical word units for `verses` in Quran order.
    public func loadWordUnits(for verses: [AyahNumber]) async throws -> [AyahNumber: [SpotTestWordUnit]] {
        let sorted = Array(Set(verses)).sorted()
        guard !sorted.isEmpty else { return [:] }
        let textPersistence = GRDBQuranVerseTextPersistence(mode: .arabic, fileURL: uthmaniDatabase)
        let wordByWord = WordByWordService(fileURL: wordByWordDatabase)

        async let fetchedTexts = textPersistence.textForVerses(sorted)
        async let fetchedLayouts = wordByWord.textLayouts(for: sorted)
        let (texts, layouts) = try await (fetchedTexts, fetchedLayouts)

        var result: [AyahNumber: [SpotTestWordUnit]] = [:]
        result.reserveCapacity(sorted.count)
        for verse in sorted {
            guard let rawText = texts[verse]?.text else { continue }
            let tokens = rawText.split(whereSeparator: \.isWhitespace).map(String.init)
            if let units = layouts[verse]?.units(tokenCount: tokens.count) {
                result[verse] = units.map { unit in
                    let text = tokens[(unit.tokens.lowerBound - 1) ... (unit.tokens.upperBound - 1)].joined(separator: " ")
                    return SpotTestWordUnit(text: text, wordNumbers: Array(unit.words))
                }
            } else {
                result[verse] = tokens.enumerated().map { idx, token in
                    SpotTestWordUnit(text: token, wordNumbers: [idx + 1])
                }
            }
        }
        return result
    }

    /// Loads exact Hafs 1405 Mushaf line spans for the pages covered by `pool`.
    /// Returns empty when no bundled `ayahinfo` database is available (caller falls back cleanly).
    public func loadLineSpans(for pool: AyahRangeSet) async -> [AyahNumber: VerseLineSpan] {
        guard !pool.isEmpty,
              let ayahInfoDatabase,
              FileManager.default.fileExists(atPath: ayahInfoDatabase.path)
        else {
            return [:]
        }
        let pages = Set(pool.ranges.flatMap { range -> [Page] in
            let firstPage = range.lowerBound.page.pageNumber
            let lastPage = range.upperBound.page.pageNumber
            guard firstPage <= lastPage else { return [] }
            return (firstPage ... lastPage).compactMap { Page(quran: range.lowerBound.quran, pageNumber: $0) }
        })
        let persistence = GRDBWordFramePersistence(fileURL: ayahInfoDatabase)
        var minLineByVerse: [AyahNumber: (page: Int, minLine: Int, maxLine: Int)] = [:]
        for page in pages.sorted() {
            guard let frames = try? await persistence.wordFrameCollectionForPage(page) else { continue }
            for frame in frames {
                let verse = frame.word.verse
                if let existing = minLineByVerse[verse] {
                    if existing.page == page.pageNumber {
                        minLineByVerse[verse] = (
                            page: existing.page,
                            minLine: min(existing.minLine, frame.line),
                            maxLine: max(existing.maxLine, frame.line)
                        )
                    }
                } else {
                    minLineByVerse[verse] = (page: page.pageNumber, minLine: frame.line, maxLine: frame.line)
                }
            }
        }
        return minLineByVerse.mapValues { VerseLineSpan(page: $0.page, firstLine: $0.minLine, lastLine: $0.maxLine) }
    }

    // MARK: Private

    private let uthmaniDatabase: URL
    private let wordByWordDatabase: URL
    private let ayahInfoDatabase: URL?
}
