//
//  ContentTranslationViewModel.swift
//
//
//  Created by Mohamed Afifi on 2023-12-29.
//

import AnnotationsService
import Combine
import Crashing
import Foundation
import NoorUI
import QuranAnnotations
import QuranKit
import QuranText
import QuranTextKit
import ReadingService
import SwiftUI
import TranslationService
import UIx
import VLogging
import WordTextService

struct LoadedTranslationContent {
    var verses: [AyahNumber] = []
    var translations: [Translation] = []
    var verseTexts: [AyahNumber: VerseText] = [:]
}

@MainActor
public final class ContentTranslationViewModel: ObservableObject {
    // MARK: Lifecycle

    public init(
        localTranslationsRetriever: LocalTranslationsRetriever,
        dataService: QuranTextDataService,
        overlayService: VerseOverlayService,
        wordByWordService: WordByWordService
    ) {
        self.dataService = dataService
        self.wordByWordService = wordByWordService
        // The preference publishes changes only, so start from its current value.
        wordByWordLanguage = WordByWordPreferences.shared.language
        showsTransliteration = WordByWordPreferences.shared.showsTransliteration
        self.overlayService = overlayService
        self.localTranslationsRetriever = localTranslationsRetriever
        reading = ReadingPreferences.shared.reading
        arabicFontSize = fontSizePreferences.arabicFontSize
        translationFontSize = fontSizePreferences.translationFontSize
        showArabicText = contentStatePreferences.showArabicInTranslation
        showFootnotes = contentStatePreferences.showFootnotesInTranslation
        selectedTranslations = selectedTranslationsPreferences.selectedTranslationIds
        highlights = [:]

        overlayService.$overlays
            .combineLatest($verses)
            .map { overlays, verses in overlays.undimmedVerses?.intersection(verses) }
            .removeDuplicates()
            .sink { [weak self] in self?.undimmedVerses = $0 }
            .store(in: &cancellables)

        overlayService.$overlays
            .combineLatest($verses)
            .map { overlays, verses in
                let colors = overlays.versesByHighlights()
                return Dictionary(uniqueKeysWithValues: Set(verses).compactMap { verse in
                    colors[verse].map { (verse, Color($0)) }
                })
            }
            .removeDuplicates()
            .sink { [weak self] in self?.highlights = $0 }
            .store(in: &cancellables)

        overlayService.$overlays
            .combineLatest($verses)
            .map { overlays, verses in
                Dictionary(uniqueKeysWithValues: Set(verses).compactMap { verse in
                    let indicators = overlays.indicators(for: verse)
                    return indicators.isEmpty ? nil : (verse, indicators)
                })
            }
            .removeDuplicates()
            .sink { [weak self] in self?.indicatorsByVerse = $0 }
            .store(in: &cancellables)

        overlayService.$overlays
            .combineLatest($verses)
            .map { overlays, verses in overlays.recitedWord.flatMap { verses.contains($0.verse) ? $0 : nil } }
            .removeDuplicates()
            .sink { [weak self] in self?.recitedWord = $0 }
            .store(in: &cancellables)

        overlayService.$overlays
            .combineLatest($verses)
            .map { overlays, verses -> PracticeMask? in
                guard let mask = overlays.practiceMask, let page = verses.first?.page else { return nil }
                return mask.restricted(to: page)
            }
            .removeDuplicates()
            .sink { [weak self] in self?.practiceMask = $0 }
            .store(in: &cancellables)

        overlayService.$overlays
            .combineLatest($verses)
            .map { overlays, verses -> MistakeHeatmapOverlay? in
                guard let heatmap = overlays.activeMistakeHeatmap, let page = verses.first?.page else { return nil }
                let restricted = heatmap.restricted(to: page)
                return restricted.isEmpty ? nil : restricted
            }
            .removeDuplicates()
            .sink { [weak self] in self?.mistakeHeatmap = $0 }
            .store(in: &cancellables)

        WordByWordPreferences.shared.$language
            .removeDuplicates()
            .sink { [weak self] in self?.wordByWordLanguage = $0 }
            .store(in: &cancellables)

        WordByWordPreferences.shared.$showsTransliteration
            .removeDuplicates()
            .sink { [weak self] in self?.showsTransliteration = $0 }
            .store(in: &cancellables)

        overlayService.scrollRequests
            .sink { [weak self] in
                self?.scrollToVerseIfNeeded()
            }
            .store(in: &cancellables)

        fontSizePreferences.$translationFontSize
            .sink { [weak self] in self?.translationFontSize = $0 }
            .store(in: &cancellables)

        fontSizePreferences.$arabicFontSize
            .sink { [weak self] in self?.arabicFontSize = $0 }
            .store(in: &cancellables)

        contentStatePreferences.$showArabicInTranslation
            .sink { [weak self] in self?.showArabicText = $0 }
            .store(in: &cancellables)

        contentStatePreferences.$showFootnotesInTranslation
            .sink { [weak self] in self?.showFootnotes = $0 }
            .store(in: &cancellables)

        // Translation services update the selection from background tasks.
        selectedTranslationsPreferences.$selectedTranslationIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.selectedTranslations = $0 }
            .store(in: &cancellables)

        readingPreferences.$reading
            .assign(to: &$reading)
    }

    // MARK: Public

    @Published public var showHeaderAndFooter = true {
        didSet { recordListUpdate(reason: "header_footer_changed") }
    }

    @Published public var verses: [AyahNumber] = [] {
        willSet {
            if newValue != verses {
                wordsTask = Task { [weak self] in await self?.loadWords(for: newValue) }
            }
        }
        didSet { recordListUpdate(reason: "verses_changed") }
    }

    // MARK: Internal

    let tracker = CollectionTracker<TranslationItemId>()
    @Published private(set) var reading: Reading

    @Published var selectedTranslations: [Translation.ID] {
        didSet {
            crashContext.setQuranMode("translation", selectedTranslationCount: selectedTranslations.count)
            recordListUpdate(reason: "selection_changed")
        }
    }

    @Published private(set) var loadedContent = LoadedTranslationContent() {
        didSet { recordListUpdate(reason: "content_loaded") }
    }

    @Published var expandedTranslations: [AyahNumber: [Translation: [Range<String.Index>]]] = [:] {
        didSet { recordListUpdate(reason: "translation_expanded") }
    }

    @Published var translationFontSize: FontSize
    @Published var arabicFontSize: FontSize

    @Published var showArabicText: Bool {
        didSet { recordListUpdate(reason: "arabic_text_visibility_changed") }
    }

    @Published var showFootnotes: Bool {
        didSet { recordListUpdate(reason: "footnotes_visibility_changed") }
    }

    @Published private var practiceMask: PracticeMask?
    @Published private var mistakeHeatmap: MistakeHeatmapOverlay?
    @Published var highlights: [AyahNumber: Color]
    /// The recited word on this page, numbered as in the ayah's text.
    @Published private(set) var recitedWord: Word?
    @Published private(set) var wordByWordLanguage: WordByWordLanguage = .off {
        didSet {
            if wordByWordLanguage != oldValue {
                wordsTask = Task { [weak self, verses] in await self?.loadWords(for: verses) }
            }
        }
    }

    /// Whether word-by-word words show their transliteration; only when meanings are on.
    @Published private(set) var showsTransliteration = false {
        didSet {
            if showsTransliteration != oldValue {
                wordsTask = Task { [weak self, verses] in await self?.loadWords(for: verses) }
            }
        }
    }

    @Published private(set) var wordMeanings: [Word: String] = [:]
    @Published private(set) var wordTransliterations: [Word: String] = [:]
    @Published private(set) var wordLayouts: [AyahNumber: UthmaniWordLayout] = [:]

    @Published private(set) var undimmedVerses: Set<AyahNumber>?

    @Published private(set) var indicatorsByVerse: [AyahNumber: Set<AyahIndicator>] = [:]

    @Published var footnote: TranslationFootnote?

    @Published var scrollToItem: TranslationItemId?

    var translations: [Translation] {
        loadedContent.translations
    }

    var verseTexts: [AyahNumber: VerseText] {
        loadedContent.verseTexts
    }

    func items(quranFont: QuranFont) -> [TranslationItem] {
        guard let page = verseTexts.first?.key.page else {
            return []
        }
        guard verseTexts.first?.value.translations.count == translations.count else {
            return []
        }

        // Never leave a page with verse numbers only.
        let showsArabicText = showArabicText || translations.isEmpty

        var items: [TranslationItem] = []

        for (verse, verseText) in verseTexts.sorted(by: { $0.key < $1.key }) {
            let decoration = TranslationVerseDecoration(
                color: highlights[verse],
                isDimmed: undimmedVerses?.contains(verse) == false
            )

            let masked = practiceMask?.hides(verse) == true
            // Add sura name, if a new sura
            if verse.sura.firstVerse == verse {
                items.append(
                    .suraName(
                        TranslationSuraName(
                            sura: verse.sura,
                            showsBesmAllah: showsArabicText && !masked,
                            quranFont: quranFont,
                            arabicFontSize: arabicFontSize
                        ),
                        decoration
                    )
                )
            }

            items.append(.verseNumber(verseNumber(verse: verse), decoration))
            if showsArabicText || masked || practiceMask?.checkedVerse == verse {
                items.append(.arabicText(arabicText(verse: verse, verseText: verseText, quranFont: quranFont), decoration))
            }

            for (index, translation) in translations.enumerated() {
                if masked, !(practiceMask?.partialVerse == verse && practiceMask?.showsMeaning == true) { continue }
                let text = verseText.translations[index]

                switch text {
                case .reference(let reference):
                    items.append(
                        .translationReferenceVerse(
                            TranslationReferenceVerse(
                                verse: verse,
                                translation: translation,
                                reference: reference,
                                translationFontSize: translationFontSize
                            ), decoration
                        )
                    )
                case .string(let string):
                    let chunks: [Range<String.Index>]
                    let readMore: Bool
                    if let cutoffChunk = cutoffChunkIfTruncationNeeded(string.text) {
                        if let expandedChunks = expandedChunks(verse: verse, translation: translation) {
                            chunks = expandedChunks
                            readMore = false
                        } else {
                            chunks = [cutoffChunk]
                            readMore = true
                        }
                    } else {
                        chunks = [string.text.startIndex ..< string.text.endIndex]
                        readMore = false
                    }

                    for chunkIndex in 0 ..< chunks.count {
                        items.append(
                            .translationTextChunk(
                                TranslationTextChunk(
                                    verse: verse,
                                    translation: translation,
                                    text: string,
                                    chunks: chunks,
                                    chunkIndex: chunkIndex,
                                    readMore: chunkIndex == chunks.count - 1 ? readMore : false, // Add read more to the last chunk.
                                    translationFontSize: translationFontSize
                                ), decoration
                            )
                        )
                    }

                    if showFootnotes, !readMore {
                        items += footnoteChunks(verse: verse, translation: translation, string: string)
                            .map { .translationFootnoteChunk($0, decoration) }
                    }
                }

                // Show translator if showing more than a single translation.
                if translations.count > 1 {
                    items.append(
                        .translatorText(
                            TranslatorText(
                                verse: verse,
                                translation: translation,
                                translationFontSize: translationFontSize
                            ), decoration
                        )
                    )
                }
            }

            let isLastVerseInTheView = loadedContent.verses.last == verse
            if !isLastVerseInTheView {
                items.append(.verseSeparator(TranslationVerseSeparator(verse: verse), decoration))
            }
        }

        if showHeaderAndFooter {
            items.insert(.pageHeader(TranslationPageHeader(page: page)), at: 0)
            items.append(.pageFooter(TranslationPageFooter(page: page)))
        }

        return items
    }

    func load() async {
        do {
            let requestedVerses = verses
            let requestedTranslationIds = selectedTranslations
            logger.info("Loading translations data; selectedTranslations='\(requestedTranslationIds)'; verses='\(requestedVerses.map(\.nonLocalizedDescription).joined(separator: ", "))'")

            let localTranslations = try await localTranslationsRetriever.getLocalTranslations()
            try Task.checkCancellation()

            let translationsById = Dictionary(uniqueKeysWithValues: localTranslations.map { ($0.id, $0) })
            let requestedTranslations = requestedTranslationIds.compactMap { translationsById[$0] }
            let requestedVerseTexts = try await dataService.textForVerses(
                requestedVerses,
                translations: requestedTranslations
            )
            try Task.checkCancellation()

            guard requestedVerses == verses, requestedTranslationIds == selectedTranslations else {
                logger.info("Discarding stale translations data")
                return
            }

            commitLoadedContent(
                verses: requestedVerses,
                translations: requestedTranslations,
                verseTexts: requestedVerseTexts
            )
        } catch is CancellationError {
            logger.info("Cancelled translations data load")
        } catch {
            // TODO: should show error to the user
            crasher.recordError(error, reason: "Failed to retrieve quran page details")
        }
    }

    /// Scrolls only while the view is on screen, so content being replaced can't use up the navigation target.
    func onAppear() {
        isVisible = true
        scrollToVerseIfNeeded()
    }

    func onDisappear() {
        isVisible = false
    }

    /// The reader scrolled the page themselves; forget the last scroll so it isn't applied again
    /// on appearance or size changes, and so the next request scrolls even to the same verse.
    func onReaderScroll() {
        // Every drag reports; publishing an unchanged nil would still redraw the page.
        if scrollToItem != nil {
            scrollToItem = nil
        }
    }

    func openURL(_ url: TranslationURL) {
        switch url {
        case .footnote(let translationId, let sura, let ayah, let footnoteIndex):
            setFootnoteIfNeeded(translationId: translationId, sura: sura, ayah: ayah, footnoteIndex: footnoteIndex)

        case .readMore(let translationId, let sura, let ayah):
            expandTranslationIfNeeded(translationId: translationId, sura: sura, ayah: ayah)

        case .word(let sura, let ayah, let word):
            guard let verse = verses.first.flatMap({ AyahNumber(quran: $0.quran, sura: sura, ayah: ayah) }) else {
                return
            }
            logger.info("Quran Translation: study word \(verse.nonLocalizedDescription) word \(word)")
            onWordTapped?(Word(verse: verse, wordNumber: word))
        }
    }

    /// Opens word study for a tapped word; `nil` leaves words untappable.
    var onWordTapped: ((Word) -> Void)?

    func ayahAtPoint(_ point: CGPoint) -> AyahNumber? {
        tracker.itemAtPoint(point)?.ayah
    }

    func commitLoadedContent(
        verses: [AyahNumber],
        translations: [Translation],
        verseTexts: [AyahNumber: VerseText]
    ) {
        loadedContent = LoadedTranslationContent(
            verses: verses,
            translations: translations,
            verseTexts: verseTexts
        )
        scrollToVerseIfNeeded()
    }

    // MARK: Private

    private static let maxChunkSize = 800

    private var cancellables: Set<AnyCancellable> = []
    private var listGeneration = 0
    private var isVisible = false
    private var recordedRowCount = 0
    private let overlayService: VerseOverlayService
    private let wordByWordService: WordByWordService
    private var wordsTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    private let dataService: QuranTextDataService
    private let localTranslationsRetriever: LocalTranslationsRetriever
    private let readingPreferences = ReadingPreferences.shared
    private let selectedTranslationsPreferences = SelectedTranslationsPreferences.shared
    private let contentStatePreferences = QuranContentStatePreferences.shared
    private let fontSizePreferences = FontSizePreferences.shared

    private func arabicText(verse: AyahNumber, verseText: VerseText, quranFont: QuranFont) -> TranslationArabicText {
        let arabicVerseNumber = NumberFormatter.arabicNumberFormatter.format(verse.ayah)
        let tokens = verseText.arabicText.text.split(whereSeparator: \.isWhitespace)
        // Recited and word-by-word numbers are canonical words; the verified layout says which text
        // tokens show them. A text that doesn't split as expected (another script) gets neither.
        let units = wordLayouts[verse]?.units(tokenCount: tokens.count)
        if let mask = practiceMask, mask.hides(verse) {
            // Build the displayed string from visible units only, so accessibility and word links
            // cannot disclose the answer. Until a matching layout exists, hide the entire ayah.
            let masked = units?.map { unit in
                unit.words.contains { mask.showsWord(Word(verse: verse, wordNumber: $0)) }
                    ? tokens[unit.tokens.lowerBound - 1 ... unit.tokens.upperBound - 1].joined(separator: " ")
                    : "…"
            }.joined(separator: " ") ?? "…"
            return TranslationArabicText(
                verse: verse,
                text: QuranText(masked),
                quranFont: quranFont,
                arabicFontSize: arabicFontSize,
                offersMeaningCue: mask.partialVerse == verse && !mask.showsMeaning && !translations.isEmpty
            )
        }
        let recitedUnit = recitedWord.flatMap { word in
            word.verse == verse ? units?.first { $0.words.contains(word.wordNumber) } : nil
        }
        var wordHeatLevels: [Int: MistakeHeatLevel] = [:]
        var heatmapTokens: [TranslationWordHeat] = []
        if let units, let mask = practiceMask, !mask.mistakeWords.isEmpty {
            let verseMistakes = mask.mistakeWords.filter { $0.verse == verse }
            if !verseMistakes.isEmpty {
                for (index, unit) in units.enumerated() where unit.words.contains(where: { verseMistakes.contains(Word(verse: verse, wordNumber: $0)) }) {
                    wordHeatLevels[index + 1] = .high
                    heatmapTokens.append(TranslationWordHeat(tokens: unit.tokens, level: .high))
                }
            }
        } else if let units, let heatmap = mistakeHeatmap {
            let verseWordHeat = heatmap.wordLevels(for: verse)
            if !verseWordHeat.isEmpty {
                for (index, unit) in units.enumerated() {
                    let level = unit.words.compactMap { verseWordHeat[Word(verse: verse, wordNumber: $0)] }.max()
                    if let level {
                        wordHeatLevels[index + 1] = level
                        heatmapTokens.append(TranslationWordHeat(tokens: unit.tokens, level: level))
                    }
                }
            }
        }
        return TranslationArabicText(
            verse: verse,
            text: QuranText(verseText.arabicText.text + " " + arabicVerseNumber),
            quranFont: quranFont,
            arabicFontSize: arabicFontSize,
            words: wordByWordLanguage == .off ? nil : units?.map { unit in
                QuranWordMeaning(
                    arabic: tokens[unit.tokens.lowerBound - 1 ... unit.tokens.upperBound - 1].joined(separator: " "),
                    meaning: Self.meaning(of: unit.words, verse: verse, meanings: wordMeanings),
                    transliteration: Self.transliteration(of: unit.words, verse: verse, transliterations: wordTransliterations)
                )
            },
            wordNumbers: onWordTapped == nil || wordByWordLanguage == .off ? nil : units?.map(\.words.lowerBound),
            highlightedWord: recitedUnit.flatMap { units?.firstIndex(of: $0) }.map { $0 + 1 },
            highlightedTokens: recitedUnit?.tokens,
            wordHeatLevels: wordHeatLevels,
            heatmapTokens: heatmapTokens
        )
    }

    /// The meanings of `words`, joined; consecutive words sharing a meaning (`بَعْدَ مَا`) show it once.
    private static func meaning(of words: ClosedRange<Int>, verse: AyahNumber, meanings: [Word: String]) -> String? {
        var parts: [String] = []
        for number in words {
            if let meaning = meanings[Word(verse: verse, wordNumber: number)], meaning != parts.last {
                parts.append(meaning)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The transliterations of `words`, joined; each word sounds separately, so none is dropped.
    private static func transliteration(
        of words: ClosedRange<Int>,
        verse: AyahNumber,
        transliterations: [Word: String]
    ) -> String? {
        let parts = words.compactMap { transliterations[Word(verse: verse, wordNumber: $0)] }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func loadWords(for verses: [AyahNumber]) async {
        let language = wordByWordLanguage
        let loadsTransliterations = language != .off && showsTransliteration
        let wordByWordService = wordByWordService
        do {
            async let layouts = wordByWordService.textLayouts(for: verses)
            async let meanings = wordByWordService.meanings(for: verses, language: language)
            async let transliterations = loadsTransliterations
                ? wordByWordService.transliterations(for: verses)
                : [:]
            let (loadedLayouts, loadedMeanings, loadedTransliterations) = try await (layouts, meanings, transliterations)
            guard !Task.isCancelled else {
                return
            }
            wordLayouts = loadedLayouts
            wordMeanings = loadedMeanings
            wordTransliterations = loadedTransliterations
        } catch {
            // Without word data the page shows whole-ayah text and highlights, as before.
            logger.error("Quran Translation: failed to load words. Error: \(error)")
        }
    }

    private func footnoteChunks(verse: AyahNumber, translation: Translation, string: TranslationString) -> [TranslationFootnoteChunk] {
        zip(string.footnoteRanges, string.footnotes.indices).flatMap { markerRange, footnoteIndex in
            let text = string.footnoteText(at: footnoteIndex)
            let chunks = text.count <= Self.maxChunkSize
                ? [text.startIndex ..< text.endIndex]
                : text.chunkRanges(maxChunkSize: Self.maxChunkSize)
            return chunks.indices.map { chunkIndex in
                TranslationFootnoteChunk(
                    verse: verse,
                    translation: translation,
                    footnoteIndex: footnoteIndex,
                    marker: chunkIndex == 0 ? String(string.text[markerRange]) : nil,
                    text: text,
                    chunks: chunks,
                    chunkIndex: chunkIndex,
                    translationFontSize: translationFontSize
                )
            }
        }
    }

    private func verseNumber(verse: AyahNumber) -> TranslationVerseNumber {
        TranslationVerseNumber(verse: verse, indicators: indicatorsByVerse[verse, default: []])
    }

    private func recordListUpdate(reason: String) {
        let rowsBefore = recordedRowCount
        let rowsAfter = items(quranFont: reading.quranFont).count
        listGeneration += 1
        recordedRowCount = rowsAfter
        crashContext.recordListUpdate(
            owner: "quran_translation",
            reason: reason,
            rowsBefore: rowsBefore,
            rowsAfter: rowsAfter,
            generation: listGeneration
        )
        logger.info(
            "Quran Translation list update: \(reason), rows: \(rowsBefore)->\(rowsAfter), generation: \(listGeneration)"
        )
    }

    private func cutoffChunkIfTruncationNeeded(_ string: String) -> Range<String.Index>? {
        guard let maxUntruncatedIndex = string.index(string.startIndex, offsetBy: Self.maxChunkSize, limitedBy: string.endIndex) else {
            return nil
        }
        let chunkEndIndex = string[..<maxUntruncatedIndex].lastIndex(of: " ") ?? maxUntruncatedIndex
        return string.startIndex ..< chunkEndIndex
    }

    private func expandedChunks(verse: AyahNumber, translation: Translation) -> [Range<String.Index>]? {
        expandedTranslations[verse]?[translation]
    }

    private func expandTranslationIfNeeded(translationId: Translation.ID, sura: Int, ayah: Int) {
        performOnTranslationText(translationId: translationId, sura: sura, ayah: ayah) { ayah, translation, string in
            if let cutoffChunk = cutoffChunkIfTruncationNeeded(string.text) {
                let truncatedChunks = string.text.chunkRanges(range: cutoffChunk.upperBound ..< string.text.endIndex, maxChunkSize: Self.maxChunkSize)
                expandedTranslations[ayah, default: [:]][translation] = [cutoffChunk] + truncatedChunks
            }
        }
    }

    private func setFootnoteIfNeeded(translationId: Translation.ID, sura: Int, ayah: Int, footnoteIndex: Int) {
        performOnTranslationText(translationId: translationId, sura: sura, ayah: ayah) { ayah, translation, string in
            footnote = TranslationFootnote(
                string: string,
                footnoteIndex: footnoteIndex,
                translation: translation,
                translationFontSize: translationFontSize
            )
        }
    }

    private func performOnTranslationText(translationId: Translation.ID, sura: Int, ayah: Int, _ body: (AyahNumber, Translation, TranslationString) -> Void) {
        guard let quran = loadedContent.verses.first?.quran else {
            return
        }
        let ayah = AyahNumber(quran: quran, sura: sura, ayah: ayah)
        let translation = translations.first { $0.id == translationId }
        let translationIndex = translation.flatMap { translations.firstIndex(of: $0) }
        let verseText = ayah.flatMap { ayah in verseTexts[ayah] }
        if let ayah, let translation, let translationIndex, let verseText {
            if case .string(let string) = verseText.translations[translationIndex] {
                body(ayah, translation, string)
            }
        }
    }

    private func scrollToVerseIfNeededSynchronously() {
        guard isVisible,
              let ayah = overlayService.overlays.firstScrollingVerse(),
              let item = items(quranFont: reading.quranFont).first(where: { $0.id.ayah == ayah })
        else {
            return
        }
        logger.info("Quran Translation: scrollToVerseIfNeeded \(ayah.nonLocalizedDescription)")
        scrollToItem = item.id
        // Scroll to the navigation target once; later reloads keep the reader's position.
        overlayService.consumeNavigationTarget(ayah)
    }

    private func scrollToVerseIfNeeded() {
        // Execute in the next runloop to allow the overlayService value to load.
        DispatchQueue.main.async {
            self.scrollToVerseIfNeededSynchronously()
        }
    }
}
