# Quran H7 + V3b: mistake history heatmap, recite-and-check model evidence, detail sheet and repair queue

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** feature
- **Status:** verified
- **Related:** [2026-11-27-h1-h2a-learning-store-and-practice.md](2026-11-27-h1-h2a-learning-store-and-practice.md),
  [2026-11-27-h3-memorization-map-and-review-queue.md](2026-11-27-h3-memorization-map-and-review-queue.md),
  [2026-11-27-h5-similar-verses.md](2026-11-27-h5-similar-verses.md),
  [2026-11-27-v3a-recite-and-check.md](2026-11-27-v3a-recite-and-check.md),
  [2026-11-27-quran-roadmap-v5-order.md](2026-11-27-quran-roadmap-v5-order.md) (items 15–17 of roadmap §5)

## Context

App: **Quran** (with shared `Localization`, `QuranAnnotations`, and `NoorUI` changes, so **Arabican** is also tested, built, and eligible for release per AGENTS.md rule 5).

The owner asked to continue the Quran roadmap from `Documentation/agents/quran-roadmap-progress.md` starting at the first item under Next steps: **H7 foundation → V3b → H7 completion**:
- **H7 foundation:** word and ayah mistake history reducer with an explicit, tested decay policy (one count per word per session) over H1 `RecallEvidence` and H5 confusion drills, reader heatmap overlay that never mixes with tajweed or similar-verse markers, and a detail sheet (history, confirm, dispute, remove, note).
- **V3b:** V3a Recite-to-Check confirmed mistakes recorded as `.model` `RecallEvidence` with model provenance feeding H7's heatmap, inline dispute that immediately recomputes, and a silent policy that records without showing mistakes.
- **H7 completion:** repair queue drilling weak passages (never isolated words) through H2 Practice.

## Decisions

- **No Core Data or Backup schema bump required.** Existing `Quran 5` `MO_PracticeSession` and `MO_RecallEvidence` already store `sessionID`, `sura`, `ayah`, `word` (`0` = whole ayah, `> 0` = canonical QUL word), `outcome`, `assistance`, `provenance` (`.manual` / `.model`), `recordedOn`, and append-only `retractedOn`. Derived heatmaps and repair queues are computed purely from evidence on demand, staying CloudKit-compatible for P1.
- **Explicit, deterministic decay policy (`MistakeDecayPolicy`):**
  - Each mistake (`.mistake` or `.revealed`) starts at weight `1.0`, counted **at most once per `(sessionID, verse, word)`** (and at most once per session for an ayah's overall session score).
  - Subsequent **clean, unassisted** recalls (`.correct` with `assistance == 0`, no mistake on that verse in that session) multiply remaining heat by `cleanRecallRetention = 0.5`. Assisted recalls (`.hint` or `assistance > 0`) neither add heat nor decay prior mistakes.
  - Time decays gently with `halfLifeDays = 60.0` (`pow(0.5, ageDays / 60)`).
  - Discrete tiers: `minimumHeat = 0.25` (clears after 3 clean recalls: `0.125 < 0.25`, or ~120 days), `mediumThreshold = 0.75`, `highThreshold = 1.75` (high for repeated mistakes across sessions). Using `0.75` / `1.75` rather than `1.0` / `2.0` prevents a mistake from dropping tiers 1 second after recording due to continuous exponential time decay (caught by `MistakeHistoryTests`).
- **Confirming and disputing/removing append-only:**
  - `MemorizationService.confirmMistake(_:)` retracts the `.model` evidence IDs and writes a `.manual` `RecallEvidenceRecord` in the same `sessionID` with the original `recordedOn`, preserving one-count-per-word-per-session and backup/sync idempotency.
  - `MemorizationService.retractMistake(_:)` (and V3b inline `RecitationCheckViewModel.dispute(_:)`) retracts the word's evidence IDs, and when disputing/removing the **last** active word mistake in a verse within that session, also retracts the companion ayah-level (`word == 0`) `.mistake` record so the verse clears completely from the heatmap and repair queue.
- **Heatmap overlay mutual exclusion & rendering:**
  - Controlled by `QuranContentStatePreferences.shared.showMistakeHeatmap` (default `false`) via the reader's More menu (`MoreMenuMistakeHeatmap`).
  - **Never mixes with Tajweed Mushaf or H2 Practice:** hidden in the More menu and suppressed at two layers (`QuranInteractor.refreshMistakeHistory()` and `ContentImageViewModel`/`ContentLineViewModel`) when `reading == .tajweed && quranMode == .arabic`, and suppressed whenever `VerseOverlays.practiceMask != nil`.
  - Word-level mistakes pinpoint the exact words with translucent tint plus a bottom accent bar (`ImageDecorationsView`, `QuranWordByWordText`) and `QuranArabicText` token highlights; ayah-level-only mistakes (Forgot, skipped verse, H5 confusion drill) tint the ayah softly underneath user highlights/playback/selection. Line-page Mushaf renders ayah-level heat via `versesByHighlights(includeAllHeatmapVerses: true)`.
- **Mistake Detail sheet (`MistakeDetailView`):**
  - Opened from the Ayah Menu (`Mistake History`, shown for a single selected ayah when the heatmap is active or the ayah has history) and from weak-ayah chips inside the H7 Repair Queue.
  - Displays the ayah in Quran font via `QuranMarkedText`, heat level badge (color + text label), decay summary, active mistakes (Confirm/Dispute for `.model`, Remove for `.manual`), retracted history, Practice Passage launch, and the existing reader Note Editor (`Ayah Note`) instead of duplicating note storage.
- **V3b Recite-to-Check integration (`RecitationCheckViewModel`):**
  - `RecitationCheckViewModel.recalls(from:)` converts only reached verses: skipped verses → ayah `.mistake` (`.model`), omitted/substituted words → `.mistake` with exact canonical word numbers (`.model`), uncertain/partial verses → `.skipped` (never recorded as a mistake and never falsely decaying heat), fully correct verses → `.correct` (`.model`), unreached verses → omitted.
  - Adds `RecitationCheckPolicy` (`.showMistakes` vs `.silent`). In `.silent` mode, confirmed mistakes are recorded quietly to H7 history without displaying red mistake marks during the check; in `.showMistakes` mode, each confirmed mistake row has an inline **Dispute** button that retracts its `.model` evidence and immediately recomputes H7's heatmap.
- **H7 Repair Queue (`HifzReviewView` Repair tab + Home row):**
  - `MistakeHistoryReducer.repairQueue` resolves every hot verse to a full hafiz-sized passage (active `PassageRecord` → most recent multi-ayah practiced passage → `PassageSplitter.defaultPassages` sura-on-page chunk), never isolated single words.
  - Exposed as the middle **Repair** tab in `HifzReviewView` (`Queue | Repair | Map`) with a top **Practice Weakest Passage** CTA and tappable weak-ayah chips opening `MistakeDetailView`, plus a **Repair Weak Passages** row in Home's Memorization section when `repairCount > 0`.

## Trade-offs

- **Complexity added:** ~10 new files + wiring across `QuranAnnotations`, `MemorizationService`, `RecitationRecognition`, `NoorUI`, `MoreMenuFeature`, `AyahMenuFeature`, `QuranImageFeature`, `QuranTranslationFeature`, `QuranViewFeature`, `RecitationFollowFeature`, `HifzReviewFeature`, `HomeFeature` (+1,991 / -78 lines across 53 modified files plus 10 new files; 43 localization keys × 16 catalogs; 2 new `NoorSystemImage` cases + 3 aliases). No new dependencies, permissions, entitlements, background tasks, or Core Data / Backup schema versions. Failure modes: persistence errors surface retry/alert UI without mutating history.
- **Who benefits / how often:** Memorization learners reviewing recurring trouble spots across Practice, Spot Tests, Similar Verses, and Recite to Check. Likely used by a minority of readers overall (UNVERIFIED), and the silent recite-and-check policy is likely the least-used sub-mode (UNVERIFIED), though cheap (~30 lines) to keep.
- **Rejected cheaper options:** Persisting precomputed heatmaps in Core Data (adds migration and CloudKit sync conflicts; recomputing from tens/hundreds of sessions is fast and pure); building a separate note field inside Mistake Detail (duplicates `NoteService` and backup/sync); drilling isolated words in Repair Queue (violates roadmap §4 and §6 H7: a hafiz revises passages, not isolated words).
- **Ongoing cost:** Maintaining 43 agent-translated strings across 16 catalogs (native review UNVERIFIED); keeping heatmap suppression synchronized if inline similar-verse markers are added in a future follow-up; negligible memory/launch cost (mistake history loads asynchronously off the main actor when opening the reader or Memorization tab).

## Changes

- `Model/QuranAnnotations/Sources/MistakeHeatmap.swift` (new), `VerseOverlays.swift`: `MistakeHeatLevel`, `MistakeHeatmapOverlay`, `VerseOverlays.mistakeHeatmap` & `activeMistakeHeatmap`.
- `Domain/MemorizationService/Sources/MistakeHistory.swift` (new), `MemorizationService.swift`: `MistakeDecayPolicy`, `MistakeEvent`, `WordMistakeSummary`, `VerseMistakeSummary`, `MistakeHistorySnapshot`, `RepairQueueItem`, `MistakeHistoryReducer`, `recordSessionWithEvidence`, `mistakeHistory`, `mistakeSummary`, `mistakeHeatmap`, `repairQueue`, `confirmMistake`, `retractMistake`.
- `Domain/RecitationRecognition/Sources/RecitationChecker.swift`: public initializers on `CheckedWord` and `RecitationCheck`.
- `Domain/QuranTextKit/Sources/Preferences/QuranContentStatePreferences.swift`: `showMistakeHeatmap` preference (default `false`).
- `UI/NoorUI/Sources/`: `NoorSystemImage.swift` (`mistakeHeatmap`, `repairQueue`, aliases `mistakeHistory`, `confirmMistake`, `disputeMistake`), `VerseOverlays+Theme.swift` (heat colors + ayah-level highlight priority), `ImageDecorations.swift` / `ImageDecorationsLayout.swift` / `ImageDecorationsView.swift` (word-level heatmap fill + bottom bar), `QuranArabicText.swift` & `QuranWordByWordText.swift` (translation-mode word heat + VoiceOver value), `AyahMenuUI.swift` & `AyahMenuView.swift` (`mistakeHistory` row).
- `Features/MoreMenuFeature/Sources/`: `MoreMenuModel.swift`, `MoreMenuViewModel.swift`, `views/MoreMenuMistakeHeatmap.swift` (new), `views/MoreMenuView.swift`.
- `Features/QuranImageFeature/Sources/`: `ContentImageViewModel.swift` (`wordHeatmapHighlights`, Tajweed guard), `ContentLineViewModel.swift` (ayah-level heatmap, Tajweed guard).
- `Features/QuranTranslationFeature/Sources/`: `TranslationItem.swift`, `TranslationItem+View.swift`, `ContentTranslationViewModel.swift`.
- `Features/AyahMenuFeature/Sources/`: `AyahMenuBuilder.swift`, `AyahMenuViewController.swift`.
- `Features/QuranViewFeature/Sources/`: `QuranBuilder.swift`, `QuranInteractor.swift` (heatmap lifecycle, Tajweed guard, Ayah Menu Mistake History, Mistake Detail sheet + Practice/Note callbacks, V3b/H2/H5 live refresh).
- `Features/RecitationFollowFeature/Sources/`: `RecitationCheckViewModel.swift`, `RecitationCheckView.swift`, `RecitationCheckBuilder.swift` (V3b `.model` evidence recording, `RecitationCheckPolicy.silent`, inline `dispute(_:)` recomputing H7).
- `Features/HifzReviewFeature/Sources/`: `MistakeDetailViewModel.swift` (new), `MistakeDetailView.swift` (new), `MistakeDetailBuilder.swift` (new), `HifzReviewViewModel.swift`, `HifzReviewView.swift`, `HifzReviewBuilder.swift` (Repair tab + Mistake Detail sheet).
- `Features/HomeFeature/Sources/`: `HomeViewModel.swift`, `HomeView.swift`, `HomeViewController.swift` (conditional `Repair Weak Passages` row opening Repair tab).
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: 43 new keys in all 16 languages.
- `Package.swift`: direct dependencies for `MemorizationService` (`QuranAnnotations`), `HifzReviewFeature` (`QuranAnnotations`), `QuranViewFeature` (`MemorizationPersistence`), `RecitationFollowFeature` (`MemorizationPersistence`, `MemorizationService`, test deps).
- iPhone and iPad share every file; no platform conditionals.

## Tests

- `Model/QuranAnnotations/Tests/MistakeHeatmapTests.swift` (2): page restriction; practice-mask suppression.
- `Domain/MemorizationService/Tests/MistakeHistoryTests.swift` (7): explicit decay policy (clean recalls + 60-day half-life + threshold boundaries — caught the `1.0`/`2.0` threshold boundary bug before the fix, failed 3 assertions, passed after adjusting to `0.75`/`1.75`); one count per word per session; assisted recall does not decay while 3 clean recalls clear; confirm upgrades `.model` to `.manual` without doubling count; retracting last word mistake also retracts companion ayah mistake and clears heatmap/repair queue; retracting 1 of 2 word mistakes keeps the other active; repair queue resolves to full passages (declared or default `PassageSplitter`) and never isolated words.
- `Features/RecitationFollowFeature/Tests/RecitationCheckViewModelTests.swift` (+2): `recalls(from:)` confirms skipped/omitted/substituted as `.model`, excludes unreached, maps uncertain to `.skipped`; Core ML + Core Data test records `.model` skipped verse under `.silent` policy, feeds H7 heatmap & repair queue, and disputing retracts evidence and clears both immediately.
- `Features/HifzReviewFeature/Tests/MistakeDetailAndRepairTests.swift` (2): detail view model loads real Uthmani word units, confirms model event, removes manual event, triggers `onHistoryChanged`, launches full passage practice and note callback; review view model loads Repair tab items and launches full passage practice.
- `Features/QuranImageFeature/Tests/ContentImageHeatmapTests.swift` (1): canonical-to-image glyph mapping and Tajweed Mushaf suppression.
- `UI/NoorUI/Tests/VerseOverlaysThemeTests.swift` (+1): wordless heatmap ayah tint priority below saved highlights and `includeAllHeatmapVerses` mode.

## Validation

- **Verified:**
  - `make format-lint`: `0/1309 files require formatting, 68 files skipped.`
  - Focused suites: `LocalizationTests`, `QuranAnnotationsTests`, `MemorizationServiceTests` (`Executed 50 tests, with 0 failures`), `HifzReviewFeatureTests` (`Executed 12 tests, with 0 failures`), `RecitationFollowFeatureTests` (`Executed 12 tests, with 0 failures` incl. Core ML model tests), `QuranImageFeatureTests`, `NoorUITests` (`Executed 276 tests, with 0 failures`).
  - Full suites (xcresult summaries, run sequentially on iPhone 18 Pro Max simulator):
    - `make test-no-sync`: `passedTests: 1832, failedTests: 0, skippedTests: 0`
    - `make test-sync`: `passedTests: 2313, failedTests: 0, skippedTests: 0`
    - `make test-arabican`: `passedTests: 117, failedTests: 0, skippedTests: 0`
    - `make test-tools`: all tool test suites passed (`package-pins.test.sh` `5 passed, 0 failed`).
  - App builds: `make build-example-no-sync`, `make build-example-sync` (root `Package.resolved` restored afterward), `make build-arabican` — all `Build Succeeded`.
  - Live iPhone 18 Pro Max simulator (`make run-example-no-sync`): verified Home Memorization section showing `"Repair Weak Passages · 2 passages need repair"` in Light Large and Dark Accessibility Extra Large, and verified live Mistake Heatmap highlighting ayah `109:4` cleanly on Mushaf page 603 without moving printed layout (restored `showMistakeHeatmap` to `false` afterward).
- **Not verified:** physical-device microphone check with V3b inline Dispute and Silent mode; VoiceOver listening pass on heated word cells and Mistake Detail sheet; interactive landscape/AX-XL pass inside Mistake Detail, Repair tab, and Recite to Check sheets (reasoned in code: `ViewThatFits`, `WrappingHStack`, `AnyLayout` stacking at `dynamicTypeSize.isAccessibilitySize`, no fixed widths); compact iPhone and iPad split view (only iPhone 18 Pro Max simulator allowed); native review of the 43 agent translations across 15 non-English catalogs.

## Release

- **Commit:** `11ff32917869d5cf6286a33597b7821ad085127e`
- **Pushed:** `origin/main` (`76167fb8..11ff3291`)
- **TestFlight:** not uploaded (blocked by non-interactive Xcode account auth; owner action required):
  - `make release-testflight-quran`: archived `Quran (com.nulltup.memquran, App Store Connect MemQuran) 1.20.3 (1035)` from `11ff32917869d5cf6286a33597b7821ad085127e`, then failed in export: `error: exportArchive Failed to Use Accounts` (`App Store Connect access for “NBMD2V39VV” is required`, `xcodebuild -exportArchive failed (70)`).
  - `make release-testflight-arabican`: archived `Arabican (com.nulltup.arabican, App Store Connect Arabican) 0.1.0 (1035)` from `11ff32917869d5cf6286a33597b7821ad085127e`, then failed with the same `error: exportArchive Failed to Use Accounts` (`xcodebuild -exportArchive failed (70)`).
  - Owner command from an interactive Xcode-signed-in terminal: `make release-testflight-quran && make release-testflight-arabican` (Arabican shares `Localization`, `QuranAnnotations`, and `NoorUI`).
- **iCloud / CloudKit schema:** unchanged (no CloudKit in either app; no Core Data model version change).

## Follow-ups

- Next roadmap milestone: **H6** (Goals, Khatmah, activity time, today's plan, gentle streaks, optional reminders after D5).
- Owner physical-device verification of H7 + V3b (checklist item 34) and V4/V5 lab checks.
- Native review of the 43 new localization keys across the 15 non-English catalogs.
- If H5's optional inline similar-verse markers are added later, enforce mutual exclusion with `VerseOverlays.activeMistakeHeatmap`.
