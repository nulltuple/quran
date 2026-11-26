# Quran F1 follow-up: collection and note marks in the no-sync translation view

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-26-f1-local-collections-ui.md](2026-11-26-f1-local-collections-ui.md) (follow-up
  "Mark collected ayahs on the page in the no-sync reader")

## Context

App: **Quran** (shared NoorUI and QuranAnnotations change; both compile into Arabican too).
Roadmap progress "Next steps" item 1: F1 shipped collections in the no-sync build, but the reader
did not mark collected ayahs. `VerseOverlays.collectionVerses`, `AyahIndicator`, `AyahIndicatorIcon`
and the indicator part of `QuranVerseNumber` were all `#if QURAN_SYNC`, and
`QuranAnnotationsObserver.updateCollections` only wrote `collectionVerses` with sync.

What the sync build actually marks (read before changing anything):

- **Translation view:** the ayah-number capsule (`UI/NoorUI/Sources/Features/Quran/QuranVerseNumber.swift`)
  shows reading-bookmark, collection (filled star) and note icons from `VerseOverlays.indicators(for:)`
  (`Features/QuranTranslationFeature/Sources/ContentTranslationViewModel.swift`, `indicatorsByVerse`).
- **Mushaf page (image and line pages):** only reading bookmarks are drawn (underlines under the ayah
  marker, `AyahReadingBookmarkUnderlines`, and header ribbons). Collections and notes have no mark on the
  mushaf page in either build; `ContentImageViewModel` and `ContentLineViewModel` read only
  `readingBookmarkSlotsByVerse`/`pageReadingBookmarkSlots`.
- `QuranContentStatePreferences.ayahIndicatorVisibility` (More menu "Ayah indicators") is stored but no
  reader code reads it (`grep -rn ayahIndicatorVisibility` finds only the More menu, the preference and
  analytics); `testIndicatorsShowEveryAnnotationWhateverTheStoredPreference` pins that. Unchanged here.

## Decisions

- **Match the sync build: marks in the translation view's ayah-number capsule only.** The roadmap item
  said "mark collected ayahs on the page"; the sync reader marks them only in the translation view, so
  the no-sync build now does the same. A new star badge on the mushaf page would be a new visual
  pattern in both builds (CLAUDE.md: match established layouts first), so it is left as a follow-up for
  the owner to ask for.
- **Note icon only for notes with text.** Without sync a highlight is stored as a note with no text
  (`NoteService.updateHighlight` saves `nil` text), so `notedVerses` from every note would put a note
  icon on every highlighted ayah. The no-sync observer now fills `notedVerses` from notes whose text is
  not blank (`Note.hasText`, no-sync only). Highlights keep their color and get no icon, as in sync.
- **`AyahIndicator.readingBookmark` stays sync-only**, as a `#if` case inside the now unconditional
  enum, because `ReadingBookmarkSlot` is sync-only (`Model/QuranAnnotations/Sources/ReadingBookmark.swift`).
- **The capsule stays a plain label without sync.** Its tap opens the reading-bookmark menu, which has
  no no-sync data, so `onTapped` remains sync-only and the no-sync initializer is
  `QuranVerseNumber(verse:indicators:)`.

## Trade-offs

- **Complexity added:** small; mostly removing `#if QURAN_SYNC` around existing code (8 source files),
  one no-sync `Note.hasText`, three new test files. No new dependency, permission, persisted format,
  background work or string.
- **Who benefits / how often:** every TestFlight user who saves ayahs to Favorites or a collection, or
  writes notes, and reads in translation mode. Users reading only the mushaf page see no change.
- **Rejected cheaper options:** leaving the follow-up open (F1 users had no in-reader sign of what they
  saved outside the ayah menu); a mushaf-page star badge (new visual pattern, see Decisions).
- **Ongoing cost:** fewer `#if` branches than before in the indicator code; the indicator path now runs
  in both builds, so both test suites cover it.

## Changes

- `Model/QuranAnnotations/Sources/AyahIndicator.swift`: unconditional; `.readingBookmark` sync-only.
- `Model/QuranAnnotations/Sources/VerseOverlays.swift`: `collectionVerses`, its page filter and
  `indicators(for:)` in both builds (reading-bookmark part sync-only).
- `Model/QuranAnnotations/Sources/Note.swift`: no-sync `hasText`.
- `UI/NoorUI/Sources/Features/Quran/AyahIndicator+UI.swift`, `AyahIndicatorIcon.swift`,
  `QuranVerseNumber.swift`: indicators render in both builds; no-sync preview shows them.
- `Features/QuranTranslationFeature/Sources/ContentTranslationViewModel.swift`, `TranslationItem.swift`,
  `TranslationItem+View.swift`: `indicatorsByVerse` and `TranslationVerseNumber.indicators` in both builds.
- `Features/QuranViewFeature/Sources/QuranAnnotationsObserver.swift`: `collectionVerses` written in both
  builds; no-sync `notedVerses` from notes with text.
- Platforms: iPhone and iPad (same code); no Mac target.

## Tests

- `Model/QuranAnnotations/Tests/VerseOverlaysCollectionIndicatorTests.swift` (3, both builds).
- `Model/QuranAnnotations/Tests/NoteTests.swift`: no-sync `test_hasText_isFalseForAHighlightWithoutText`.
- `UI/NoorUI/Tests/AyahIndicatorTests.swift` (2, both builds): order and accessibility labels.
- `Features/QuranViewFeature/Tests/LocalQuranAnnotationsObserverTests.swift` (+2, no-sync, real Core Data):
  collected ayahs reach `collectionVerses` and leave it on removal; a highlight alone gets no note mark.
- `Features/QuranTranslationFeature/Tests/ContentTranslationViewModelTests.swift`: three note/collection
  indicator tests moved out of `#if QURAN_SYNC`, so they now run in the no-sync suite too.
- Fails without the change: reasoned from the diff. Without it the no-sync tests do not compile
  (`collectionVerses`, `indicators(for:)`, `indicatorsByVerse`, `hasText` do not exist without sync).

## Validation

- **Verified:** focused no-sync runs: QuranAnnotationsTests `Executed 24 tests, with 0 failures`,
  NoorUITests `Executed 269 tests, with 0 failures`, QuranTranslationFeatureTests `Executed 48 tests, with 0
  failures`, QuranViewFeatureTests `Executed 32 tests, with 0 failures`. `make format-lint`:
  `0/1145 files require formatting`. Full suites on the tree with this change and R1
  ([2026-11-26-r1-mushaf-editions.md](2026-11-26-r1-mushaf-editions.md)), one after the other:
  `make test-no-sync` 1,457 passed, 0 failed; `make test-sync` 1,936 passed, 0 failed; `make test-arabican`
  117 passed, 0 failed (counts from `xcresulttool get test-results summary`). `make build-example-no-sync`,
  `make build-example-sync`, `make build-arabican`: `Build Succeeded`. Simulator (iPhone 18 Pro Max,
  no-sync Debug, light, portrait, default text): Translation/Tafseer mode on page 2 shows `2:2 | ★` for the
  ayah saved to Favorites in the F1 session, and plain capsules for 2:1, 2:3–2:5.
- **Not verified:** Dark mode, landscape, the largest text size and VoiceOver on the capsule (the layout is
  the sync build's, unchanged); the note icon on screen (covered by `LocalQuranAnnotationsObserverTests` and
  the translation view model tests); compact iPhone and iPad split view (one simulator only). Owner
  checklist item 13.

## Release

- **Commit:**
- **Pushed:**
- **TestFlight:**
- **iCloud / CloudKit schema:** unchanged

## Follow-ups

- A collection or note mark on the mushaf page (image and line pages) in both builds, if the owner
  wants one: today only reading bookmarks are drawn there.
- `ayahIndicatorVisibility` is stored but unused by the reader (pre-existing, sync-only setting).
