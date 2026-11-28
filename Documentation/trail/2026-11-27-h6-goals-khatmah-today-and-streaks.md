# Quran H6: goals, Khatmah replanning, activity time, today’s plan, and gentle streaks

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** feature
- **Status:** verified
- **Related:** [2026-11-27-h3-memorization-map-and-review-queue.md](2026-11-27-h3-memorization-map-and-review-queue.md) (`Quran 5`, backup schema 3, Home Memorization section, `HifzReviewFeature`),
  [2026-11-27-h7-v3b-mistake-history-and-repair.md](2026-11-27-h7-v3b-mistake-history-and-repair.md),
  [2026-11-26-f2-backup-restore.md](2026-11-26-f2-backup-restore.md) (JSON backup & restore),
  roadmap §5 #18, §6 H6, and §7 D5 ([quran-prioritized-roadmap.md](../agents/quran-prioritized-roadmap.md))

## Context

App: **Quran** (`CoreDataModel` `Quran 6`, `MemorizationPersistence`, `BackupPersistence`, `BackupService`, `MemorizationService`, `AudioBannerFeature`, `QuranViewFeature`, `HifzReviewFeature`, `HomeFeature`, `SettingsFeature`, `NoorUI`, `Localization`). **Arabican** imports `NoorUI` and `Localization`, so it is also tested, built, and eligible for release per AGENTS.md rule 5; Arabican's features do not change.

The owner requested continuing the Quran roadmap from `Documentation/agents/quran-roadmap-progress.md` starting with **H6**:
- Goals by activity (`read`, `listen`, `memorize`, `review`) with fixed or flexible workload, optional deadline, and weekday schedule;
- Khatmah plans with replanning that keeps all completed history;
- Presets: **Friday Al-Kahf**, **Ramadan Khatmah**, and **7-Part Week**;
- Activity time counting only visible, active reading (with idle cutoff) and actual audio playback;
- Home showing **Today**: continue reading, goal progress / active time / streak, and due review;
- Gentle streaks;
- **D5 check:** local reminders require notification permission (`UNUserNotificationCenter`) which is unapproved (roadmap §7 D5 / AGENTS.md §9), so no notification permission or entitlement was added.

## Decisions

- **Core Data `Quran 6` lightweight migration (CloudKit-compatible for P1):**
  - Added two CloudKit-compatible entities (`MO_StudyGoal` and `MO_ActivityLog`): UUID identities, all attributes optional or defaulted, no unique constraints, soft-delete tombstones (`removedOn` / `retractedOn`), and zero derived state stored redundantly.
  - Preserved exact parity on all existing entities (including `MO_LastPage.page` and `MO_PageBookmark.page` without `defaultValueString="0"`, verified by `SimpleCoreDataEntityUniquifierTests`).
  - Lightweight migration from `Quran 5.mom` → `Quran 6` verified by unit test and live simulator upgrade.
- **Backup schema 4 (`BackupPersistence`, `BackupService`, `BackupView`):**
  - Added `studyGoals` and `activityLogs` to `BackupSnapshot` using `decodeIfPresent`, keeping schema 1, 2, and 3 backups fully restorable.
  - Added full validation (`targetAmount > 0`, `weekdayMask` in `1...127`, `startPage` in `1...604`, valid optional verse bounds, non-negative durations/counts), idempotent merge (newer `modifiedOn` updates goal plan settings; removals and retractions carry over monotonically), replace cleanup, and preview counts (`Goals and Khatmah plans`, `Activity logs`).
- **Khatmah replanning preserves all history (`StudyGoalPlanner`):**
  - Replanning updates only `deadline`, `weekdayMask`, `workloadMode`, and/or `targetAmount` (plus `modifiedOn`) on `MO_StudyGoal`; it never deletes or modifies `MO_ActivityLog` records.
  - Daily flexible targets compute from `remainingBeforeToday / remainingScheduledDays` (ceiling), keeping today's displayed quota stable while logging progress today and smoothly adjusting tomorrow's pace if ahead or behind.
- **Active visible reading & actual playback tracking (`ActiveTimeTracker`):**
  - Reading time runs only while `QuranViewController` is visible (`viewDidAppear` → `viewWillDisappear`) AND the app is active in foreground (`didBecomeActive` / `willResignActive` / `didEnterBackground`).
  - Because `QuranViewController` sets `UIApplication.shared.isIdleTimerDisabled = true`, an explicit **120-second idle cutoff** caps any unattended span so leaving a Mushaf page open never inflates reading time. Pages count once dwelled `≥ 5 s`.
  - Listening time is driven by `AudioBannerViewModel`'s `.playing` state transitions (`AudioBannerListener.audioPlaybackStateDidChange(isPlaying:)`), counting only actual playback (never downloading, paused, or stopped) and continuing accurately while the screen is locked.
  - **Zero mastery leak (roadmap §9):** `ActivityLogRecord` never creates `RecallEvidenceRecord` or alters FSRS mastery, demonstrated map counts, or mistake heatmaps.
  - **Friday Al-Kahf guard:** brief glances (< 6 pages without manual check-in) do not falsely auto-complete Surah Al-Kahf.
- **Gentle streaks (`GentleStreakSummary`):**
  - Unscheduled rest days never break a streak.
  - Up to **1 missed scheduled day in any rolling 7-day window** is forgiven as a grace day (`graceDayUsedInCurrentStreak`), and active days this week (`X / 7`) are always displayed with calm, encouraging copy.
- **No notification permission / entitlement (D5):**
  - Local reminders are intentionally omitted until the owner approves D5 (roadmap §7).
- **UI organization:**
  - Placed `GoalsViewModel` and `GoalsView` (with `GoalEditorSheet`, `KhatmahReplanSheet`, and `LogGoalProgressSheet`) in `HifzReviewFeature` (exposed via `HifzReviewBuilder.buildGoals(withListener:)`) so `HomeFeature` adds a compact **Today** section directly under **Continue reading** without creating a new SPM target or pulling in Core ML.

## Trade-offs

- **Complexity added:** 2 new Core Data entities (`Quran 6`), Backup schema 4, 5 new source files (`GoalRecords.swift` 326 lines, `StudyGoals.swift` 795 lines, `ActiveTimeTracker.swift` 324 lines, `GoalsViewModel.swift` 388 lines, `GoalsView.swift` 947 lines) + wiring across `MemorizationPersistence`, `BackupPersistence`, `BackupService`, `MemorizationService`, `AudioBannerFeature`, `QuranViewFeature`, `HifzReviewFeature`, `HomeFeature`, `SettingsFeature`, `NoorUI` (+1 `NoorSystemImage` case `studyGoal` + 3 aliases), and 90 localization keys × 16 catalogs (agent translations). Zero new third-party dependencies, permissions, entitlements, or background tasks.
- **Who benefits / how often:** Daily Quran readers, Ramadan/7-day Khatmah readers, Friday Al-Kahf readers, and Hifz learners tracking daily study consistency. Custom weekday schedules, fixed-vs-flexible toggle on non-Khatmah habits, and manual activity check-ins for non-reading activities are the pieces most likely to be rarely used (UNVERIFIED, no analytics), though cheap to keep inside the shared goal model.
- **Rejected cheaper options:** Storing goals in `UserDefaults` (would not survive F2 backup/restore or P1 iCloud sync); building a separate `GoalsFeature` SPM target (adds target/xctestplan/xcodeproj churn when `HomeFeature` already depends on `HifzReviewFeature`); adding a third tab or replacing Home's Surahs/Juz' segmented control (crowds compact widths and violates roadmap §3 "reader first"); requesting notification permissions without D5 approval (violates AGENTS.md §9).
- **Ongoing cost:** Maintaining 90 agent-translated strings across 16 catalogs (native review UNVERIFIED); every future Core Data user entity must keep `BackupService` in sync; negligible launch/memory impact (`todayPlan()` runs asynchronously off the main actor alongside `reviewQueue()`).

## Changes

- `Data/CoreDataModel/Sources/`: `Quran.xcdatamodeld/Quran 6.xcdatamodel/contents` (new), `.xccurrentversion`, `Schema.swift` (`StudyGoal`, `ActivityLog`).
- `Data/MemorizationPersistence/Sources/`: `GoalRecords.swift` (new: `GoalActivity`, `GoalKind`, `GoalUnit`, `GoalWorkloadMode`, `WeekdaySchedule`, `StudyGoalRecord`, `ActivityLogRecord`), `MemorizationRecords.swift`, `CoreDataMemorizationPersistence.swift` (`saveGoal`, `removeGoal`, `recordActivityLog`, `retractActivityLogs`).
- `Data/BackupPersistence/Sources/` & `Domain/BackupService/Sources/` & `Features/SettingsFeature/Sources/Backup/BackupView.swift`: schema 4 (`studyGoals`, `activityLogs`), validation, idempotent merge, replace cleanup, backward-compatible restore of schema 1–3, preview rows.
- `Domain/MemorizationService/Sources/`: `StudyGoals.swift` (new: `StudyGoalPreset`, `GoalPaceStatus`, `GoalProgressSnapshot`, `GentleStreakSummary`, `DayActivityBucket`, `TodayPlanSummary`, `StudyGoalPlanner`), `ActiveTimeTracker.swift` (new), `MemorizationService.swift` (`todayPlan`, `saveGoal`, `createPresetGoal`, `replanGoal`, `setGoalPaused`, `removeGoal`, `logActivity`, `logManualProgress`, `retractActivityLog`).
- `Features/AudioBannerFeature/Sources/AudioBannerViewModel.swift`: `AudioBannerListener.audioPlaybackStateDidChange(isPlaying:)` firing only on actual `.playing` transitions.
- `Features/QuranViewFeature/Sources/`: `QuranInteractor.swift`, `QuranViewController.swift` (foreground/visibility/interaction reading tracking with idle cutoff, live audio playback tracking, async persistence).
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: `studyGoal` (`"target"`) and aliases `gentleStreak`, `replanGoal`, `goalComplete`.
- `Features/HifzReviewFeature/Sources/`: `GoalsViewModel.swift` (new), `GoalsView.swift` (new: Today summary, gentle streak, active time breakdown, goal/Khatmah cards, presets, 7-day bar view, Goal Editor / Replan / Log Progress sheets), `HifzReviewBuilder.swift` (`buildGoals(withListener:)`).
- `Features/HomeFeature/Sources/`: `HomeViewModel.swift`, `HomeView.swift`, `HomeViewController.swift` (**Today** section under Continue reading with active time, gentle streak, goal progress, and direct Khatmah/Surah reader jump).
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: 90 new keys (`backup.count.goals`, `backup.count.activity-logs`, `goals.*`) across all 16 catalogs.
- Platforms: iPhone and iPad (universal target); no platform conditionals.

## Tests

- `Data/MemorizationPersistence/Tests/CoreDataMemorizationPersistenceTests.swift` (+2): `testUpgradingFromTheFifthModelVersionKeepsRangesAndAddsGoalsAndActivityLogs` (`Quran 5` → `Quran 6` lightweight migration) and `testStudyGoalsAndActivityLogsSaveUpdateTombstoneAndRetract`.
- `Data/BackupPersistence/Tests/CoreDataBackupPersistenceTests.swift` (+1 + extended sample): `testMergingStudyGoalsAndActivityLogsCarriesUpdatesRemovalsAndRetractions`.
- `Domain/BackupService/Tests/BackupServiceTests.swift` (+1 + extended schema 4 validation): `testASchemaThreeBackupRestoresWithoutGoalsOrActivityLogs`, schema version 4 header, newer version 5 refusal, invalid goal/log refusal.
- `Domain/MemorizationService/Tests/StudyGoalsAndActivityTrackerTests.swift` (new, 6 tests): presets (Friday Al-Kahf, Ramadan Khatmah, 7-Part Week); Khatmah replanning keeping completed history; all 4 activities without mastery leak; Friday Al-Kahf brief-glance guard; gentle streaks skipping rest days & 1 grace day per rolling week; `ActiveTimeTracker` idle cutoff (45 min unattended capped to 120 s), background reading pause, and playback-only audio tracking.
- `Features/HifzReviewFeature/Tests/GoalsViewModelTests.swift` (new, 1 test): end-to-end presets, manual progress, Khatmah reader page navigation, replanning keeping history, pause, delete preserving activity history.
- Regression caught during full verification: initial `Quran 6.xcdatamodel/contents` accidentally added `defaultValueString="0"` to `MO_LastPage.page` and `MO_PageBookmark.page`, causing `SimpleCoreDataEntityUniquifierTests.test_merge_skipsInsertedEntityWithMissingUniquenessValue` to fail in both sync and no-sync suites (`XCTAssertNil failed: "0"`). Removing the unintended default values restored exact parity with `Quran 5` and brought both suites to 0 failures.

## Validation

- **Verified:**
  - `make format-lint`: `0/1316 files require formatting, 69 files skipped.`
  - Focused suites: `LocalizationTests` (53/53), `MemorizationPersistenceTests` (9/9), `BackupPersistenceTests` (16/16), `BackupServiceTests` (13/13), `MemorizationServiceTests` (56/56), `HifzReviewFeatureTests` (13/13), `AudioBannerFeatureTests` (3/3), `QuranViewFeatureTests` (32/32) — all 0 failures.
  - Full suites (sequential on iPhone 18 Pro Max simulator):
    - `make test-no-sync`: `passedTests: 1843, failedTests: 0, skippedTests: 0` (`Run-QuranEngine-Package-2026.11.27_19-34-54--0800.xcresult`).
    - `make test-sync`: `passedTests: 2324, failedTests: 0, skippedTests: 0` (`Run-QuranEngine-Package-2026.11.27_19-40-40--0800.xcresult`).
    - `make test-arabican`: `passedTests: 117, failedTests: 0, skippedTests: 0` (`Run-ArabicLearning-Package-2026.11.27_19-32-36--0800.xcresult`).
    - `make test-tools`: all tool tests passed.
  - App builds: `make build-example-no-sync`, `make build-example-sync` (`Package.resolved` restored cleanly), `make build-arabican` — all `Build Succeeded`.
  - Live iPhone 18 Pro Max simulator (`make run-example-no-sync`): verified `Quran 5` → `Quran 6` live upgrade preserving existing simulator data, and verified Home **Today** section displaying `"Goals & Khatmah · 6 min · 1-day streak"` cleanly in Light Large and Dark Accessibility Extra Large.
- **Not verified:**
  - Physical-device active reading idle cutoff (waiting > 2 minutes on an open Mushaf) and lock-screen background audio listening accumulation (owner checklist item 35).
  - Interactive simulator tap-through of `GoalsView`, `GoalEditorSheet`, `KhatmahReplanSheet`, and `LogGoalProgressSheet` in portrait, landscape, and AX-XL (layout reasoned in code via `dynamicTypeSize.isAccessibilitySize` adaptive `AnyLayout` stacks, `Form`/`List`, and no fixed widths; business logic covered by `GoalsViewModelTests`).
  - Compact-iPhone width and iPad split view (only iPhone 18 Pro Max simulator allowed).
  - On-device VoiceOver pass over goal cards, weekday toggles, and 7-day activity bars.
  - Native review of the 90 agent-translated strings across the 15 non-English catalogs.

## Release

- **Commit:** `3f167562ddcfeecc4be47dc0379842372b07b4db`
- **Pushed:** `origin/main` (`8e4149fe..3f167562`)
- **TestFlight:** not uploaded (blocked by non-interactive Xcode account auth; owner action required):
  - `make release-testflight-quran`: archived `Quran (com.nulltup.memquran, App Store Connect MemQuran) 1.20.3 (1037)` from `3f167562ddcfeecc4be47dc0379842372b07b4db`, then failed in export: `error: exportArchive Failed to Use Accounts` (`xcodebuild -exportArchive failed (70)`).
  - `make release-testflight-arabican`: archived `Arabican (com.nulltup.arabican, App Store Connect Arabican) 0.1.0 (1037)` from `3f167562ddcfeecc4be47dc0379842372b07b4db`, then failed with the same `error: exportArchive Failed to Use Accounts` (`xcodebuild -exportArchive failed (70)`).
  - Owner command from an interactive Xcode-signed-in terminal: `make release-testflight-quran && make release-testflight-arabican` (Arabican imports shared `Localization` and `NoorUI`).
- **iCloud / CloudKit schema:** unchanged (entities follow CloudKit rules for P1; no CloudKit enabled yet).

## Follow-ups

- **Owner decision D5:** if local goal reminders are wanted, approve notification permission (`UNUserNotificationCenter`) so a follow-up slice can add opt-in per-goal reminder times.
- Next roadmap milestones: **P1** (Private iCloud sync — requires owner decision **D3** for iCloud capability & production CloudKit schema deployment) or **C3** (Translation compare, formatted share, search filters — completely unblocked if D3 is not yet decided).
- Native review of the 90 new localization keys across the 15 non-English catalogs.
