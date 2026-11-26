# Arabican L1: content compiler pilot, ArabicScript, LearningContent

- **Date:** 2026-11-25
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature | tooling
- **Status:** shipped
- **Related:** [2026-11-25-arabican-l0-bootstrap.md](2026-11-25-arabican-l0-bootstrap.md),
  `Documentation/ArabicLearning/03-spec-roadmap-risks.md` §5 (L1)

**App:** Arabican. Shared change to QuranEngine: `QuranKit.Word` is now `Sendable`.

## Context

Milestone L1 (spec 03 §5.2): a build-time content compiler with validation and tests, an `ArabicScript` module with
grapheme and diacritic tests, and compiled tables for letters, forms, syllables, skills, lessons and Al-Fatihah word
references. Exit gate: deterministic rebuild, malformed fixtures rejected, Al-Fatihah refs resolve to QuranKit words,
canonical text byte-identical.

## Decisions

- **Authored content is TOML** (`Tools/learning/content/letters.toml`, `curriculum.toml`), read with Python's standard
  `tomllib`: no PyYAML dependency.
- **No duplicate Quran text pipeline.** Word identities and the six regrouped ayahs come from the reader's existing
  `word_by_word.db` (`uthmani_tokens`); text comes from QuranResources' `quran.ar.uthmani.v2.db`. The compiler copies
  word tokens byte for byte; Swift tests re-read the canonical text through QuranEngine's
  `GRDBQuranVerseTextPersistence` and compare UTF-8 bytes.
- **Determinism is a content hash**, not the file hash: SHA-256 over every table's schema and rows in column order.
  SQLite stamps its library version into the file header, so file bytes can differ between machines. File bytes are
  still identical across two builds on one machine (tested). `compile.py --check` compares the committed database
  with a fresh build; the Python suite runs it.
- **Letter facts split by nature**: Unicode facts (joining, forms) live in Swift `ArabicLetter`; teaching facts (names,
  sounds, families) in `letters.toml`. The compiler mirrors the joining rule to emit `letter_form`, and
  `LearningContentStoreTests` fails if the compiled forms or letter order ever disagree with `ArabicScript`.
- **`ArabicMark` is exactly the 30 combining marks the canonical text uses** (inventory of all 6,236 ayahs). Unknown
  marks make `graphemes(of:)` return nil; a test decomposes every ayah and fails on any unknown base. Marks keep source
  order: the text stores the vowel before shadda (`رَّ` = ra, fatha, shadda), so callers compare kinds (`has(_:)`).
- **Pedagogical meaning of rare marks is UNVERIFIED** (U+0656 subscript alif, U+0657 inverted damma, U+065E fatha with
  two dots, U+065C dot below): classified as `longVowel`/`recitation` for grouping only. L4 must confirm before teaching.
- **Cut from L1, moved later** (owner: cut scope): the `stroke` table moves to L3 (tracing is its first consumer);
  `phonetic_plan` and quran-transcript move to L6 (first consumer; it also needs running third-party Python).
- **Skills are generated** from letters and contrasts (`letter.recognize.*`, `letter.sound.*`, `letter.form.*.*`,
  `sound.discriminate.*`) with generated prerequisites; lessons add `requires` edges. Validation: lessons in id order,
  requirements taught earlier, every prerequisite taught no later than its skill, no cycles, exact 29-letter alphabet
  (it caught that `ى` passed a range check), NFC authored text, units defined and used.
- **Visible slice**: the Learn tab lists units and lessons from the bundled database (`LearnViewModel`, NoorUI
  `NoorList`/`NoorSection`/`NoorListItem`/`DataUnavailableView`), so the TestFlight build proves the pipeline on device.
  Lesson titles are content (English, from TOML), not string-catalog entries; localizing content is a later decision.
- **Pinned resolution for Arabican builds** (`-onlyUsePackageVersionsFromResolvedFile` in `make test-arabican`,
  `make build-arabican` and the Arabican release archive). Without it, any `ArabicLearning/Package.swift` change made
  Xcode re-resolve the project to the newest allowed versions. The L0 commit (`ada7ef40`) shipped such drifted project
  pins (GRDB 6.29.3, swift-log 1.17.2, ...); this change restores the Quran app's pins.
- **`QuranKit.Word: Sendable`**: Swift 6 needs it to return words from database reads. `AyahNumber` is already
  `Sendable` (`Navigatable`), so the conformance is free and backward compatible.

## Trade-offs

- **Complexity added:** Python compiler, validator and tests (691 lines); 2 Swift modules
  (`ArabicScript`, `LearningContent`) and a view model + view; a committed 140 KB SQLite file and a manifest. No
  dependencies, permissions or background work. Persisted state: none (content is read-only, replaced per build).
- **Who benefits / how often:** every later milestone reads this content. The Learn list itself is a stepping stone.
- **Rejected cheaper options:** hand-written Swift data tables (no validation, no Quran cross-check); duplicating the
  canonical text into authored files (drift risk); YAML (needs a dependency).
- **Ongoing cost:** content edits need `python3 -I Tools/learning/compile.py` and a commit of the regenerated DB (the
  test fails otherwise). Arabican now links GRDB through `SQLitePersistence` (already linked through NoorUI).

## Changes

- `Tools/learning/compile.py`, `validate.py`, `compile.test.py`; `content/letters.toml`, `content/curriculum.toml`.
- `ArabicLearning/Sources/ArabicScript/`: `ArabicLetter`, `LetterForm`, `ArabicMark` (+ `Kind`), `ArabicGrapheme`,
  `ArabicScript.graphemes(of:)`.
- `ArabicLearning/Sources/LearningModel/Curriculum.swift`: `LetterInfo`, `Lesson`, `LearningUnit`, `Curriculum`,
  `QuranWordText` (reuses `QuranKit.Word` and `QuranText.QuranText`).
- `ArabicLearning/Sources/LearningContent/`: `LearningContentStore` (reuses `SQLitePersistence.DatabaseConnection`),
  `Resources/learning-content.sqlite` (+ manifest, excluded from the bundle).
- `ArabicLearning/Sources/LearningUI/`: `LearnViewModel`, `LearnView`; `ArabicanRootView(content:)`.
- `Apps/Arabican/Arabican/ArabicanApp.swift`: wires `LearningContentStore()`.
- `Model/QuranKit/Sources/Word.swift`: `Sendable`.
- `Makefile`, `Tools/lib/app-identity.sh`, `Tools/release-testflight.sh`: pinned resolution for Arabican.
- `.github/workflows/ci.yml`: compiler tests in the Guardrails job.

## Tests

- Python `Tools/learning/compile.test.py` (19): determinism (hash and bytes), committed DB is fresh, Al-Fatihah words
  byte-identical, counts and generated prerequisites, rejection of duplicate lesson ids, unknown skills, requirements no
  earlier lesson teaches, a sound taught before its letter, a cycle, lessons out of order, a variant letter (`ى`), a
  non-Arabic letter, non-NFC text, an undefined unit, an invalid sura; token mapping fixtures for one-token-per-word,
  two-words-in-one-token and one-word-in-two-tokens.
- Swift `ArabicScriptTests` (9), `LearningContentTests` (5, including all 6,236 ayahs decomposing with no unknown
  base), `LearningUITests/LearnViewModelTests` (2), `QuranKitTests/WordTests` (2).
- `release.test.sh`: Arabican resolve flags in the identity and the Makefile.

## Validation

- **Verified:**
  - `make test-arabican`: `result: Passed, totalTestCount: 23, passedTests: 23, failedTests: 0`.
  - `python3 -I Tools/learning/compile.test.py`: `Ran 19 tests ... OK`; `compile.py --check`: `ok: ... matches a fresh build`.
  - `make test-tools`: guardrails 22, release 36, icons 16, word data 46, pins 5 passed, 0 failed.
  - `make format-lint`: `0/1090 files require formatting`.
  - `make build-arabican`: `Build Succeeded`; Learn tab on the iPhone 18 Pro simulator lists "Getting started" (1 lesson)
    and "The letters" (8 lessons).
  - Quran (shared `QuranKit` change): `make test-no-sync` `result: Passed, totalTestCount: 1424, passedTests: 1424,
    failedTests: 0` (1422 before plus the 2 new `WordTests`); `make test-sync` `totalTestCount: 1918, passedTests: 1918,
    failedTests: 0`; `make build-example-no-sync` and `make build-example-sync` `Build Succeeded`.
- **Not verified:** Learn list at large Dynamic Type, Dark mode, iPad split view, VoiceOver (standard NoorUI list rows);
  pedagogical correctness of lesson grouping (needs the qualified reviewer, spec risk 11).

## Release

- **Commit:** recorded in the follow-up `docs(trail)` commit.
- **Pushed:** recorded in the follow-up commit.
- **TestFlight:** Arabican build recorded in the follow-up commit; Quran build required by the shared `QuranKit` change.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- L2: profiles, `LearningPersistence`, `LearningEngine` (DAG, mastery, FSRS via swift-fsrs), first renderers.
- L3: `stroke` table from Noorine stroke data; letter audio.
- L4: confirm the teaching meaning of U+0656, U+0657, U+065E, U+065C before using words that contain them.
