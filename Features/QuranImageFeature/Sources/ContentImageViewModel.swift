//
//  ContentImageViewModel.swift
//
//
//  Created by Mohamed Afifi on 2024-02-10.
//

import AnnotationsService
import Combine
import Crashing
import ImageService
import NoorUI
import QuranAnnotations
import QuranGeometry
import QuranKit
import QuranText
import ReadingService
import SwiftUI
import VLogging
import WordTextService

@MainActor
class ContentImageViewModel: ObservableObject {
    // MARK: Lifecycle

    init(
        reading: Reading,
        page: Page,
        imageDataService: ImageDataService,
        overlayService: VerseOverlayService,
        wordByWordService: WordByWordService
    ) {
        self.page = page
        self.reading = reading
        self.imageDataService = imageDataService
        self.overlayService = overlayService
        self.wordByWordService = wordByWordService
        // The preference publishes changes only, so start from its current value.
        wordByWordLanguage = WordByWordPreferences.shared.language
        overlays = overlayService.overlays.restricted(to: page)
        undimmedVerses = overlayService.overlays.undimmedVerses(on: page)

        overlayService.$overlays
            .map { $0.restricted(to: page) }
            .removeDuplicates()
            .sink { [weak self] in self?.overlays = $0 }
            .store(in: &cancellables)

        overlayService.$overlays
            .map { $0.undimmedVerses(on: page) }
            .removeDuplicates()
            .sink { [weak self] in self?.undimmedVerses = $0 }
            .store(in: &cancellables)

        // A new playing ayah follows the recited word again after the reader scrolled away.
        overlayService.$overlays
            .map(\.playingVerses)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // Publishing an unchanged value would still redraw every page while audio plays.
                if self?.followsRecitedWord == false {
                    self?.followsRecitedWord = true
                }
            }
            .store(in: &cancellables)

        WordByWordPreferences.shared.$language
            .removeDuplicates()
            .sink { [weak self] in self?.wordByWordLanguage = $0 }
            .store(in: &cancellables)

        overlayService.scrollRequests
            .sink { [weak self] in
                self?.scrollToVerseIfNeeded()
            }
            .store(in: &cancellables)
    }

    // MARK: Internal

    let page: Page
    @Published var imagePage: ImagePage?
    @Published var scrollToVerse: AyahNumber?
    @Published var scale: WordFrameScale = .zero
    @Published var imageFrame: CGRect = .zero

    @Published private var suraHeaderLocations: [SuraHeaderLocation] = []
    @Published private var ayahNumberLocations: [AyahNumberLocation] = []
    @Published private var overlays: VerseOverlays
    @Published private var undimmedVerses: Set<AyahNumber>?
    /// The page-image word of each text word on the page; empty for readings without a mapping.
    @Published private var imageWords: [Word: Word] = [:]
    @Published private var meanings: [Word: String] = [:]
    @Published private var followsRecitedWord = true
    private var wordByWordLanguage: WordByWordLanguage = .off {
        didSet {
            if wordByWordLanguage != oldValue {
                Task { await loadMeanings() }
            }
        }
    }

    /// The recited word on the page image, when the page image has a mapping for it.
    private var recitedImageWord: Word? {
        overlays.recitedWord.flatMap { imageWords[$0] }
    }

    /// The recited word content keeps in view, until the reader scrolls away from it.
    var recitedScrollWord: Word? {
        followsRecitedWord ? recitedImageWord : nil
    }

    var decorations: ImageDecorations {
        return ImageDecorations(
            suraHeaders: suraHeaderLocations,
            ayahNumbers: ayahNumberLocations,
            drawsAyahNumbersAndSuraHeaders: reading.drawsAyahNumbersAndSuraHeaders,
            chromeStyle: QuranPageChromeStyle(reading: reading),
            wordFrames: imagePage?.wordFrames ?? WordFrameCollection(frames: []),
            textColumn: imagePage?.textColumn,
            verseHighlights: overlays.versesByHighlights().mapValues { Color($0) },
            wordHighlight: overlays.pointedWord ?? recitedImageWord,
            undimmedVerses: undimmedVerses,
            // The word pointer shows its own popover, so captions follow the recited word only.
            wordCaption: overlays.pointedWord == nil ? overlays.recitedWord.flatMap { meanings[$0] } : nil,
            scrollWord: recitedScrollWord
        )
    }

    #if QURAN_SYNC
    var ayahReadingBookmarks: [AyahNumber: [ReadingBookmarkSlot]] {
        overlays.readingBookmarkSlotsByVerse
    }

    var pageReadingBookmarks: [ReadingBookmarkSlot] {
        overlays.pageReadingBookmarkSlots(on: page)
    }
    #endif

    func loadImagePage() async {
        guard ReadingPreferences.shared.reading == reading else {
            return
        }

        do {
            let imagePage = try await imageDataService.imageForPage(page)
            try Task.checkCancellation()
            guard ReadingPreferences.shared.reading == reading else {
                return
            }
            self.imagePage = imagePage
            imageWords = await loadImageWords()
            await loadMeanings()

            ayahNumberLocations = try await imageDataService.ayahNumbers(page)
            if reading.drawsAyahNumbersAndSuraHeaders {
                suraHeaderLocations = try await imageDataService.suraHeaders(page)
            }

            scrollToVerseIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            guard ReadingPreferences.shared.reading == reading else {
                return
            }
            // TODO: should show error to the user
            crasher.recordError(error, reason: "Failed to retrieve quran image details")
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
        if scrollToVerse != nil {
            scrollToVerse = nil
        }
        if followsRecitedWord {
            followsRecitedWord = false
        }
    }

    func wordAtGlobalPoint(_ point: CGPoint) -> Word? {
        let localPoint = CGPoint(
            x: point.x - imageFrame.minX,
            y: point.y - imageFrame.minY
        )
        return imagePage?.wordFrames.wordAtLocation(localPoint, imageScale: scale)
    }

    // MARK: Private

    private let imageDataService: ImageDataService
    private let wordByWordService: WordByWordService
    private let overlayService: VerseOverlayService
    private let reading: Reading
    private var cancellables: Set<AnyCancellable> = []
    private var isVisible = false

    private func loadImageWords() async -> [Word: Word] {
        do {
            return try await wordByWordService.imageWords(for: page.verses, reading: reading)
        } catch {
            // Without the mapping the page highlights whole ayahs, as before word timings.
            logger.error("Quran Image: failed to load word positions for page \(page.pageNumber). Error: \(error)")
            return [:]
        }
    }

    private func loadMeanings() async {
        let language = wordByWordLanguage
        do {
            let meanings = try await wordByWordService.meanings(for: page.verses, language: language)
            guard language == wordByWordLanguage else {
                return
            }
            self.meanings = meanings
        } catch {
            logger.error("Quran Image: failed to load word meanings for page \(page.pageNumber). Error: \(error)")
            meanings = [:]
        }
    }

    private func scrollToVerseIfNeededSynchronously() {
        // Wait until the view is on screen and `loadImagePage()` has the page.
        guard isVisible, imagePage != nil, let ayah = overlayService.overlays.firstScrollingVerse() else {
            return
        }
        logger.info("Quran Image: scrollToVerseIfNeeded \(ayah.nonLocalizedDescription)")
        scrollToVerse = ayah
        if ayah.page == page {
            // Scroll to the navigation target once; later requests keep the reader's position.
            overlayService.consumeNavigationTarget(ayah)
        }
    }

    private func scrollToVerseIfNeeded() {
        // Execute in the next runloop to allow the overlayService value to load.
        DispatchQueue.main.async {
            self.scrollToVerseIfNeededSynchronously()
        }
    }
}
