# Quran H2c practice in translation and line-page readers

- **Date:** 2026-11-27
- **Agent:** Codex / GPT-6
- **Type:** feature
- **Status:** in-progress
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

- Hooks installed, `git config core.hooksPath .githooks`. Final lint: `0/1257 files require formatting, 60 files skipped.` First focused run: `Test Succeeded` in `/tmp/quran-h2c-focused.log`. Final rerun and full-suite/build results are recorded as they become available.
- **Resume without duplicating work.** On this Mac, the sequential command `bash /tmp/quran-h2c-validate.sh` runs under Codex exec session 42066. Inspect `ls -lt /tmp/quran-h2c-*.log` and the last log before starting any simulator test. The script exits on the first failure. In order it runs final lint, the eight focused modules together, full Quran no-sync, sync Localization, full Quran sync, Arabican, both Quran builds, restores the tracked no-sync Package.resolved, builds Arabican, and runs the pin test. Use xcresulttool summaries and verify CoreMLRecitationModelTests actually ran. The simulator UDID is C4D112D1-BB82-4A00-A6AE-9CAE1A7A7148. The model is present in .cache/recitation-model. Xcode package commands require sandbox escalation on this machine, or xcodebuild can misleadingly report there is no package.
- **UI verification still pending at first checkpoint.** A temporary XCUITest project at `/tmp/quran-h2c-ui/ReaderCheck.xcodeproj` compiled (`** TEST BUILD SUCCEEDED **` in `/tmp/quran-h2c-ui-compile.log`). Install the updated Quran simulator build first. The tests open 112:1, long press, start Practice, request meaning or peek, check and exit, and attach screenshots. Run with parallel testing disabled on the designated simulator only, inspect attachments and repeat in Dark mode and large Dynamic Type. Physical device, VoiceOver, compact width and iPad split view UNVERIFIED.

## Release

- **Commit:** local branch `codex/quran-h2c`. Find the implementation with `git log -1 --format=%H -- Features/HifzPracticeFeature`.
- **Pushed / TestFlight:** pending at first checkpoint. Build 1020 belongs to H2b. Do not report it for H2c. After verification, push HEAD:main, release Quran and Arabican, then record exact upload lines in a follow-up trail commit.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

Finish remaining checks and close the H2c tracker entry with the release identifiers. Stop for owner review before starting V2b.
