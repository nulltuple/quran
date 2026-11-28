//
//  MistakeDetailViewModel.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import MemorizationService
import Observation
import QuranAnnotations
import QuranKit
import VLogging

/// Drives the H7 Mistake Detail sheet for one ayah:
/// shows mistake history across sessions, confirms model findings, disputes or removes entries,
/// opens the ayah's note editor, and launches Practice on its containing passage.
@MainActor
@Observable
public final class MistakeDetailViewModel {
    // MARK: Lifecycle

    public init(
        verse: AyahNumber,
        service: MemorizationService,
        textLoader: SpotTestTextLoader,
        practicePassage: ((Passage) -> Void)? = nil,
        openNote: (() -> Void)? = nil,
        openInReader: ((AyahNumber) -> Void)? = nil,
        onHistoryChanged: (() -> Void)? = nil
    ) {
        canonicalVerse = AyahNumber(quran: .hafsMadani1405, sura: verse.sura.suraNumber, ayah: verse.ayah) ?? verse
        self.verse = verse
        self.service = service
        self.textLoader = textLoader
        practicePassageHandler = practicePassage
        openNoteHandler = openNote
        openInReaderHandler = openInReader
        onHistoryChangedHandler = onHistoryChanged
    }

    // MARK: Public

    public let verse: AyahNumber
    public let canonicalVerse: AyahNumber
    public private(set) var summary: VerseMistakeSummary?
    public private(set) var wordUnits: [SpotTestWordUnit] = []
    public private(set) var isLoading = false
    public private(set) var loadFailed = false
    public var mutationFailed = false

    public var canPractice: Bool { practicePassageHandler != nil }
    public var canEditNote: Bool { openNoteHandler != nil }
    public var canOpenInReader: Bool { openInReaderHandler != nil }

    /// The Uthmani Arabic text for a canonical word number, or `nil` when `word == 0` or unavailable.
    public func arabicText(forWord word: Int) -> String? {
        guard word > 0 else { return nil }
        return wordUnits.first { $0.wordNumbers.contains(word) }?.text
    }

    /// The highest active heat level for a displayed word unit, or `nil` when cool.
    public func heatLevel(for unit: SpotTestWordUnit) -> MistakeHeatLevel? {
        guard let summary else { return nil }
        return unit.wordNumbers.compactMap { number in
            summary.wordSummaries.first { $0.word.wordNumber == number }?.level
        }.max()
    }

    public func load() async {
        isLoading = true
        loadFailed = false
        let service = service
        let textLoader = textLoader
        let canonical = canonicalVerse
        do {
            async let loadedSummary = service.mistakeSummary(for: canonical)
            async let loadedUnits = textLoader.loadWordUnits(for: [canonical])
            summary = try await loadedSummary
            wordUnits = try await loadedUnits[canonical] ?? []
        } catch {
            logger.error("MistakeDetail: failed to load for \(canonical.nonLocalizedDescription): \(error)")
            loadFailed = true
        }
        isLoading = false
    }

    /// Confirms a model-detected mistake (upgrades provenance from `.model` to `.manual`).
    public func confirm(_ event: MistakeEvent) async {
        mutationFailed = false
        do {
            try await service.confirmMistake(event)
            await load()
            onHistoryChangedHandler?()
        } catch {
            logger.error("MistakeDetail: confirm failed: \(error)")
            mutationFailed = true
        }
    }

    /// Disputes a model-detected mistake or removes a manual mistake via append-only retraction.
    public func retract(_ event: MistakeEvent) async {
        mutationFailed = false
        do {
            try await service.retractMistake(event)
            await load()
            onHistoryChangedHandler?()
        } catch {
            logger.error("MistakeDetail: retract failed: \(error)")
            mutationFailed = true
        }
    }

    public func editNote() {
        openNoteHandler?()
    }

    public func openReader() {
        openInReaderHandler?(verse)
    }

    /// Launches H2 Practice on a full hafiz-sized passage containing this ayah (never isolated words).
    public func practiceRepairPassage() {
        guard let practicePassageHandler else { return }
        if let multiAyahSession = summary?.activeEvents.compactMap(\.sessionPassage).first(where: { $0.first < $0.last }) {
            practicePassageHandler(multiAyahSession)
            return
        }
        let pageVerses = canonicalVerse.page.verses.filter { $0.sura == canonicalVerse.sura }
        if let first = pageVerses.first, let last = pageVerses.last {
            let defaults = PassageSplitter.defaultPassages(covering: first ... last)
            if let match = defaults.first(where: { $0.first <= canonicalVerse && canonicalVerse <= $0.last }) {
                practicePassageHandler(match)
                return
            }
            practicePassageHandler(Passage(first, last))
            return
        }
        practicePassageHandler(Passage(canonicalVerse, canonicalVerse))
    }

    // MARK: Private

    private let service: MemorizationService
    private let textLoader: SpotTestTextLoader
    private let practicePassageHandler: ((Passage) -> Void)?
    private let openNoteHandler: (() -> Void)?
    private let openInReaderHandler: ((AyahNumber) -> Void)?
    private let onHistoryChangedHandler: (() -> Void)?
}
