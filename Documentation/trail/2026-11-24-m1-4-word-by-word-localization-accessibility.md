# M1.4: word-by-word localization, VoiceOver and large-text layout

- **Date:** 2026-11-24
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** fix
- **Status:** shipped
- **Related:** [2026-11-24-m1-canonical-word-data.md](2026-11-24-m1-canonical-word-data.md),
  [2026-11-24-word-by-word-recitation.md](2026-11-24-word-by-word-recitation.md),
  [quran-roadmap-progress.md](../agents/quran-roadmap-progress.md) (M1.4)

## Context

The owner asked to continue the roadmap from M1.4: localize the word-by-word controls in every
shipped language, and check VoiceOver, Dynamic Type, RTL and iPad split view for
`QuranWordByWordText`.

Found on `da6a3766`:

- `menu.word_by_word` was English ("Word-by-word meaning") in all 14 non-English, non-Arabic
  catalogs (`de`, `es`, `fa`, `fr`, `kk`, `ms`, `nl`, `pt`, `ru`, `tr`, `ug`, `uz`, `vi`, `zh`).
  `menu.word_by_word.off` was already translated everywhere.
- The reciter name `qari_afasy_qul_word_by_word` was English in the 12 `Readers.strings` that
  translate the other reciters (`tr` and `zh` have no `Readers.strings` and fall back to English
  for every reciter, so they are unchanged).
- **Layout bug:** each word cell in `QuranWordByWordText` used `.fixedSize()`, so it ignored the
  column width. At accessibility text sizes a long meaning made one cell wider than the screen:
  the new layout test measured the ayah at **747 pt in a 320 pt column** (iPad split view or a
  compact iPhone), clipping the ayah off screen.
- VoiceOver already combined each cell's Arabic and meaning, but the word being recited was not
  announced.
- `make preview` cannot run here: it needs the `build-ios-apps` Codex plugin, which is not
  installed (`Preview error: Install the build-ios-apps Codex plugin...`).

## Decisions

- **Translations are the agent's, not a native speaker's.** Each follows the wording of the
  catalog's existing reciter-style suffixes and "word translation pointer" strings in the same
  file. Native review is UNVERIFIED (owner checklist).
- **The recited word reads as selected** (`.isSelected` trait) instead of a new localized
  "now reciting" value: no new string in 16 catalogs, and VoiceOver users already know the
  trait. Whether "selected" is clear enough during playback is UNVERIFIED on device.
- **Explicit label (Arabic, then meaning)** replaces `.combine`, so the reading order is fixed
  and unit-tested rather than inferred from layout.
- **Cells may wrap, never widen past the column** (`.fixedSize(horizontal: false, vertical:
  true)`): at default sizes every cell keeps its natural single-line width (a test pins that), and
  only a cell that would exceed the column wraps its meaning.
- **Arabic size not changed.** The Arabic follows the app's Quran font-size setting (as
  `QuranArabicText` does), while meanings follow system Dynamic Type; at AX5 the meaning is
  larger than the Arabic. Changing that is a product choice; recorded under Follow-ups.
- **Speech language not set.** No public SwiftUI API sets a per-text speech language (searched
  `SwiftUICore.swiftinterface` in the iPhoneOS 27.2 SDK: only `speechSpellsOutCharacters`,
  `speechAdjustedPitch` and similar). VoiceOver's automatic language detection is relied on,
  UNVERIFIED.

## Trade-offs

- **Complexity added:** 3 source lines of behavior in `QuranWordByWordText.swift` plus one
  computed property; 26 catalog values; 1 new test file (4 tests) and 1 catalog test. No new
  dependency, permission, persisted state or background work.
- **Who benefits / how often:** speakers of the 14 languages who open the more menu (the title
  was English for them); VoiceOver users of word-by-word mode (likely rare, UNVERIFIED); anyone at
  large text sizes or in iPad split view with word-by-word meanings on, who previously lost part
  of the ayah off screen.
- **Rejected cheaper options:** leaving English as fallback (visible untranslated title next to
  translated "Off"); a horizontal scroll per ayah (breaks reading flow and VoiceOver order);
  capping Dynamic Type for meanings (hurts the users who need large text).
- **Ongoing cost:** any new word-by-word string must be added to all 16 catalogs; the new
  catalog test fails if one shows English.

## Changes

- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings` (14): `menu.word_by_word`.
- `Core/Localization/Sources/Resources/*.lproj/Readers.strings` (12):
  `qari_afasy_qul_word_by_word`.
- `UI/NoorUI/Sources/Features/Quran/QuranWordByWordText.swift`: `QuranWordMeaning.accessibilityLabel`;
  word cells use an explicit label and the `.isSelected` trait when recited; cells cap at the
  column width. Shared by iPhone and iPad (translation view).

## Tests

- `LocalizationTests`: `testWordByWordStringsAreTranslatedInEveryLocalization`. Shown to fail
  without the translations (ran it with the catalog changes stashed: `de shows English for
  menu.word_by_word`, and the same for each language and the reciter name).
- `NoorUITests`, new `QuranWordByWordTextTests`:
  `testVoiceOverReadsTheArabicThenItsMeaning`,
  `testVoiceOverReadsOnlyTheArabicForAWordWithoutAMeaning`,
  `testALongMeaningWrapsInsteadOfWideningTheAyahPastTheScreenAtAccessibilitySizes` (failed
  before the fix: `XCTAssertLessThanOrEqual failed: ("747.0") is greater than ("320.0")`),
  `testShortMeaningsKeepTheirWordsOnOneLineAtTheDefaultSize`.

## Validation

- **Verified:**
  - `make test-no-sync TARGET=LocalizationTests`: `Executed 53 tests, with 0 failures`.
  - `make test-no-sync TARGET=NoorUITests`: `Executed 265 tests, with 0 failures`.
  - Rendered 2:4 with `ImageRenderer` from a temporary test (deleted, not committed) at 375 pt
    default size (Light), 320 pt AX5 (Dark), 320 pt xxxLarge: words flow right to left, the
    recited word's highlight shows in both themes, long meanings wrap inside the column.
  - `make format-lint`: `0/1061 files require formatting`.
  - `make test-no-sync`: `Test Succeeded`; xcresult summary `totalTestCount 1390, passedTests
    1390, failedTests 0` (was 1,385).
  - `make test-sync`: `Test Succeeded`; xcresult summary `totalTestCount 1896, passedTests 1896,
    failedTests 0` (was 1,891).
  - `make build-example-no-sync` and `make build-example-sync`: `Build Succeeded`.
- **Not verified:** VoiceOver speech on a device (Arabic voice selection, "selected" during
  playback); translation quality for all 14 languages; the reader in a real iPad split view and a
  large iPhone in landscape (only the view was rendered, not the app); `make preview` (tool
  missing).

## Release

- **Commit:** pending
- **Pushed:** pending
- **TestFlight:** pending
- **iCloud / CloudKit schema:** unchanged

## Follow-ups

- Decide whether word meanings should follow the app's translation font-size setting instead of
  system Dynamic Type, as translation text does (`QuranTranslationTextChunk.swift:46`), so they
  stay in proportion to the Arabic (owner product choice).
- Native-speaker review of the 26 new strings.
- `tr` and `zh` lack `Readers.strings`: every reciter name is English there (pre-existing).
