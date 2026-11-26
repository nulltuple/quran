#if !QURAN_SYNC
import AnalyticsFake
import AnnotationsService
import Combine
import QuranAnnotations
import QuranKit
import QuranResources
import QuranTextKit
import UIKit
import XCTest
@testable import AyahMenuFeature
@testable import NotePersistence

@MainActor
final class AyahMenuLegacyViewModelTests: XCTestCase {
    func test_updateHighlightPersistsSelectedColorAndDismissesMenu() async {
        let persistence = NotePersistenceSpy()
        let sut = makeSUT(persistence: persistence)
        let listener = ListenerSpy()
        sut.listener = listener

        await sut.updateHighlight(color: .blue)

        XCTAssertEqual(persistence.setNoteCall, .init(
            note: nil,
            verses: [
                VersePersistenceModel(ayah: 7, sura: 1),
                VersePersistenceModel(ayah: 1, sura: 2),
            ],
            color: HighlightColor.blue.rawValue
        ))
        XCTAssertTrue(listener.didDismiss)
    }

    func test_bookmark_opensCollectionEditorForSelectedVerses() {
        let verses = [
            AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 7)!,
            AyahNumber(quran: .hafsMadani1405, sura: 2, ayah: 1)!,
        ]
        let sut = makeSUT(verses: verses)
        let listener = ListenerSpy()
        sut.listener = listener

        sut.bookmark()

        XCTAssertEqual(listener.collectionEditorVerses, verses)
    }

    func test_showTafsir_opensTafsirForSelectedVerses() {
        let verses = [
            AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 7)!,
            AyahNumber(quran: .hafsMadani1405, sura: 2, ayah: 1)!,
        ]
        let sut = makeSUT(verses: verses)
        let listener = ListenerSpy()
        sut.listener = listener

        sut.showTafsir()

        XCTAssertEqual(listener.tafsirVerses, verses)
    }

    func test_bookmarkState_isBookmarkedWhenACollectionHasASelectedVerse() {
        let first = AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 7)!
        let other = AyahNumber(quran: .hafsMadani1405, sura: 3, ayah: 1)!

        XCTAssertEqual(makeSUT(bookmarkedVerses: []).bookmarkState, .unhighlighted)
        XCTAssertEqual(makeSUT(bookmarkedVerses: [other]).bookmarkState, .unhighlighted)
        XCTAssertEqual(makeSUT(bookmarkedVerses: [first]).bookmarkState, .bookmarked)
    }

    func test_share_sharesSelectedVerseText() async throws {
        let originalQuranMode = QuranContentStatePreferences.shared.quranMode
        defer { QuranContentStatePreferences.shared.quranMode = originalQuranMode }
        QuranContentStatePreferences.shared.quranMode = .arabic
        let sut = makeSUT(
            verses: [AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 1)!],
            quranFileURL: QuranResources.quranUthmaniV2Database
        )
        let listener = ListenerSpy()
        sut.listener = listener

        await sut.share()

        let sharedText = try XCTUnwrap(listener.sharedLines?.first)
        XCTAssertEqual(listener.sharedLines?.count, 1)
        XCTAssertTrue(sharedText.contains("﴿ ١ ﴾"))
        XCTAssertTrue(sharedText.hasSuffix("\n\nAl-Fātihah 1:1"))
        XCTAssertTrue(listener.shownErrors.isEmpty)
    }

    func test_share_showsErrorWhenVerseTextIsUnavailable() async {
        let sut = makeSUT()
        let listener = ListenerSpy()
        sut.listener = listener

        await sut.share()

        XCTAssertEqual(listener.shownErrors.count, 1)
        XCTAssertNil(listener.sharedLines)
    }

    func test_copy_showsErrorWhenVerseTextIsUnavailable() async {
        let sut = makeSUT()
        let listener = ListenerSpy()
        sut.listener = listener

        await sut.copy()

        XCTAssertEqual(listener.shownErrors.count, 1)
        // `showError` dismisses the menu itself; dismissing it first would leave that dismissal in flight.
        XCTAssertFalse(listener.didDismiss)
    }

    private func makeSUT(
        persistence: NotePersistence = NotePersistenceSpy(),
        verses: [AyahNumber] = [
            AyahNumber(quran: .hafsMadani1405, sura: 1, ayah: 7)!,
            AyahNumber(quran: .hafsMadani1405, sura: 2, ayah: 1)!,
        ],
        quranFileURL: URL? = nil,
        bookmarkedVerses: Set<AyahNumber> = []
    ) -> AyahMenuViewModel {
        let unavailableDatabase = URL(fileURLWithPath: "/tmp/unavailable-quran-database")
        return AyahMenuViewModel(deps: .init(
            sourceView: UIView(),
            pointInView: .zero,
            verses: verses,
            textRetriever: ShareableVerseTextRetriever(
                databasesURL: unavailableDatabase,
                quranFileURL: quranFileURL ?? unavailableDatabase
            ),
            notes: [],
            bookmarkedVerses: bookmarkedVerses,
            noteService: NoteService(persistence: persistence, analytics: AnalyticsLibrarySpy())
        ))
    }
}

private final class NotePersistenceSpy: NotePersistence {
    struct SetNoteCall: Equatable {
        let note: String?
        let verses: [VersePersistenceModel]
        let color: Int
    }

    private(set) var setNoteCall: SetNoteCall?

    func notes() -> AnyPublisher<[NotePersistenceModel], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func setNote(
        _ note: String?,
        verses: [VersePersistenceModel],
        color: Int
    ) async throws -> NotePersistenceModel {
        setNoteCall = .init(note: note, verses: verses, color: color)
        return NotePersistenceModel(
            verses: Set(verses),
            modifiedDate: .distantPast,
            note: note,
            color: color
        )
    }

    func removeNotes(with verses: [VersePersistenceModel]) async throws -> [NotePersistenceModel] {
        []
    }
}

@MainActor
private final class ListenerSpy: AyahMenuListener {
    private(set) var didDismiss = false
    private(set) var sharedLines: [String]?
    private(set) var shownErrors: [Error] = []
    private(set) var collectionEditorVerses: [AyahNumber]?
    private(set) var tafsirVerses: [AyahNumber]?

    func dismissAyahMenu() {
        didDismiss = true
    }

    func playAudio(_ from: AyahNumber, to: AyahNumber?, repeatVerses: Bool) {}

    func shareText(_ lines: [String], in sourceView: UIView, at point: CGPoint) {
        sharedLines = lines
    }

    func showError(_ error: Error) {
        shownErrors.append(error)
    }

    func showTranslation(_ verses: [AyahNumber]) {}

    func showTafsir(_ verses: [AyahNumber]) {
        tafsirVerses = verses
    }

    func showNoteEditor(for verses: [AyahNumber]) async {}
    func deleteNotes(in verses: [AyahNumber]) async {}

    func showCollectionEditor(for verses: [AyahNumber]) {
        collectionEditorVerses = verses
    }
}
#endif
