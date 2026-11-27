# Quran H2c practice in translation and line-page readers

- **Date:** 2026-11-27
- **Agent:** Codex / GPT-6 (implementation) + Gemini 4 Neon (verification and release)
- **Type:** feature
- **Status:** shipped
- **Related:** [H2b and build 1020](2026-11-27-h2b-practice-listen-cues-cumulative-resume.md), [H1/H2a](2026-11-27-h1-h2a-learning-store-and-practice.md)

## Context

The owner requested H2c and a review checkpoint before V2b. Base and fetched origin/main both resolved to
`73a366201b9a62970559a977161be0ee98492931`. The checkout was clean. At the owner's subsequent request,
the implementation and this handoff are committed locally before the release gates finish.

## Decisions

- Selected translations are an optional, one-ayah hint. The current ayah offers Show Meaning when translations exist. Requesting it counts once towards assistance. Check shows the Arabic even when the reader usually hides it. Hidden Arabic, word meanings, transliterations and word-study links are removed from the rendered Arabic row.
- Line-page assets provide ayah spans. Mask the printed ayah in place and show canonical peeks and progressive word cues in the practice bar. Cover the page while a required span is missing. Keep the print position and avoid invented glyph coordinates.
- Derive page turns from changes of the mask's current reciting ayah. Use the reader's existing navigation for forward, backward cumulative and resumed positions. Keep an already visible spread intact. Use the passage's Quran edition to decode existing drafts.

## Trade-offs

- Implementation and tests at the first checkpoint touched 37 files including 16 catalogs, with 299 insertions and 29 deletions. Two new string keys. One explicit dependency on the existing Localization module. No external package, capability, background task or persisted format was added.
- People memorizing with translations or a line edition benefit each session. Cross-page cumulative review is probably less frequent (UNVERIFIED). A line scan cannot locate a canonical word precisely. Rendering its cues separately costs bar space and requires exercising both reader modes.
- A separate practice screen would lose the reader's page context. Reusing the existing overlay, verified text units, highlight spans and navigation keeps the synchronous work confined to visible presentation. Device frame times, binary-size delta and native translation review are UNVERIFIED.

## Changes

- `Features/HifzPracticeFeature/Sources/HifzPracticeViewModel.swift:89` handles the meaning request and line cues. The builder initializes the existing draft store with the selected edition.
- `Features/QuranTranslationFeature/Sources/ContentTranslationViewModel.swift:466` constructs masked text from verified layout units. If the script and layout disagree it hides the whole ayah. The meaning action follows the translation builder through the reader to the same practice model.
- `Features/QuranImageFeature/Sources/ContentLineView.swift:166` uses existing projected spans and the themed practice mask. `Features/QuranContentFeature/Sources/ContentViewModel.swift:147` applies a new mask before navigating. Ayah menu offers Practice in both presentations.
- FSRS, evidence storage, backup schemas, model artifacts and audio are reused. Arabican imports the changed Localization resources via `ArabicLearning/Sources/LearningUI/QuranBridgeView.swift`. Both TestFlight lanes apply.

## Tests

- Six new owning-module tests cover hidden Arabic/word-by-word content, optional translations, Check when Arabic is normally hidden, per-ayah assisted grading, line-scan geometry and cues, and page transitions in both directions.
- Red run before implementation: `test_practiceRemovesUnrevealedArabicMeaningsAndTransliterationFromTheRow, XCTAssertFalse failed` and `XCTAssertNil failed`. `Executed 52 tests, with 2 failures (0 unexpected)` in the translation target. The focused run after implementation exercised each new test. The final wiring uses direct callbacks to avoid a SwiftUI environment invalidation warning.

## Validation

- **Git hooks & guardrails:** `git config core.hooksPath .githooks`; `make guardrails RANGE=73a36620..509fceca` -> `guardrail: ok (range 73a36620..509fceca)`.
- **Format & lint:** `make format-lint` -> `0/1257 files require formatting, 60 files skipped.` (`/tmp/quran-h2c-lint-final.log`).
- **Focused suite:** 8 modules (`AyahMenuFeatureTests`, `HifzPracticeFeatureTests`, `QuranAnnotationsTests`, `QuranContentFeatureTests`, `QuranImageFeatureTests`, `QuranTranslationFeatureTests`, `QuranViewFeatureTests`, `LocalizationTests`) -> `Test Succeeded` (`/tmp/quran-h2c-focused-final.log`).
- **Full Quran no-sync suite (`make test-no-sync`):** `passedTests: 1742`, `failedTests: 0`, `skippedTests: 0`, `result: Passed` (`Run-QuranEngine-Package-2026.11.27_11-58-47--0800.xcresult`). Model-backed tests ran (model present in `.cache/recitation-model`): `CoreMLRecitationModelTests` (`Executed 10 tests, with 0 failures (0 unexpected)`), `VerseMatcherRecitationTests` (`Executed 1 test, with 0 failures (0 unexpected)`), `WordAlignerRecitationTests` (`Executed 1 test, with 0 failures (0 unexpected)`).
- **Sync localization (`make test-sync TARGET=LocalizationTests`):** `passedTests: 53`, `failedTests: 0`, `skippedTests: 0`, `result: Passed` (`Run-QuranEngine-Package-2026.11.27_12-03-58--0800.xcresult`).
- **Full Quran sync suite (`make test-sync`):** `passedTests: 2223`, `failedTests: 0`, `skippedTests: 0`, `result: Passed` (`Run-QuranEngine-Package-2026.11.27_12-04-50--0800.xcresult`). Model-backed tests ran: `CoreMLRecitationModelTests` (`Executed 10 tests, with 0 failures (0 unexpected)`), `VerseMatcherRecitationTests` (`Executed 1 test, with 0 failures (0 unexpected)`), `WordAlignerRecitationTests` (`Executed 1 test, with 0 failures (0 unexpected)`).
- **Full Arabican suite (`make test-arabican`):** `passedTests: 117`, `failedTests: 0`, `skippedTests: 0`, `result: Passed` (`Run-ArabicLearning-Package-2026.11.27_12-10-46--0800.xcresult`).
- **App builds & pins:** `make build-example-no-sync` (`Build Succeeded`), `make build-example-sync` (`Build Succeeded`, followed by restoring tracked no-sync `Package.resolved`), `make build-arabican` (`Build Succeeded`), `bash Tools/package-pins.test.sh` (`5 passed, 0 failed`), and `make test-tools` (all suites passed, 0 failures).
- **Simulator UI verification (iPhone 18 Pro Max `C4D112D1-BB82-4A00-A6AE-9CAE1A7A7148`, iOS 27.2):** installed freshly built H2c app via `make run-example-no-sync` (`Build Succeeded`) and ran `/tmp/quran-h2c-ui/ReaderCheck.xcodeproj` with `-parallel-testing-enabled NO` (launching directly and navigating through the real More menu and Settings > Choose Mushaf UI):
  - **Light mode, Portrait & Landscape:** verified translation practice (`test1_TranslationPractice`: Arabic masked to `…`, word-by-word meanings/transliteration removed, `Show Meaning` reveals selected translations once and hides itself, `Next Word` peeks `قُلۡ`, `Check` restores full Arabic and word-by-word meanings, `Correct` advances to `112:2` and restores `Show Meaning`), translation cumulative order + kill-and-resume (`test2_TranslationCumulativeAndResume`: `firstWord` cues, Step 3 returns to `112:1`, `app.terminate()` + relaunch shows `"Picked up where you left off."`), landscape translation (`test3_LandscapeTranslation`), Madani Mushaf (1439) line-page practice + edition-aware resume (`test4_LinePagePracticeAndEditionResume`: downloaded via Settings > Choose Mushaf, printed ayahs covered by span masks without shifting sura headers/basmalas, `"Ayah masks · word cues below"` caption, `Next Word` shows `قُلۡ … … …` in bar, `Check` unmasks `112:1`, grading + `app.terminate()` + relaunch resumes at `112:2` on `hafsMadani1440` with `"Picked up where you left off."`), and landscape line-page two-page spread (`test5_LandscapeLinePage`). All assertions passed (`** TEST SUCCEEDED **`) and exported screenshots were visually inspected.
  - **Dark mode + Accessibility Extra-Large Dynamic Type (`accessibility-extra-large`):** `test1_TranslationPractice` and `test4_LinePagePracticeAndEditionResume` (`Executed 2 tests, with 0 failures (0 unexpected)`, `** TEST EXECUTE SUCCEEDED **`); exported screenshots visually inspected (dark masks, `Show Meaning`, and line-page cues render cleanly; noted AX-XL polish item under Follow-ups).
- **Not verified:** physical device behavior, VoiceOver reading order on masked translation rows and the line-page cue bar, compact-iPhone width, iPad split view, multi-page cross-boundary page turns in live simulator UI (covered by unit test `ContentViewModelTests.testPracticeTurnsForANewAyahInEitherDirectionAndLeavesAPeekOnTheSamePage`), device frame times, binary-size delta, and native review of the 2 new localized strings in the 15 non-English catalogs.

## Release

- **Commit:** `509fceca9ab9824e2c21a7d76e440f6ea58b103a` (pushed on `origin/main`).
- **TestFlight builds (both apps, build 1022):**
  - `Uploaded Quran iOS 1.20.3 (1022) for commit 509fceca9ab9824e2c21a7d76e440f6ea58b103a to App Store Connect app MemQuran.`
  - `Uploaded Arabican iOS 0.1.0 (1022) for commit 509fceca9ab9824e2c21a7d76e440f6ea58b103a to App Store Connect app Arabican.`
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Stop for the owner-review checkpoint before starting V2b.
- Minor Accessibility Extra-Large Dynamic Type polish (observed on simulator screenshots): `HifzPracticeView.swift:44` (and existing `:227`, `:238`) applies `@ScaledMetric` `wordSize` inside `.font(.custom(..., size: wordSize, relativeTo: .title3))`, double-scaling the Arabic cue line at AX4+ sizes; `Check` and `Mistakes` button labels also wrap mid-word at AX-XL.
