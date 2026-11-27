# Quran H4: spot tests with strict and granular scores

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** feature
- **Status:** verified
- **Related:** [2026-11-27-h3-memorization-map-and-review-queue.md](2026-11-27-h3-memorization-map-and-review-queue.md) (`AyahRangeSet`, `Quran 5`, `HifzReviewFeature`, Home Memorization section),
  [2026-11-27-h1-h2a-learning-store-and-practice.md](2026-11-27-h1-h2a-learning-store-and-practice.md) (`MO_PracticeSession`, `MO_RecallEvidence`, `MemorizationService`),
  roadmap §3, §4, §5 #12 and §6 H4 ([quran-prioritized-roadmap.md](../agents/quran-prioritized-roadmap.md))

App: **Quran** (`MemorizationService`, `HifzReviewFeature`, `HomeFeature`, `NoorUI`, `Localization`).
Arabican imports `NoorUI` and `Localization`, so it must be tested, built, and released too; Arabican's features do not change.

## Context

Roadmap §5 #12 and §6 H4: "Sources: memorized ranges, custom ranges, presets (Warm up, Weakest, Due, Recent, Old). Random start with seeded sampler, question length in ayahs or lines, count or timer, start cue, hidden location option. Manual reveal and grade; hint and skip recorded. Scores: strict (error-free unassisted questions), word recall, coverage, assistance; no score when the denominator is zero. Temporary tests never change history."

This session implemented H4 end-to-end and verified focused unit/feature/localization tests plus simulator UI checks across Light, Landscape, and Dark + AX-XL. The implementation session reached its quota before full verification. The follow-up verified the pushed feature commit and recorded the TestFlight attempts below.

## Decisions

- **No Core Data schema change.** Non-temporary spot test questions record directly into existing `MO_PracticeSession` and `MO_RecallEvidence` (via `MemorizationService.recordSpotTest` → `recordSession`), keeping Backup schema 3 and CloudKit compatibility untouched. Skipped questions record `.skipped` per-verse evidence (recorded in history without changing FSRS intervals because `EvidenceReducer.grade` returns `nil` when all verses are `.skipped`).
- **Temporary tests strictly isolated.** When `isTemporary == true`, `MemorizationService.recordSpotTest` returns `[]` without touching persistence, verified by unit tests comparing `persistence.history()` before and after.
- **Deterministic seeded sampler (`SpotTestRNG` SplitMix64 + `SpotTestSampler`).** Questions stay within contiguous pool blocks (never bridging gaps across non-contiguous custom ranges), prefer non-overlapping spans first, fall back to distinct start verses on small pools, and support replay with the exact same seed.
- **Mushaf line length via real `ayahinfo_1920.db` geometry with pure fallback.** `SpotTestTextLoader` reads exact `(page, firstLine, lastLine)` spans from `GRDBWordFramePersistence` for `Reading.hafs_1405` off the main actor; `SpotTestSampler` stays free of GRDB by taking `[AyahNumber: VerseLineSpan]` and falls back to 15-lines-per-page estimation when geometry is absent.
- **Zero-denominator safety enforced in the type system (`SpotTestRatio?`).** `SpotTestRatio.init?(numerator:denominator:)` returns `nil` when `denominator <= 0`, so `strictScore`, `wordRecallScore`, `coverageScore`, and `assistanceRate` are `nil` (rendered as `"—"`) whenever their denominator is zero.
- **Preset definitions (`MemorizationService.spotTestPool`):**
  - `warmUp`: `.strong` passages (falls back to all memorized/practiced if none strong yet).
  - `weakest`: `.weak` passages plus `.learning` passages whose `lastGrade != .good` (so a single clean first-time session isn't misclassified as weak; falls back to `.learning` only if none genuinely weak).
  - `due`: `reviewQueue().dueItems`.
  - `recent`: passages practiced or declared within 14 days (fallback: newest half).
  - `old`: passages older than 14 days since last activity (fallback: oldest half).
- **Hidden location safety.** When `hideLocation == true` and `startCue == .referenceOnly`, `SpotTestConfiguration.effectiveStartCue` falls back to `.firstWord` so a question never starts blank. Hidden words are omitted from the SwiftUI view hierarchy while reciting so VoiceOver never reads them.
- **UI hosted inside `HifzReviewFeature` + Home entry.** Avoids creating another small feature module and keeps `RecitationRecognition` out of `HomeFeature`. Accessible in one tap from Home → Memorization → `Spot Test` and from `HifzReviewView`'s toolbar.

## Trade-offs

- **Complexity added:** 3 new domain files in `Domain/MemorizationService` (`SpotTestModels.swift`, `SpotTestSampler.swift`, `SpotTestScorer.swift`) + ~160 lines in `MemorizationService.swift`; 3 new UI files in `Features/HifzReviewFeature` (`SpotTestTextLoader.swift`, `SpotTestViewModel.swift`, `SpotTestView.swift`); Home entry (~20 lines); 1 new `NoorSystemImage` case (`spotTest`) + 3 aliases; 73 localization keys × 16 catalogs (agent translations). No new third-party dependency, Core Data schema change, permission, entitlement, or background work.
- **Who benefits / how often:** learners preparing for Hifz revision exams; likely a minority of overall Quran readers (UNVERIFIED, no analytics). Timed mode, custom page ranges, and hidden-location mode are the pieces most likely to be rarely used (UNVERIFIED), though each is small and shares the same core engine.
- **Rejected cheaper options:** creating a separate `HifzSpotTestFeature` target (extra `Package.swift` target boilerplate without isolating any heavy dependency like Core ML); approximating lines only by ayah counts (inaccurate on short vs long ayahs when `ayahinfo_1920.db` is already bundled); hard-coding `0%` on empty denominators (violates spec and misleads users).
- **Ongoing cost:** 73 more strings in 16 catalogs (agent translations, native review UNVERIFIED); `SpotTestTextLoader.loadLineSpans` reads touched pages from `ayahinfo_1920.db` only when `.lines` mode is chosen (runs off the main actor).

## Changes

- `Domain/MemorizationService/Sources/SpotTestModels.swift` (new): source, presets, length, limit, start cue, configuration, verse/question results.
- `Domain/MemorizationService/Sources/SpotTestSampler.swift` (new): SplitMix64 `SpotTestRNG`, `SpotTestSampler` (ayah & line spans, non-overlapping preference, non-contiguous safety).
- `Domain/MemorizationService/Sources/SpotTestScorer.swift` (new): `SpotTestRatio?`, `SpotTestScoreReport`, `SpotTestScorer` (strict, word recall, coverage, assistance, best streak, skipped).
- `Domain/MemorizationService/Sources/MemorizationService.swift`: `spotTestPool(for:calendar:)`, `generateSpotTest(configuration:lineSpans:calendar:)`, `recordSpotTest(_:startedOn:isTemporary:)`.
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: `case spotTest = "checklist"` and aliases `spotTestTimer`, `hideLocation`, `replayTest`.
- `Features/HifzReviewFeature/Sources/SpotTestTextLoader.swift` (new), `SpotTestViewModel.swift` (new), `SpotTestView.swift` (new), `HifzReviewBuilder.swift`, `HifzReviewView.swift`, `HifzReviewViewModel.swift`.
- `Features/HomeFeature/Sources/HomeView.swift`, `HomeViewModel.swift`, `HomeViewController.swift`: Home Memorization section → `Spot Test` entry.
- `Package.swift`: added `NoorFont`, `QuranGeometry`, `QuranText`, `VerseTextPersistence`, `WordFramePersistence`, `WordTextService` (and test deps `QuranResources`, `TestResources`) to `HifzReviewFeature`.
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: 73 `hifz_test.*` keys in all 16 catalogs.
- Docs: `Documentation/agents/quran-roadmap-progress.md`, `Documentation/agents/quran-prioritized-roadmap.md`, `Documentation/agents/feature-cost-register.md`, `Documentation/trail/README.md`.
- Platforms: iPhone and iPad (one universal target); no platform conditionals.

## Tests

- `Domain/MemorizationService/Tests/SpotTestTests.swift` (8 tests): deterministic seeded sampling & non-contiguous range safety, small/empty pools, line-length sampling with geometry & fallback, hidden-location cue fallback, zero-denominator `nil` ratios, strict/word-recall/coverage/assistance/streak math, all 5 presets (`warmUp`, `weakest`, `due`, `recent`, `old`), temporary-test history isolation vs saved hints/word-mistakes/skips.
- `Features/HifzReviewFeature/Tests/SpotTestViewModelTests.swift` (3 tests): full end-to-end Spot Test with real Uthmani & `word_by_word.db` (hints, mistaken word selection, skip, scores, persistence, Practice/Reader hooks), temporary-test isolation + same-seed replay + hidden location, timed test auto-finish + real `hafs_1405_ayahinfo.db` line sampling + zero-denominator results.
- Regression caught during simulator inspection: fixed missing localization key `hifz_practice.reveal_word` → `hifz_practice.next_word`, added single-line button scaling on the 3 assist buttons, and stacked the question-card header vertically at AX-XL so the length badge never squeezes out.

## Validation

- **Verified:**
  - `make format-lint`: `0/1280 files require formatting, 63 files skipped.` (before the final 8-line AX-XL header edit in `SpotTestView.swift`; re-run `make format-lint` in next session).
  - `make test-no-sync TARGET=MemorizationServiceTests`: `Executed 39 tests, with 0 failures (0 unexpected)` (`SpotTestTests`: 8/8 passed).
  - `make test-no-sync TARGET=HifzReviewFeatureTests`: `Executed 7 tests, with 0 failures (0 unexpected)` (`SpotTestViewModelTests`: 3/3 passed).
  - `make test-no-sync TARGET=LocalizationTests`: `Executed 53 tests, with 0 failures (0 unexpected)`.
  - `make run-example-no-sync`: `Build Succeeded`, installed and launched on iPhone 18 Pro Max (`C4D112D1-BB82-4A00-A6AE-9CAE1A7A7148`, iOS 27.2).
  - Live simulator end-to-end UI checks (`** TEST SUCCEEDED **` in Light + Large, Landscape, and Dark + AX-XL): Home Memorization → Spot Test Setup (presets with live counts, Memorized/Custom, Ayahs/Lines, Questions/Timer, Start Cue, Hide Surah & Ayah, Temporary Test) → Active Question (First Letter, Next Word, Skip, Reveal & Grade, RTL Uthmani Mistake word chips) → Score Report (Strict Score, Word Recall, Coverage, Assistance, Streak, Skipped, Question Breakdown, Replay, New Spot Test). Left simulator in Light mode, Large text.
- **Follow-up verification of `699cda6c` (2026-11-27, Codex):**
  - `make format-lint`: `0/1280 files require formatting, 64 files skipped.`
  - `make test-no-sync`: `Test Succeeded`. Result bundle reports 1,787 passed, 0 failures, 0 skips.
  - `make test-sync`: `Test Succeeded`. Result bundle reports 2,268 passed, 0 failures, 0 skips.
  - `make test-arabican`: `Test Succeeded`. Result bundle reports 117 passed, 0 failures, 0 skips.
  - `make test-tools`: exit 0. All tool suites completed, including guardrails (`22 passed, 0 failed`) and release (`43 passed, 0 failed`).
  - `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: each reported `Build Succeeded`.
    Restored the sync-generated `Package.resolved` and verified the tree matched `HEAD`.
  - `make guardrails RANGE=HEAD^..HEAD`: `guardrail: ok (range HEAD^..HEAD)`.
- **Not verified:**
  - Physical device checks: VoiceOver on hidden-location prompts and word chips, iPad split view, compact-iPhone width, native review of 73 non-English strings.

## Release

- **Commit:** `699cda6cf2c6255176b57ca900bd9e0af8eb4e1b`.
- **Pushed:** `origin/main` at `699cda6c`.
- **TestFlight:**
  - Quran 1.20.3 (1027) archived. App Store Connect rejected the export because
    `The bundle version must be higher than the previously uploaded version: ‘1027’`.
    Retry from the verification record commit so the release script assigns a new build number.
  - `Uploaded Arabican iOS 0.1.0 (1027) for commit 699cda6cf2c6255176b57ca900bd9e0af8eb4e1b to App Store Connect app Arabican.`
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

1. Retry the pending TestFlight lanes from the verification record commit. After both upload receipts
   are available, mark V2b, H3, and H4 shipped in the trails, roadmap spec, and progress doc.
2. **Next milestone:** H5, Similar verses and confusion drills (roadmap §6).
