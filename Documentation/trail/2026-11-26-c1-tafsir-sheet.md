# Quran C1: tafsir sheet from the ayah menu, Arabic tafsir passages

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-26-quran-roadmap-v2.md](2026-11-26-quran-roadmap-v2.md) (C1 research result),
  roadmap v2 §6 C1 (`Documentation/agents/quran-prioritized-roadmap.md`)

App: **Quran** (and Arabican rebuilds: NoorUI, a module Arabican imports, gained a case and an ayah-menu action).

## Context

Roadmap v2 §5 puts C1 (tafsir) first: "Tafsir is the largest comprehension gap". Its research result said
the Quran.app translations feed (`https://quran.app/data/translations.php?v=5`) lists 11 Arabic tafsirs as
ordinary translation entries, so they "should already download and show" (UNVERIFIED until this entry).

Checked in the simulator (no-sync Debug, iPhone 18 Pro Max): Settings > Translations lists every Arabic
tafsir under العربية; Arabic Muyassar (id 64) and Sahih International downloaded, and Translation/Tafseer mode
showed Muyassar under each ayah, right-to-left, with its Quran quotations colored, attributed `- الميسر`.
So Arabic tafsir already worked inline. What was missing: reading tafsir from the Mushaf page, choosing a
tafsir without changing the reader's translations, and saying which ayahs a passage explains.

The downloaded `quran.ar.muyassar.db` (5,615,616 bytes, `text_version` 10, `schema_version` 5, FTS3 table
`verses(sura, ayah, text)`, rowid = verse index):

- 6,236 rows; 1,196 store an integer instead of text. Every integer is the 1-based verse index of a later ayah
  in the same sura that holds the passage's text (`2:45 → 53` = 2:46; `4:66, 4:67 → 561` = 4:68); no
  reference points to another reference; the largest passage is 14 ayahs.
- Text length: at most 1,463 characters, mean 169.
- `TranslationsParser` / `GRDBTranslationVerseTextPersistence` already read such integers as
  `.reference(AyahNumber)` (`Data/VerseTextPersistence/Sources/GRDBVerseTextPersistence.swift`, `textFromRow`),
  and the translation view shows "See ayah N." for them.
- A `WHERE text = 561 OR text = '561'` scan over the file took 0.005 s with `sqlite3` on this Mac.

The other 10 tafsirs were not downloaded; that their files use the same reference shape is UNVERIFIED (the
code handles references in either direction, so a file that refers backwards also works).

## Decisions

- **Reuse the translations pipeline.** Tafsirs download, update and delete through Settings > Translations as
  before; no new download code, no new storage. Rejected: a separate tafsir download store (duplicates
  `TranslationService`).
- **Which entries are tafsirs.** The feed has no type field, so `Translation.tafsirIDs`
  (`Model/QuranText/Sources/Translation+Tafsir.swift`) lists the 11 tafsir ids read from the feed on
  2026-11-26 (58, 59, 60, 61, 62, 63, 64, 92, 95, 99, 113). Rejected: matching "Tafseer" in the display
  name (fragile, misses `Arabic I'rab Tafsir Center` spellings in other feeds). Asbab al-Nuzool (84), Qira'at
  (100), Hidayat (94), Word Meanings (85) and Betaqat (96) are commentary-like but left out: they are not
  tafsirs of the ayah's meaning.
- **Passages.** `QuranTextDataService.tafsir(for:translation:)` reads the ayah's row; for a reference it reads
  the holder's text; then `versesReferencing(holder)` (one scan) finds the passage's other ayahs. The sheet
  shows the passage's whole range ("Al-Baqarah 2:45–46"), a note that one explanation covers these ayahs,
  the Quran text of every ayah in it, and next/previous skip past the passage.
- **Sheet, not a new reader mode.** Modeled on the existing translation sheet (`TranslationVerseFeature`) and
  presented through the same `presentTranslatedVerse` (medium/large detents, leading Close ×); next/previous
  arrows in the same order; moving highlights the ayah in the reader behind it, like the translation sheet.
- **Ayah menu.** One "Tafsir" row in the group that held "Translation/Tafseer"; shown in both page and
  translation modes (the translation row stays page-mode only). `AyahMenuUI.studyRows(isTranslationView:)`.
- **Selection.** `TafsirPreferences.selectedTafsirId` (key `tafsir.selected`), separate from the reader's
  selected translations; falls back to the first downloaded tafsir. A picker appears only with two or more.
- **Empty state.** With no tafsir downloaded the sheet says so and opens the existing translations list; on
  close it rereads the downloaded tafsirs.
- **Not changed:** tafsirs stay in the translations picker and, when selected there, still show inline (owner
  can ask to hide them). Downloading from the translations list selects the download for the reader too
  (existing behavior), so a tafsir downloaded through the sheet's empty state also appears in the
  translation view until deselected. Recorded as a follow-up rather than changed silently.
- **English and Bengali tafsir:** not in the feed (roadmap D6). Not built; owner question stands.
- Strings: 6 new keys in all 16 `Localizable.strings` (agent translations; native review UNVERIFIED). Next and
  previous reuse `translation.verse.next` / `translation.verse.previous`.

## Trade-offs

- **Complexity added:** new module `Features/TafsirFeature` (4 source files, 475 lines; 1 test file); one
  persistence method (`versesReferencing`, a protocol requirement with one conformer); one domain method;
  one preference key; one `NoorSystemImage` case (`tafsir` = `text.book.closed`); one ayah-menu action; 6
  strings × 16 languages. Made 4 QuranTranslationFeature helpers public (`textFont`, `footnoteFont`,
  `characterDirection`, `footnoteText(at:)`) instead of copying them. No dependency, permission or
  entitlement; no background work; one new persisted value (an optional `Int` in UserDefaults).
- **Who benefits / how often:** anyone who reads tafsir; for Arabic readers likely often. For the owner's
  English/Bengali use it is limited to Arabic tafsir until D6 is decided: flag this as possibly rarely used
  by the owner today.
- **Rejected cheaper options:** doing nothing (tafsir already shows inline in Translation mode) leaves the
  Mushaf page without tafsir and passages unexplained; a "tafsir link per ayah" in the translation view
  (spec) was not built: the ayah menu already reaches the sheet from that view, and a per-ayah link adds a
  row to every ayah.
- **Ongoing cost:** the id list must be updated if Quran.app adds tafsirs; one more sheet to keep accessible.
  No launch-time cost (the sheet loads on demand); each open runs two indexed-by-scan queries on one file.

## Changes

- `Data/VerseTextPersistence`: `TranslationVerseTextPersistence.versesReferencing(_:)`, implemented by
  `GRDBTranslationVerseTextPersistence` (integer and numeric-string references).
- `Model/QuranText/Sources/Translation+Tafsir.swift`: `Translation.tafsirIDs`, `isTafsir`, `TafsirText`.
- `Domain/QuranTextKit`: `QuranTextDataService.tafsir(for:translation:)`.
- `Domain/TranslationService/Sources/TafsirPreferences.swift`: the selected tafsir.
- `UI/NoorUI`: `NoorSystemImage.tafsir`; `AyahMenuUI.Actions.showTafsir`, `AyahMenuUI.studyRows`; the menu's
  `.study` group renders Translation (page mode) and Tafsir.
- `Features/AyahMenuFeature`: `AyahMenuListener.showTafsir(_:)`, `AyahMenuViewModel.showTafsir()`.
- `Features/TafsirFeature` (new): `TafsirBuilder`, `TafsirViewModel`, `TafsirView`, `TafsirViewController`.
- `Features/QuranViewFeature`: `QuranInteractor.showTafsir(_:)`, `tafsirBuilder` in `Deps`, wired in
  `QuranBuilder` (sync and no-sync).
- `Features/QuranTranslationFeature`: 4 helpers made public (above).
- `Core/Localization`: 6 keys × 16 languages.
- `Package.swift` (TafsirFeature target, GRDB for QuranTextKit tests), `QuranEngine-Package.xctestplan`.
- Platforms: iPhone and iPad (one universal target); no platform-specific code.

## Tests

- `VerseTextPersistenceTests.GRDBVerseTextPersistenceTests.testVersesReferencingFindsIntegerAndNumericStringReferencesToTheVerse`
- `QuranTextKitTests.QuranTextDataServiceTafsirTests` (5): own text, referring ayah, holder with integer and
  string references (and footnotes parsed), blank text is no text, tafsir ids.
- `TranslationServiceTests.TafsirPreferencesTests` (3).
- `NoorUITests.AyahMenuStudyRowsTests` (2).
- `AyahMenuFeatureTests`: `test_showTafsir_opensTafsirForSelectedVerses` in the sync and legacy suites.
- `TafsirFeatureTests.TafsirViewModelTests` (6): only downloaded tafsirs listed, passage and next skipping it,
  previous, switching tafsir keeps the ayah and persists, empty state, no previous at 1:1. Real
  `QuranTextDataService`, real GRDB files, `LocalTranslationsFake` at the file-system boundary.

## Validation

- **Verified:**
  - `make test-no-sync TARGET=QuranTextKitTests`: `Executed 52 tests, with 0 failures`.
  - `make test-no-sync TARGET=TafsirFeatureTests`: `Executed 6 tests, with 0 failures`.
  - `make format-lint`: `0/1154 files require formatting`.
  - Simulator (no-sync Debug, light, portrait, default text): long-press 2:1 in Translation/Tafseer mode →
    the menu shows "Tafsir" between Add Note and Copy → the sheet opens at medium height with
    "Al-Baqarah 2:1", the ayah in the Quran font and Muyassar's text right-to-left with `- الميسر`; the next
    arrow shows 2:2 and highlights it in the reader. First render had the text touching the sheet's left
    edge; fixed with `.populateReadableInsets()` and checked again.
  - `make test-no-sync` (full plan): 1,475 tests, 1,474 passed, 1 failed:
    `LastPagePersistenceTests CoreDataLastPageUniquifierTests/test_merge_removingOverflow()` | `Crash: xctest`.
    This change does not touch `Data/LastPagePersistence`. Rerun alone twice on this tree:
    `Executed 10 tests, with 0 failures` both times; on the parent commit `ddd2120e` (a temporary worktree):
    `Executed 10 tests, with 0 failures`. Treated as an intermittent crash, recorded under Follow-ups.
  - `make test-sync` (full plan, after no-sync): 1,954 tests, 1,954 passed, 0 failed (xcresult summary).
  - `make test-arabican` (after the Quran suites): 117 tests, 117 passed, 0 failed.
  - `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: `Build Succeeded` each.
- **Not verified:**
  - A multi-ayah passage on screen (2:45–46): covered by unit tests on Muyassar-shaped data, not seen in the
    simulator.
  - Opening the sheet from the Mushaf page (image) mode, Dark mode, landscape, the largest text sizes,
    VoiceOver order, the two-tafsir picker, the empty state's Download button: not checked by hand.
  - iPad and compact iPhone layouts: no other simulator allowed; the sheet uses readable insets and no
    fixed widths.
  - The other 10 tafsir files' format; Ibn Kathir's text length (longest texts are expected there).
  - Native-speaker review of the 15 translations.

## Release

- **Commit:** 2688bda9
- **Pushed:** origin/main at 2688bda9
- **TestFlight:** Quran build 988 (1.20.3): `Uploaded Quran iOS 1.20.3 (988) for commit 2688bda9bd95c4494e375297c04b587749ad7363 to App Store Connect app MemQuran.` Arabican build 988 (0.1.0), for the shared NoorUI change: `Uploaded Arabican iOS 0.1.0 (988) for commit 2688bda9bd95c4494e375297c04b587749ad7363 to App Store Connect app Arabican.`
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Owner **D6**: where English and Bengali tafsir packs come from and where they are hosted. Quran.com API v4
  `GET /api/v4/resources/tafsirs` (read 2026-11-26, 20 tafsirs) lists English: Ibn Kathir (Abridged) id 169,
  Ma'arif al-Qur'an 168, Tazkirul Quran 817; Bengali: Ahsanul Bayaan 165, Abu Bakr Zakaria 166, Ibn Kathir
  (Tawheed Publication) 164, Fathul Majid 381. A `Tools/` script could fetch one into the feed's SQLite shape
  (`verses(sura, ayah, text)`, references as verse indexes) so the sheet reads it unchanged; how API v4 marks
  passages is UNVERIFIED.
- Optional: keep tafsirs out of the reader's translation picker, or stop a download made from the tafsir
  sheet from selecting it for the reader.
- Intermittent: `CoreDataLastPageUniquifierTests/test_merge_removingOverflow` crashed xctest once in the full
  no-sync plan (passes alone and on the parent commit). Investigate if it recurs.
- Optional: a per-ayah tafsir link in the translation view (spec), if the ayah menu proves too hidden.
