# Quran H3: memorization map and passage review queue

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** feature
- **Status:** verified
- **Related:** [2026-11-27-h1-h2a-learning-store-and-practice.md](2026-11-27-h1-h2a-learning-store-and-practice.md) (`Quran 4`, `MemorizationService`, backup schema 2),
  [2026-11-27-v2b-live-practice-reveal.md](2026-11-27-v2b-live-practice-reveal.md) (V2b live reveal in Practice),
  [2026-11-26-f2-backup-restore.md](2026-11-26-f2-backup-restore.md) (JSON backup and restore),
  roadmap §3, §4, §5 #12 and §6 H3 ([quran-prioritized-roadmap.md](../agents/quran-prioritized-roadmap.md))

App: **Quran** (`QuranKit`, `CoreDataModel` `Quran 5`, `MemorizationPersistence`, `BackupPersistence`, `BackupService`,
`MemorizationService`, `HifzReviewFeature`, `HomeFeature`, `HifzPracticeFeature`, `QuranContentFeature`,
`QuranViewFeature`, `FeaturesSupport`, `AppStructureFeature`, `SettingsFeature`, `NoorUI`, `Localization`).
Arabican imports `QuranKit`, `NoorUI`, and `Localization`, so it is tested, built, and released too; Arabican's
features do not change.

## Context

Roadmap §5 #12 and §6 H3: "Declare what is already memorized quickly (by surah, juz, page range); juz → surah →
ayah map with state colors plus text labels; due queue of passages with reason ('weak 3 sessions', 'due 2 days');
Sabaq/Sabqi/Manzil buckets with daily budgets; skip, reschedule, reset with confirmation. Review opens H2 on the
passage."

H1 left `MemorizedRange` and `Passage` entities to H3 so nothing shipped unused. With H2 (a–c) and V2b complete,
H3 turns standalone reader practice into a retention loop while keeping Quran a reader first (one Memorization
section on Home pushing the review queue and map screen, not a new app shell).

## Decisions

- **`QuranKit` range algebra (`AyahRangeSet` + `ClosedRange<AyahNumber>.verseCount`).** Normalized, disjoint,
  sorted canonical `AyahNumber` ranges with O(suras) verse counting, `contains`, `union`, `subtracting`, and
  `intersection`. Placed in `QuranKit` per roadmap §4 so Arabican's bridge reader can reuse it later.
- **Core Data `Quran 5` lightweight migration (CloudKit-compatible for P1).** Adds `MO_MemorizedRange`
  (`id`, `firstSura`, `firstAyah`, `lastSura`, `lastAyah`, `declaredOn`, `removedOn`) and `MO_Passage`
  (`id`, `firstSura`, `firstAyah`, `lastSura`, `lastAyah`, `createdOn`, `modifiedOn`, `snoozedUntil`, `removedOn`).
  UUID identities, all attributes optional or defaulted, no relationships or unique constraints, tombstones
  (`removedOn`) instead of hard deletes.
- **Backup schema 3.** Extends `BackupSnapshot` with `memorizedRanges` and `passages`, bumps
  `BackupService.schemaVersion` to `3`, keeps schema 1 and schema 2 files backward-compatible (`decodeIfPresent`),
  validates all verse bounds, adds a `Memorized ranges` preview row in Settings > Backup & Restore, and merges
  idempotently (removals carry over; newer `modifiedOn` updates passage bounds and snoozes).
- **Default passage splitting (`PassageSplitter`) + user-editable split.** Declaring a memorized range splits
  uncovered verses by sura first (short suras on the same page stay distinct passages), then by page, halving
  dense chunks (> 10 ayahs) to ~half-page units. Any multi-ayah passage can be split after any chosen ayah
  (`splitPassage`), tombstoning the old record and creating two new `PassageRecord`s.
- **Sabaq / Sabqi / Manzil buckets derived from FSRS + declarations (never stored separately).**
  - **Sabaq:** `.learning` passages (new or relearning after Forgot).
  - **Sabqi:** `.weak` passages or `.strong` passages with review interval < 14 days (recent consolidation).
  - **Manzil:** `.strong` passages with review interval ≥ 14 days, plus `.unassessed` declared passages awaiting
    first verification.
  - Daily budgets (defaults 2 / 4 / 5, range 0–20) live in `UserDefaults` (`ReviewBudgetStore`, preferences, not
    backed up) and highlight today's remaining budget per bucket while keeping overflow accessible under "More Due".
- **Declared vs demonstrated kept strictly apart.** `MemorizationMapSummary` tracks `declaredVerseCount`
  independently from `demonstratedVerseCount` (`learning` + `weak` + `strong`) across all 6,236 ayahs, 30 juzs
  (with exact `JuzSuraSlice` bounds so Juz counts equal the sum of their sura slices), and 114 suras. Every map
  state pairs color with an explicit text label (and VoiceOver label).
- **Skip, Reschedule, Reset (with confirmation).** Skip snoozes until start of tomorrow; Reschedule offers
  Tomorrow / 3 days / 1 week / custom date; practicing a snoozed passage supersedes the snooze automatically;
  Reset retracts all active `RecallEvidenceRecord`s for that passage's sessions and clears its snooze (append-only
  CloudKit-compatible, behind a destructive confirmation alert). Removing a declared range tombstones the range
  and any orphaned passages while preserving practice history.
- **Exact passage launch into H2/V2b Practice.** Added `QuranInput.initialPracticeRange` (default `nil`),
  `QuranNavigator.navigateToPractice(verses:)`, and `HifzPracticeBuilder.build(passage:...)` so queued passages —
  including 1-ayah passages — launch H2/V2b directly in the reader on the active Mushaf edition without expanding
  single ayahs to the end of the page.
- **Home surface (`HomeFeature`).** Added a compact `Memorization` section under `Continue reading` (due count +
  "Review & Memorization Map" + "Start Next Review" when due > 0), keeping Home's Surahs/Juz' segmented bar
  uncrowded and setting up H6's Today surface.
- **New feature target (`HifzReviewFeature`).** Separate from `HifzPracticeFeature` so `HomeFeature` does not pull
  in `RecitationRecognition`.

## Trade-offs

- **Complexity added:** `AyahRangeSet` (202 lines) in `QuranKit`; `Quran 5` Core Data model + 2 entities;
  `MemorizationPersistence` (+~175 lines); `BackupPersistence` / `BackupService` schema 3 (+~110 lines);
  `MemorizationService` (+~1,030 lines across `PassageSplitter`, `ReviewQueue`, `MemorizationService`);
  new `HifzReviewFeature` target (6 files, 1,647 lines, 1 test file); `HomeFeature` integration (+~130 lines);
  reader launch wiring (+~45 lines across `FeaturesSupport`, `QuranContentFeature`, `HifzPracticeFeature`,
  `QuranViewFeature`, `AppStructureFeature`); 5 new `NoorSystemImage` cases + 3 aliases; 74 localization keys ×
  16 catalogs (agent translations). No new third-party dependency, permission, entitlement, or background work.
- **Who benefits / how often:** learners actively memorizing and revising daily; likely a minority of overall
  Quran readers (UNVERIFIED, no analytics). Passage splitting and custom daily budgets are the pieces most likely
  to be rarely used (UNVERIFIED), though both are small (~150 lines combined).
- **Rejected cheaper options:** adding a 3rd segment ("Memorization") to Home's navigation-bar segmented control
  (crowds compact iPhone widths and localized titles); computing the map only at Surah level without Juz slices
  (breaks Juz-based Hifz revision workflows and roadmap spec); hard-deleting reset sessions (breaks CloudKit/backup
  idempotency); putting H3 UI inside `HifzPracticeFeature` (would pull Core ML / `RecitationRecognition` into
  `HomeFeature`).
- **Ongoing cost:** `mapSummary()` walks 6,236 ayahs on load (runs off the main actor; ~20 ms in tests, phone
  timing UNVERIFIED); 74 more keys in 16 catalogs (agent translations, native review UNVERIFIED); every future
  learning entity still requires a backup schema bump.

## Changes

- `Model/QuranKit/Sources/AyahRangeSet.swift` (new) & `Tests/AyahRangeSetTests.swift` (new).
- `Data/CoreDataModel/Sources/Quran.xcdatamodeld/Quran 5.xcdatamodel/contents` (new), `.xccurrentversion`, `Schema.swift`.
- `Data/MemorizationPersistence/Sources/MemorizationRecords.swift`, `CoreDataMemorizationPersistence.swift`.
- `Data/BackupPersistence/Sources/BackupSnapshot.swift`, `CoreDataBackupPersistence.swift`;
  `Domain/BackupService/Sources/BackupService.swift`; `Features/SettingsFeature/Sources/Backup/BackupView.swift`.
- `Domain/MemorizationService/Sources/PassageSplitter.swift` (new), `ReviewQueue.swift` (new), `MemorizationService.swift`.
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: `memorizationMap`, `reschedule`, `skipPassage`, `splitPassage`,
  `resetProgress`, and aliases `reviewQueue`, `declareMemorized`, `reviewBudgets`.
- `Features/QuranContentFeature/Sources/QuranInput.swift`, `Features/FeaturesSupport/Sources/QuranNavigator.swift`,
  `Features/AppStructureFeature/Sources/Common/TabInteractor.swift`,
  `Features/HifzPracticeFeature/Sources/HifzPracticeBuilder.swift`,
  `Features/QuranViewFeature/Sources/QuranInteractor.swift`.
- `Features/HifzReviewFeature/Sources/`: `HifzReviewBuilder.swift`, `HifzReviewViewModel.swift`,
  `HifzReviewFormatting.swift`, `HifzReviewView.swift`, `HifzMapView.swift`, `HifzReviewSheets.swift` (new).
- `Features/HomeFeature/Sources/`: `HomeBuilder.swift`, `HomeViewModel.swift`, `HomeView.swift`, `HomeViewController.swift`.
- `Features/AppDependenciesFake/Sources/AppDependenciesFake.swift`: returns test `stack` for `coreDataStack`.
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: 74 keys (`backup.count.memorized-ranges`,
  `hifz_review.*`) in all 16 catalogs.
- `Package.swift`, `QuranEngine-Package.xctestplan`: added `HifzReviewFeature` and `HifzReviewFeatureTests`,
  updated `HomeFeature` and `QuranViewFeature` dependencies.
- Docs: `Documentation/agents/quran-prioritized-roadmap.md`, `Documentation/agents/quran-roadmap-progress.md`,
  `Documentation/agents/feature-cost-register.md`, `Documentation/trail/README.md`.
- Platforms: iPhone and iPad (one universal target); no platform conditionals.

## Tests

- `Model/QuranKit/Tests/AyahRangeSetTests.swift` (4 tests): overlapping/adjacent normalization across suras,
  union/intersection/subtraction, full 6,236-verse count, edge cuts.
- `Data/MemorizationPersistence/Tests/CoreDataMemorizationPersistenceTests.swift` (+2 tests): **`Quran 4` →
  `Quran 5` lightweight migration** keeping existing sessions and adding ranges/passages; declared range and
  passage save/update/tombstone idempotency.
- `Data/BackupPersistence/Tests/CoreDataBackupPersistenceTests.swift` (+1 test + extended sample): schema 3
  round trip, idempotent merge carrying removals and newer snoozes, replace.
- `Domain/BackupService/Tests/BackupServiceTests.swift` (+1 test + extended validation): schema 3 header,
  **schema 1 and schema 2 files still restore**, invalid range/passage records refused, summary count.
- `Domain/MemorizationService/Tests/PassageSplitterTests.swift` (3 tests): short suras stay separate on page 604,
  Al-Mulk splits by page and halves dense pages, 1-ayah passage.
- `Domain/MemorizationService/Tests/ReviewQueueAndMapTests.swift` (4 tests): declare → default passages +
  declared-vs-demonstrated map, Sabaq/Sabqi/Manzil buckets + weak-3-sessions & overdue-days reasons + daily
  budgets, skip/reschedule/split/reset/remove-declaration lifecycle, `ReviewBudgetStore` clamping.
- `Features/HifzReviewFeature/Tests/HifzReviewViewModelTests.swift` (4 tests): declare suras/pages, launch
  practice, bucket filter, budgets, skip/reschedule/split/reset/remove, open in reader.
- Regression evidence: verified via new tests in every owning module and simulator UI screenshots (initial
  screenshot showed `"Not memori…"` truncation in Ayah Map cell 4 and uneven bucket card heights; widening
  `cellSize` to 76 pt with 2-line wrapping and `.frame(maxHeight: .infinity, alignment: .topLeading)` fixed both,
  confirmed in re-captured Dark + AX-XL screenshots).

## Validation

- **Verified:**
  - `make format-lint`: `0/1272 files require formatting, 62 files skipped.`
  - Full Quran no-sync suite (`make test-no-sync`): `passedTests: 1776`, `failedTests: 0`, `skippedTests: 0`
    (`Run-QuranEngine-Package-2026.11.27_14-00-30--0800.xcresult`).
  - Full Quran sync suite (`make test-sync`): `passedTests: 2257`, `failedTests: 0`, `skippedTests: 0`
    (`Run-QuranEngine-Package-2026.11.27_14-06-37--0800.xcresult`).
  - Full Arabican suite (`make test-arabican`): `passedTests: 117`, `failedTests: 0`, `skippedTests: 0`
    (`Run-ArabicLearning-Package-2026.11.27_14-13-39--0800.xcresult`).
  - Tools (`make test-tools`): all passed (`package-pins.test.sh`: `5 passed, 0 failed`, plus build/guardrails/release
    tests).
  - App builds: `make build-example-no-sync` (`Build Succeeded`), `make build-example-sync` (`Build Succeeded`,
    tracked no-sync `Package.resolved` restored), `make build-arabican` (`Build Succeeded`).
  - Simulator end-to-end UI verification on iPhone 18 Pro Max (`C4D112D1-BB82-4A00-A6AE-9CAE1A7A7148`, iOS 27.2):
    - Home Memorization section in Light + Large and Dark + AX-XL (`accessibility-extra-large`), picking up
      migrated `Quran 4` → `Quran 5` practice sessions immediately.
    - Full flow (`** TEST SUCCEEDED **`): Home → Memorization → Declare Memorized (Juz picker) → Review Queue
      (Sabaq/Sabqi/Manzil bucket strip, pills, reasons) → Map (Juz list → Juz 30 Surahs → Al-Ikhlāṣ Ayah Grid) →
      Landscape rotation → Practice button launching H2/V2b Practice directly on `112:1–4` on page 604 with masks
      and Practice bar.
    - Re-verified Dark + AX-XL after cell width and bucket alignment polish (`** TEST SUCCEEDED **`: vertical
      bucket stack, 2-column scaled Ayah Grid with zero truncation on `"Not memorized"`). Left simulator in Light
      mode, Large text.
- **Not verified:**
  - Physical device upgrade from build 1022 (`Quran 4` → `Quran 5` Core Data migration on real user data) and
    `mapSummary()` latency on a phone with large history (owner checklist item 31).
  - Compact-iPhone width and iPad split view (reasoned via `dynamicTypeSize.isAccessibilitySize`, adaptive
    `LazyVGrid` with `@ScaledMetric`, no fixed widths).
  - On-device VoiceOver focus order across Queue rows, bucket cards, and Ayah Map cells.
  - Native review of the 74 agent-translated strings across the 15 non-English catalogs.

## Release

- **Commit:** `4ddf13a801fdef2aa454433ec21f9c6d6a52d2c7` (`feat(hifz): memorization map and passage review queue (H3)`)
- **Pushed:** `origin/main` at `4ddf13a8`
- **TestFlight:** blocked on owner Xcode Accounts sign-in — archive succeeded for Quran `1.20.3 (1025)`, then
  `xcodebuild -exportArchive` failed (70): `error: exportArchive Failed to Use Accounts` ("App Store Connect
  access for 'NBMD2V39VV' is required. Ensure that your Apple Account usernames and passwords are correct in
  Accounts settings."). Both `make release-testflight-quran` and `make release-testflight-arabican` are ready to
  run once signed back in (this build ships both V2b and H3).
- **iCloud / CloudKit schema:** unchanged (entities follow CloudKit rules for P1).

## Follow-ups

- Proceed to **H4** (Spot tests with strict and granular scores: random-start exams over memorized or custom
  ranges, presets Warm up / Weakest / Due / Recent / Old, count or timer, strict/word-recall/coverage/assistance
  scores, temporary tests never changing history).
- Optional H3 polish after owner device feedback: merge adjacent passages in UI (split is built), custom
  Sabaq/Sabqi/Manzil interval threshold, native review of non-English `hifz_review.*` strings.
