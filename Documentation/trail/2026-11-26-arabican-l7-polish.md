# Arabican L7: progressive substitution, Bengali meanings, release gate

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-26-arabican-l6-tajweed-foundations.md](2026-11-26-arabican-l6-tajweed-foundations.md),
  [2026-11-26-one-simulator-iphone-18-pro-max.md](2026-11-26-one-simulator-iphone-18-pro-max.md)

## Context

App: **Arabican** only (`ArabicLearning/`; no QuranEngine module changed). Milestone L7 "Polish &
release gate" (`Documentation/ArabicLearning/03-spec-roadmap-risks.md` §5.2). The handoff asked to
check scope with the owner first. Owner answers (2026-11-26): build **progressive substitution**
and the **meaning language (EN/BN)**; **cut** profile export/import and the attribution screen;
treat the reviewer-dependent release blockers (risks 2, 6, 11) as **accepted open risks** for
personal use. The accessibility pass and performance budgets were in scope regardless.

## Decisions

- **Progressive substitution** (inventory #19, ayyat's idea, reimplemented): the reader's new
  "In a line, known words in Arabic" mode shows each ayah's meaning word by word in reading order,
  and a word whose **every lemma** (prefixes such as بِ and وَ included; pronoun suffixes have none)
  has a **mastered** `lemma.meaning.<lemma>` skill appears in Arabic instead. Mastery decays, so a
  word can return to its meaning. Not copied from ayyat: its score, lemma override and
  pre-graduation cap (more code; our mastery state already gates it). Default mode stays "Under
  each word"; the choice is a per-device `@AppStorage` preference like a text size.
- Adjacent known words form **one** Arabic run (`MeaningPiece.arabic`), so they read right to left
  in their own order inside the left-to-right line. Seen in the simulator before the fix: 1:2
  showed لِلَّهِ left of رَبِّ, which an Arabic reader reads backwards.
- The key above the line counts known words ("8 of 29 words in this sura"), never a share of the
  Quran (risk 8).
- **Meaning language** is a profile setting (`LearnerProfile.meaningLanguage`, Progress tab,
  "Meanings in"): reader glosses, the word sheet's order and lemma gloss, and the options of
  `bridge.meaning.*` and `lemma.meaning.*` exercises. Every bridge word and top-300 lemma has a
  Bengali meaning (153/153, 300/300 checked with sqlite3), so no content change. The app UI stays
  English; language names are Foundation endonyms (`Locale.localizedString(forLanguageCode:)`).
- Changing the language rebuilds the profile's screens (an in-progress practice session restarts).
- The Quran tab's view model moved into the per-profile `Session` (it now needs the profile's
  progress and language).
- **Release gate:** risks 2, 6 and 11 accepted by the owner as open (review pending, features stay
  enabled); 1, 9, 10 closed with evidence (spec §6).

## Trade-offs

- **Complexity added:** 2 source files (`MeaningLanguage`, `ProgressiveSubstitution`), changes in
  10; source 43 files / 5,008 lines (L6: 41 / 4,761). Persisted state: one column
  `profile.meaning_language` (migration "v2 meaning language", default 'english'). No dependency,
  permission or entitlement.
- **Who benefits / how often:** the meaning line pays off only after vocabulary lessons are
  mastered (at least 4 correct answers per lemma); before that it shows only meanings. Likely
  **rarely used** until a learner reaches U10; it costs ~80 lines. Bengali benefits a Bengali reader
  every session; otherwise unused (~60 lines).
- **Rejected cheaper options:** hiding known words' glosses under each word (simpler, but not the
  substitution idea and gives no reading line); a whole-sentence translation (no translation data
  in Arabican; word meanings are what we have and are verified); localizing the UI to Bengali
  (owner asked for meanings only).
- **Ongoing cost:** none at launch; the reader reads evidence once per appearance (1 ms).

## Changes

- `LearningModel/MeaningLanguage.swift` (new); `LearnerProfile.meaningLanguage`.
- `LearningPersistence/ProfileStore.swift`: migration v2, `setMeaningLanguage(_:for:)`.
- `LearningEngine/ProgressiveSubstitution.swift` (new): `skill(for:)`, `knownWords(segments:evidence:)`.
- `ExerciseKit`: `ExerciseGenerator(meaningLanguage:)`; `meaningInAyah`, `meaningOfLemma` use it.
- `LearningUI`: `BridgeViewModel(content:progress:meaningLanguage:)`, `BridgeReaderViewModel.load()`,
  `knownWords`, `meaning(_:)`, `meaningLine(_:)`; `QuranBridgeView` meaning line, overflow-menu
  picker (inline), key; `WordSheet` language order; `LearnerProgressView` "Meanings in" picker;
  `ArabicanRootViewModel.setMeaningLanguage(_:)`, `Session.bridge`; `PracticeViewModel` passes the
  language. 7 strings added, 2 unused removed (`bridge.word.english`, `bridge.word.bengali`).
- Reused: `NoorSystemImage.translation` (globe), `WrappingHStack`, `NumberFormatter.shared`, NoorList.

## Tests

117 package tests (L6: 107). New: `ProgressiveSubstitutionTests` (3: every lemma must be mastered;
practicing is not knowing, words outside the vocabulary stay glossed; skill id),
`BridgeExerciseTests.test_bengaliProfileGetsBengaliMeaningsForEveryBridgeSuraAndLemma`,
`LearningPersistenceTests.test_meaningLanguageDefaultsToEnglishAndPersistsPerProfile`,
`test_aVersionOneProfilesFileMigratesToEnglishMeanings` (a v1 profiles file keeps its profile and
reads English), `BridgeViewModelTests.test_readerShowsWordsWhoseLemmasAreMasteredInArabic...`,
`test_meaningLineJoinsAdjacentKnownWordsIntoOneArabicRun` (regression for the reversed run: written
after the simulator showed the bug; before the fix the per-word rendering had no grouping, so the
test's expected single `.arabic` piece for 1:2 words 2–3 could not hold — reasoned from the diff),
`PerformanceBudgetTests` (2).

## Validation

- **Verified:** `make format-lint`: `0/1140 files require formatting`. `make test-arabican`
  (iPhone 18 Pro Max): xcresult `{'result': 'Passed', 'totalTestCount': 117, 'passedTests': 117,
  'failedTests': 0}`, `Test Succeeded`. `make build-arabican`: `Build Succeeded`.
  `make test-tools`: all suites OK (`43 passed, 0 failed`, `ℹ pass 8`, ...).
  Simulator (iPhone 18 Pro Max, iOS 27.2), with 60 top lemmas seeded as mastered: meaning line on
  Al-Fatihah ("8 of 29 words"), Bengali reader and Bengali meaning exercise, Dark Mode at
  accessibility-large text, landscape, the overflow menu, the Progress "Meanings in" row, the bridge
  listening prompt. Performance (simulator): practice start 37 ms, Quran list 3 ms, reader 1 ms;
  budgets 0.5 s / 0.25 s / 0.1 s in `PerformanceBudgetTests`. Debug app 69 MB (bundled recitation
  3.3 MB, letter audio 1.7 MB, content DB 768 KB).
- **Not verified:** VoiceOver (labels and combined elements read in code only; VoiceOver not run);
  compact iPhone and iPad layouts (one simulator only, AGENTS.md "Simulator"); tajweed prompts in
  the full practice flow; launch time and memory with Instruments; anything on a device (audio,
  recording, tracing by finger); the inline Arabic in the meaning line sits low next to Latin text
  at accessibility sizes (readable, not polished).

## Release

- **Commit:** see `git log` (`feat(arabican): L7 ...`).
- **Pushed:** origin/main.
- **TestFlight:** recorded in a follow-up `docs(trail)` commit.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Qualified review of letter audio, lessons, glosses and tajweed (risks 2, 6, 11: accepted open).
- Iqlab, meem idgham, meem ikhfa and soft madd: need a sura with examples, recitation and timings.
- Interleave vocabulary with U4–U7; optional tracing for learners who cannot trace (u3.check).
- VoiceOver walk-through and an iPad check, if the owner allows another simulator or a device.
- R1 recognition research needs a consented test set (owner).
