# Quran F1: collections and Favorites in the shipping (no-sync) build

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** in-progress
- **Related:** [2026-11-25-m3-1-local-verse-collections-store.md](2026-11-25-m3-1-local-verse-collections-store.md),
  [2026-11-26-quran-roadmap-v2.md](2026-11-26-quran-roadmap-v2.md) (F1 was M3.2)

## Context

App: **Quran** (shared NoorUI change also compiles into Arabican). Roadmap v2's first slice, F1:
in TestFlight (no-sync), the ayah menu's Bookmark action opens the collection editor and the
Bookmarks tab lists Favorites and the user's collections, stored by M3.1's
`PersistenceAyahBookmarkCollectionService` (Core Data model `Quran 3`, shipped in build 961 with no
UI). Before this change every collection screen was `#if QURAN_SYNC`
(`Features/BookmarksFeature/Sources/*.swift` first line), the no-sync Bookmarks tab was only page
bookmarks (`BookmarksBuilder.swift`, old `BookmarksViewController`), and the ayah menu had no
Bookmark row without sync (`UI/NoorUI/Sources/Features/AyahMenu/AyahMenuView.swift`, `annotations`).

## Decisions

- **Highlights stay note-based without sync.** The sync screens also edit and list highlights through
  `MobileSyncAyahHighlightService`, a model where a highlight is separate from a note. The no-sync
  store keeps the upstream model: a highlight is a colored note (`CoreDataNotePersistence.setNote`
  merges intersecting notes, `removeNotes` deletes text too). A same-API highlight service over notes
  would have to either delete note text on "remove highlight" or silently keep the color. Instead the
  no-sync collection editor shows collections only, highlights keep their existing home (the ayah
  menu's color row and the Notes tab), and the no-sync Bookmarks tab has no Highlights section.
  This supersedes the M3.1 follow-up "no-sync highlight service over `NoteService`".
- **Bookmarks tab shape (roadmap v2 §6 F1):** My Collections (Favorites first, then by name), then a
  new "Page Bookmarks" section reusing the existing no-sync `BookmarksViewModel` as a child view model
  (no page-bookmark logic duplicated). The old screen's Delete All for page bookmarks and its iCloud
  backup info button moved to the new screen's navigation bar (removing a user-visible action needs
  owner approval); the confirmation now says "page bookmarks" because the screen also holds
  collections.
- **One view model per screen, both modes.** `BookmarkCollectionsViewModel`, `BookmarkAyahsViewModel`
  and `AyahSetBuilder` now compile in both modes with the sync-only members (sign-in nudge, Quran.com
  refresh, reading bookmarks, highlights, Old Page Bookmarks tip) behind `#if QURAN_SYNC`, the same
  pattern `AyahMenuViewModel` already uses. Rejected: a second no-sync view model (duplicates create,
  rename, delete, remove-all and their alerts).
- **No reader marks yet.** `VerseOverlays.collectionVerses` and its page indicator are sync-only down
  to rendering (`Model/QuranAnnotations/Sources/VerseOverlays.swift:26`,
  `UI/NoorUI/Sources/Features/Quran/AyahIndicator+UI.swift`). The no-sync reader now loads collections
  (the ayah menu shows a filled star for saved ayahs) but the page does not mark them. Follow-up.
- `#if` in UI: `UI/NoorUI` ayah menu gains the Bookmark row in both modes; the remaining `#if`s in
  `AyahMenuView` and the Bookmarks views are for sync-only rows (reading bookmarks, highlight picker),
  which have no no-sync data.

## Trade-offs

- **Complexity added:** about +465/−247 lines across 52 files (most are un-gating and per-mode
  initializers); two new test files; three strings in 16 catalogs; no dependency, permission,
  entitlement, persisted format or background work. `AppDependencies` gains `collectionPersistence`
  (no-sync only).
- **Who benefits / how often:** every TestFlight user who saves ayahs (Favorites is the common case).
  User collections beyond Favorites are likely used by a minority (UNVERIFIED, no usage data).
- **Rejected cheaper options:** a highlight service over notes (lossy, see Decisions); a separate
  no-sync Bookmarks screen (duplicated logic); waiting for P1 iCloud sync (collections already have a
  local store).
- **Ongoing cost:** the Bookmarks views and view models now carry more `#if QURAN_SYNC` blocks; both
  sync modes must keep compiling (both suites run them). SwiftFormat indents modifiers after an `#if`
  inside a modifier chain (`BookmarkCollectionsView.swift`), which reads oddly but is lint-clean.

## Changes

- Dependencies: `Features/AppDependencies/Sources/AppDependencies.swift` (`collectionPersistence`,
  no-sync `ayahBookmarkCollectionService()`), `Example/QuranEngineApp/Classes/Container.swift`
  (`CoreDataCollectionPersistence` on the app's stack), `Features/AppDependenciesFake` (one shared
  temporary stack), `Package.swift` (target and test dependencies).
- Bookmarks tab: `BookmarksBuilder` always builds `BookmarkCollectionsBuilder`; collection screens
  un-gated (`AyahSet*`, `BookmarkAyahs*`, `BookmarkCollections*`, presentation and preference files);
  `PageBookmarksSection.swift` (was `BookmarksView.swift`: `PageBookmarkRow`, `PageBookmarksSection`);
  `BookmarksViewController.swift` deleted (its Delete All and iCloud info moved to
  `BookmarkCollectionsViewController`).
- Ayah menu: `UI/NoorUI/Sources/Features/AyahMenu/AyahMenuUI.swift` and `AyahMenuView.swift`
  (Bookmark row and `BookmarkState` in both modes), `Features/AyahMenuFeature` (`bookmark()`,
  `bookmarkTitle`, no-sync `bookmarkState`, `bookmarkedVerses` input).
- Reader: `Features/QuranViewFeature/Sources/QuranAnnotationsObserver.swift` (no-sync collections
  observation), `QuranInteractor.swift`/`QuranViewController.swift`/`QuranBuilder.swift`
  (`showCollectionEditor`, `presentBookmarkAyahs` in both modes).
- `UI/NoorUI/Sources/Features/CollectionName/*` un-gated (name alert and errors).
- Strings: `bookmarks.editor.intro.collections` (the existing intro's first sentence in each
  language), `bookmarks.pages`, `bookmarks.pages.delete-all.confirmation` in all 16 catalogs (agent
  translations; native review UNVERIFIED).
- Platforms: iPhone and iPad (same code); no Mac target.

## Tests

- `Features/BookmarksFeature/Tests/LocalBookmarkCollectionsTests.swift` (5, no-sync, real Core Data
  stores): ordering, create without sign-in toast, delete empty collection, page bookmarks make the
  list editable, editor adds/removes the selection in Favorites.
- `Features/AyahMenuFeature/Tests/AyahMenuLegacyViewModelTests.swift`: Bookmark opens the collection
  editor; `bookmarkState` follows `bookmarkedVerses`.
- `Features/QuranViewFeature/Tests/LocalQuranAnnotationsObserverTests.swift` (2): the reader follows
  the local collections store and stops on `stop()`.
- `UI/NoorUI/Tests/AyahMenuViewLayoutTests.swift`: no-sync data object gains the Bookmark row inputs.
- Fails without the change: reasoned from the diff (the no-sync initializers and the observer's
  collection input do not exist before it, so the tests do not compile); not run on the parent.

## Validation

- **Verified:** `make build-no-sync` and `make build-sync`: `Build Succeeded`. Focused no-sync:
  BookmarksFeatureTests `Executed 12 tests, with 0 failures`, AyahMenuFeatureTests `Executed 6 tests,
  with 0 failures`, QuranViewFeatureTests `Executed 30 tests, with 0 failures`. `make format-lint`:
  `0/1141 files require formatting`. Full suites: see Release.
- **Not verified:** the screens in the simulator (see Release for what was checked); VoiceOver and
  large text on the new section; compact iPhone and iPad split view (one simulator only).

## Release

- **Commit:** pending
- **Pushed:** pending
- **TestFlight:** pending
- **iCloud / CloudKit schema:** unchanged

## Follow-ups

- Mark collected ayahs on the page in the no-sync reader (un-gate `collectionVerses` and its
  indicator rendering; check both readers).
- `MO_Collection` uniquifier before P1 (M3.1 follow-up, unchanged).
