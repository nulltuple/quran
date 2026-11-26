//
//  TafsirViewModel.swift
//

import Combine
import Crashing
import QuranKit
import QuranText
import QuranTextKit
import TranslationService
import VLogging

/// One tafsir's explanation of the current ayah, with the Quran text of every ayah it explains.
struct TafsirPassage: Equatable {
    let tafsir: Translation
    let text: TafsirText
    let arabicText: QuranText
}

@MainActor
final class TafsirViewModel: ObservableObject {
    enum Content: Equatable {
        case loading
        /// No tafsir is downloaded yet.
        case noTafsirs
        case loaded(TafsirPassage)
        case failed
    }

    // MARK: Lifecycle

    init(
        startingVerse: AyahNumber,
        localTranslationsRetriever: LocalTranslationsRetriever,
        dataService: QuranTextDataService,
        preferences: TafsirPreferences = .shared,
        onVerseChange: @escaping (AyahNumber) -> Void
    ) {
        verse = startingVerse
        self.localTranslationsRetriever = localTranslationsRetriever
        self.dataService = dataService
        self.preferences = preferences
        self.onVerseChange = onVerseChange
    }

    // MARK: Internal

    @Published private(set) var verse: AyahNumber
    /// The downloaded tafsirs, in the order the translations list keeps them.
    @Published private(set) var tafsirs: [Translation] = []
    @Published private(set) var selectedTafsir: Translation?
    @Published private(set) var content: Content = .loading

    /// The ayah after the passage shown, so a passage of several ayahs is read once.
    var nextVerse: AyahNumber? {
        passage?.text.lastVerse.next ?? verse.next
    }

    var previousVerse: AyahNumber? {
        passage?.text.firstVerse.previous ?? verse.previous
    }

    /// Reads the downloaded tafsirs again, as after returning from the translations list, and shows the
    /// selected one.
    func reloadTafsirs() async {
        do {
            let downloaded = try await localTranslationsRetriever.getLocalTranslations()
                .filter { $0.isTafsir && $0.isDownloaded }
            tafsirs = downloaded
            selectedTafsir = preferences.selectedTafsir(from: downloaded)
        } catch {
            crasher.recordError(error, reason: "Tafsir: failed to read local translations")
            content = .failed
            return
        }
        await loadContent()
    }

    func select(_ tafsir: Translation) async {
        guard tafsir != selectedTafsir else {
            return
        }
        logger.info("Tafsir: selected tafsir \(tafsir.id)")
        preferences.selectedTafsirId = tafsir.id
        selectedTafsir = tafsir
        await loadContent()
    }

    func next() async {
        guard let nextVerse else {
            return
        }
        await show(nextVerse)
    }

    func previous() async {
        guard let previousVerse else {
            return
        }
        await show(previousVerse)
    }

    func retry() async {
        await reloadTafsirs()
    }

    // MARK: Private

    private let localTranslationsRetriever: LocalTranslationsRetriever
    private let dataService: QuranTextDataService
    private let preferences: TafsirPreferences
    private let onVerseChange: (AyahNumber) -> Void

    /// Counts loads, so a slow load that a newer one replaced does not overwrite it.
    private var loadGeneration = 0

    private var passage: TafsirPassage? {
        if case .loaded(let passage) = content {
            return passage
        }
        return nil
    }

    private func show(_ verse: AyahNumber) async {
        logger.info("Tafsir: show verse \(verse.nonLocalizedDescription)")
        self.verse = verse
        onVerseChange(verse)
        await loadContent()
    }

    private func loadContent() async {
        guard let tafsir = selectedTafsir else {
            content = .noTafsirs
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        let verse = verse
        if passage?.text.verses.contains(verse) != true || passage?.tafsir != tafsir {
            content = .loading
        }
        do {
            let text = try await dataService.tafsir(for: verse, translation: tafsir)
            let arabicText = try await dataService.numberedArabicText(for: text.verses)
            guard generation == loadGeneration else {
                return
            }
            content = .loaded(TafsirPassage(tafsir: tafsir, text: text, arabicText: arabicText))
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else {
                return
            }
            crasher.recordError(error, reason: "Tafsir: failed to read \(tafsir.id) for \(verse.nonLocalizedDescription)")
            content = .failed
        }
    }
}
