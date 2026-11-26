# Arabican L2: profiles, learner store, engine core, practice

- **Date:** 2026-11-25
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-25-arabican-l1-content-compiler.md](2026-11-25-arabican-l1-content-compiler.md),
  `Documentation/ArabicLearning/03-spec-roadmap-risks.md` §5 (L2)

**App:** Arabican only. No QuranEngine file changed.

## Context

Milestone L2 (spec 03 §5.2): local profiles, `LearningPersistence` (GRDB, migrations), `LearningEngine` (DAG, mastery
states including uncertain, FSRS bridge, session planner), `PresentationProfile`, and renderers. Exit gate: profile
isolation tests, progress survives kill/relaunch, deterministic generator fixtures, VoiceOver/Dynamic Type smoke check.

## Decisions

- **FSRS:** `open-spaced-repetition/swift-fsrs` pinned `exact: "6.0.0"` (latest tag, `git ls-remote --tags`), the owner
  having delegated the choice. API read from its source at `v6.0.0` (`Sources/FSRS/Algorithm/FSRS.swift:141`
  `next(card:now:grade:)`, `Models/FSRSModels.swift:114` `Card: Codable`) before use. Fuzz off for determinism. Correct
  maps to `good`, incorrect to `again`; unscorable attempts do not touch the card. Only `letter.*` and `lemma.*` skills
  are scheduled.
- **Learner data does not use QuranEngine's `DatabaseConnection`.** Its error path deletes the database file on
  `SQLITE_PERM`, `SQLITE_NOTADB`, `SQLITE_CORRUPT` and `SQLITE_CANTOPEN`
  (`Data/SQLitePersistence/Sources/DatabaseConnection.swift:162-178`), which is right for re-downloadable data but would
  erase a learner's progress (for example a file-protection `CANTOPEN` while the device is locked). `ProfileStore` and
  `ProgressStore` use GRDB `DatabaseQueue` and `DatabaseMigrator` directly and surface errors. The read-only content DB
  keeps using `DatabaseConnection` (it lives in the bundle, which cannot be deleted).
- **One progress file per profile** (`Application Support/Arabican/progress-<uuid>.sqlite`) plus `profiles.sqlite` for the
  list and the active profile: isolation by construction, deleting a profile deletes one file, export later is a copy.
- **Mastery:** decayed Beta evidence (half-life 30 days); mastered at ≥ 3.5 recent scored attempts and posterior mean
  ≥ 0.8; `uncertain` when only unscorable attempts exist; skipping is unscorable, never wrong. Thresholds are first
  estimates (UNVERIFIED with learners). Orientation skills are explanations: one "continue" masters them
  (`MasteryPolicy.explanation`); without this, U2 could never unlock (found while writing the tests).
- **Planner:** due reviews (up to half the cap), weakest unlocked practiced skills (a quarter), then the next lesson's
  unmastered skills, twice for recall skills. Cap = 2 × the profile's items per step (child 12, adult 20).
- **Renderers:** choice, match and explanation. **Listen-choose moves to L3**, which brings the first letter audio; a
  listening exercise without audio would be fake. Sound exercises use transliteration until then.
- **Arabic glyphs use the Quran font** (`NoorFont` `uthmanicHafs`, Dynamic Type relative), registered at launch through
  `ArabicanRootView.registerFonts()`, as AGENTS.md requires. The OFL teaching fonts (inventory #6) are not added: they
  would be downloaded binaries, and the Quran font teaches the shapes learners will read.
- Exercise prompts are structured (`ExercisePrompt`); the UI builds localized sentences from the string catalog.

## Trade-offs

- **Complexity added:** 3 modules (`LearningEngine`, `ExerciseKit`, `LearningPersistence`), 6 UI files; ArabicLearning
  is now 26 source files, 2,146 lines, 11 test files. One dependency (swift-fsrs, MIT, no transitive deps, Arabican only).
  Persisted user data: two GRDB schemas with v1 migrations. No permissions or entitlements.
- **Who benefits / how often:** every Arabican session. Profiles beyond one per device are likely rare (families); the
  cost is one table and one file per profile.
- **Rejected cheaper options:** an in-house FSRS port (owner delegated; the reference implementation avoids subtle
  scheduling bugs); one shared progress DB with a profile column (weaker isolation, harder delete/export);
  `UserDefaults` for progress (no transactions, no migrations).
- **Ongoing cost:** FSRS upgrades need an explicit pin bump; the progress schema is user data, so every change needs a
  migration and a regression test.

## Changes

- `ArabicLearning/Package.swift`: products and targets `LearningEngine`, `ExerciseKit`, `LearningPersistence`;
  dependencies swift-fsrs 6.0.0 and GRDB (same requirement and pin as QuranEngine); `NoorFont`, `Localization` for UI.
- `ArabicLearning/Package.resolved`, the Arabican project's resolved file: + swift-fsrs; shared pins unchanged.
- `LearningModel/LearnerProfile.swift`. `LearningEngine/`: `Mastery.swift` (`AttemptOutcome`, `MasteryState`,
  `SkillEvidence`, `MasteryPolicy`), `SkillGraph.swift`, `ReviewScheduler.swift`, `SessionPlanner.swift`.
- `ExerciseKit/`: `Exercise.swift` (`ExercisePrompt`, `Exercise`, `ExerciseResponse`, `ExerciseGrader`),
  `ExerciseGenerator.swift` (`SeededRandom` SplitMix64, FNV-1a skill hashing).
- `LearningPersistence/`: `ProfileStore.swift`, `ProgressStore.swift`.
- `LearningContent/LearningContentStore.swift`: `skillTitles()`.
- `LearningUI/`: `ArabicanRootViewModel`, `ArabicanRootView` (profile gate, tabs, font registration),
  `ProfileSetupView`, `PracticeViewModel`, `PracticeView` (+ `ExerciseView`), `ProgressViewModel`,
  `LearnerProgressView`; strings in `Localizable.xcstrings`.
- `Apps/Arabican/Arabican/ArabicanApp.swift`: opens `ProfileStore` in Application Support; registers fonts.

## Tests

- `LearningEngineTests` (10): uncertain-not-wrong, mastery threshold, decay, explanation mastery, unlocking, planner
  order and determinism, fresh-learner plan, FSRS due dates and lapses, determinism, scheduled-skill filter.
- `ExerciseKitTests` (7): family distractors, seed determinism, a pinned seed fixture, every taught skill has an exercise,
  per-pair match grading, skip is unscorable, orientation explanation.
- `LearningPersistenceTests` (4): active profile survives reopening, profile isolation, progress survives reopening the
  file (kill/relaunch), deleting a profile removes its file.
- `LearningUITests/PracticeViewModelTests` (5): first session is orientation, all-correct session records every attempt,
  finishing orientation unlocks the letters with a match exercise, skipping records unscorable, child sessions shorter.
- The planner test was first written without the second round; it failed on the new behavior and was updated to it.

## Validation

- **Verified:**
  - `make test-arabican`: `result: Passed, totalTestCount: 49, passedTests: 49, failedTests: 0`.
  - `make test-tools`: compiler `Ran 19 tests ... OK`; guardrails 22, release 36, icons 16, word data 46, pins 5 passed.
  - `make format-lint`: `0/1109 files require formatting`.
  - `make build-arabican`: `Build Succeeded`. On the iPhone 18 Pro simulator: created profile "Sam" (adult), completed
    the two orientation explanations ("2 of 2 answers correct."), the next session opened "Which letter is alif?" with
    four Quran-font letters; after `simctl terminate` and relaunch the app went straight to Sam's tabs and Progress
    showed "Getting started: 2 of 2 skills mastered" and "The letters: 0 of 65 skills mastered".
  - Quran suites not run: no QuranEngine path changed (AGENTS.md "Two apps", rule 4).
- **Not verified:** VoiceOver and large Dynamic Type on the practice and match screens (spec L2 asks for a smoke check;
  not done this session); iPad layout; Dark mode; child-profile layout; match exercise by hand (covered by unit tests).

## Release

- **Commit:** `d0e73d4e0c7f07bc032507a87356c7dbacac9df6`
- **Pushed:** origin/main at `d0e73d4e`.
- **TestFlight:** Arabican build **967** (0.1.0): `Uploaded Arabican iOS 0.1.0 (967) for commit
  d0e73d4e0c7f07bc032507a87356c7dbacac9df6 to App Store Connect app Arabican.` No Quran build (Quran binary unchanged).
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- VoiceOver / Dynamic Type smoke check of Practice and Progress (L2 exit gate item left open).
- L3: letter audio (Antura audition), listen-choose renderer, tracing (Noorine strokes, `stroke` table).
- Profile rename and delete UI (store supports delete; no UI yet).
- Quran app: `DatabaseConnection` deletes files on `CANTOPEN` and similar; check whether any user-data store in the
  Quran app (for example `GRDBSyncedPageBookmarkPersistence`, `GRDBActiveTranslationsPersistence`) is exposed.
