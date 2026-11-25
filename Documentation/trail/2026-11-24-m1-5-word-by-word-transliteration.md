# M1.5: transliteration line in word-by-word meanings

- **Date:** 2026-11-24
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-24-m1-4-word-by-word-localization-accessibility.md](2026-11-24-m1-4-word-by-word-localization-accessibility.md),
  [2026-11-24-m1-canonical-word-data.md](2026-11-24-m1-canonical-word-data.md),
  [quran-roadmap-progress.md](../agents/quran-roadmap-progress.md) (M1.5)

## Context

The owner asked to continue the roadmap after M1.4. M1.5 in the progress doc: "optional
transliteration line under meanings in the translation view (data now ships in
`word_by_word.db` `word_meanings.transliteration`); dual-language display only if the owner wants
it". The roadmap's M1 bullet asks for "optionally dual-language display and transliteration when
real data available". The data has a transliteration for all 77,432 words (M1.1 trail).

## Decisions

- **A toggle, off by default.** New `WordByWordPreferences.showsTransliteration` (UserDefaults
  key `wordByWordTransliteration`, default `false`): existing readers see no change.
- **Translation view only.** The toggle shows in the More menu only in translation mode with a
  meaning language on, like the footnotes toggle. The page view's single caption under the
  recited word stays meaning-only; the word pointer already offers transliteration there.
- **Transliteration needs a meaning language.** With meanings off, the translation view shows
  plain Arabic as before and loads no transliterations. Rejected: a transliteration-only mode
  (one more state in the picker for an unrequested combination).
- **Order Arabic, transliteration, meaning**, visually and for VoiceOver: the sound sits next to
  the script it reads, the meaning last as before. Transliteration is italic to tell it apart.
- **Reused the catalog's `translation.text-type.transliteration`** ("Transliteration"),
  already translated in all 16 languages: no new strings.
- **Two canonical words in one text token** (e.g. 15:7 `لَّوۡمَا`) join their transliterations
  with a space and never drop a repeat (meanings drop a consecutive repeat because QUL repeats the
  shared meaning; transliterations are distinct sounds).
- **No dual-language display** (English and Bengali together): not built, waiting on the owner;
  it doubles the rows per word.

## Trade-offs

- **Complexity added:** 1 persisted Bool preference; 1 service method; ~35 lines in
  `ContentTranslationViewModel` (one more parallel query when on); 1 menu row view (23 lines);
  ~15 lines in `QuranWordByWordText`. No dependency, permission or new data.
- **Who benefits / how often:** readers learning to pronounce while studying meanings; likely a
  minority of word-by-word users, who are themselves likely a minority (UNVERIFIED, no
  analytics). Off by default, so the cost to everyone else is one hidden menu row.
- **Rejected cheaper options:** showing transliteration whenever meanings are on (adds a line
  for everyone, longer pages); a picker option per combination (more states than toggles).
- **Ongoing cost:** one more preference to keep; one more query per page load when on (a single
  indexed read of the visible verses, the same shape as the meanings query).

## Changes

- `Domain/WordTextService`: `WordByWordPreferences.showsTransliteration`;
  `WordByWordService.transliterations(for:)`.
- `UI/NoorUI`: `QuranWordMeaning.transliteration` (init default `nil`, existing callers
  unchanged); `QuranWordByWordText` shows it between the word and its meaning; the VoiceOver label
  includes it.
- `Features/QuranTranslationFeature`: `ContentTranslationViewModel` observes the preference and
  loads transliterations with the meanings when on.
- `Features/MoreMenuFeature`: `MoreMenuWordByWordTransliteration` toggle;
  `MoreMenuViewModel.wordByWordShowsTransliteration` saves it.
- iPhone and iPad share every change.

## Tests

- `WordTextServiceTests`: `test_transliterationsOfEachWord`.
- `NoorUITests`: `testVoiceOverReadsTheTransliterationBetweenTheArabicAndTheMeaning`,
  `testTheTransliterationAddsALineUnderEachWord`.
- `QuranTranslationFeatureTests` (real `word_by_word.db`):
  `test_showsEachWordsTransliterationBetweenItAndItsMeaning`,
  `test_noTransliterationUntilTheReaderTurnsItOn`, `test_turningTransliterationOffRemovesIt`,
  `test_transliterationAloneShowsNoWords`.
- `MoreMenuFeatureTests`: `testTheTransliterationToggleStartsFromTheSavedChoice`,
  `testTurningTheTransliterationToggleOnSavesIt`.

## Validation

- **Verified:**
  - Focused `make test-no-sync TARGET=...`: MoreMenuFeatureTests `Executed 3 tests, with 0
    failures`; QuranTranslationFeatureTests `Executed 45 tests, with 0 failures`;
    WordTextServiceTests `Executed 30 tests, with 0 failures`; NoorUITests `Executed 267 tests,
    with 0 failures`.
  - Rendered 2:2 with `ImageRenderer` from a temporary test (deleted): the italic
    transliteration sits between each word and its meaning, right to left, highlight intact.
  - `make format-lint`: `0/1062 files require formatting`.
  - `make test-no-sync`: `Test Succeeded`; xcresult `totalTestCount 1399, passedTests 1399,
    failedTests 0` (was 1,390).
  - `make test-sync`: `Test Succeeded`; xcresult `totalTestCount 1905, passedTests 1905,
    failedTests 0` (was 1,896).
  - `make build-example-no-sync` and `make build-example-sync`: `Build Succeeded`.
- **Not verified:** the More menu row on device (shown only in translation mode with meanings
  on); the reader in the app with transliteration on, at large text sizes and in iPad split view;
  VoiceOver reading the Latin transliteration.

## Release

- **Commit:** cc0e776d
- **Pushed:** origin/main at cc0e776d
- **TestFlight:** build 959 (1.20.3): `Uploaded Quran iOS 1.20.3 (959) for commit
  cc0e776d0ad50aae3cb492ab5ff81dd67c8e2b02 to App Store Connect app MemQuran.` Processing and
  device install UNVERIFIED.
- **iCloud / CloudKit schema:** unchanged

## Follow-ups

- Dual-language meanings (English and Bengali together): owner decision.
- Whether word meanings and transliterations should follow the app's translation font size
  (M1.4 follow-up): owner decision.
