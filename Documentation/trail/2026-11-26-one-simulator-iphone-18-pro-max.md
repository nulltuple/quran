# Both apps: agents use only the iPhone 18 Pro Max simulator

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** tooling
- **Status:** shipped
- **Related:** [2026-11-25-arabican-l0-bootstrap.md](2026-11-25-arabican-l0-bootstrap.md) (gave Arabican its own iPhone Air simulator)

## Context

App: **both** (Quran and Arabican tooling and agent rules). During Arabican L7 an agent booted the
iPhone Air simulator, which the Makefile (`ARABICAN_TEST_DESTINATION`) and the Arabican handoff
named. The owner: "FOCUS ON IPHONE 18 PRO MAX SIMULATOR. HAVE ONLY ONE SIMULATOR. EACH SIMULATOR
COSTS EXTRA DISK SPACE" and asked to update the agent guidelines of both projects.

## Decisions

- One Makefile variable, `SIMULATOR_NAME ?= iPhone 18 Pro Max`; every destination derives from it
  (`PACKAGE_DESTINATION`, `ARABICAN_TEST_DESTINATION`, `EXAMPLE_NO_SYNC_SIMULATOR`,
  `EXAMPLE_SYNC_SIMULATOR`, `ARABICAN_SIMULATOR`). Before: iPhone 17e (Quran tests, no-sync run),
  iPhone 17 Pro Max (sync run), iPhone Air (Arabican).
- Concurrency rule changes: Quran and Arabican package suites can no longer run at the same time
  (they would share one simulator's UserDefaults and Documents). AGENTS.md now says run no-sync,
  sync and Arabican one after another.
- The UI-check rule (compact iPhone, iPad split view) conflicts with one simulator. AGENTS.md now
  asks for portrait and landscape on the iPhone 18 Pro Max, with compact-iPhone and iPad layouts
  reasoned in code and listed under Not verified. The owner may still ask for another simulator.
- `make preview` (`Tools/preview.mjs`) picks only the iPhone 18 Pro Max; `PREVIEW_DEVICE` still
  selects one by UDID when several share the name.
- Other simulators on this Mac were **not deleted**: deleting is the owner's call (they may hold
  data, and some were booted, perhaps by the owner). Shut down only the iPhone Air this session booted.

## Trade-offs

- **Complexity added:** one Makefile variable; 7 checks in `Tools/release.test.sh`; a name filter in
  `Tools/preview.mjs`. No app code changes.
- **Who benefits / how often:** the owner's disk, every session.
- **Rejected cheaper options:** a doc-only rule (agents follow Makefile defaults, which is how
  iPhone Air was picked); a check in the guardrail hook (release.test.sh already checks the Makefile).
- **Ongoing cost:** Quran and Arabican suites run sequentially (longer wall time when both are
  needed). When Xcode drops the iPhone 18 Pro Max, change `SIMULATOR_NAME`, `STANDARD_SIMULATOR`
  in `Tools/preview.mjs` and the AGENTS.md "Simulator" section together.

## Changes

- `Makefile`: `SIMULATOR_NAME`; all simulator destinations use it; Arabican comment.
- `Tools/preview.mjs`: `STANDARD_SIMULATOR`; `chooseDevice` considers only it.
- `AGENTS.md` (CLAUDE.md is a symlink): new "Simulator" section; two-app rule 7; definition of
  done step 3; UI-check rule.
- `Documentation/Previews.md`, `Documentation/ArabicLearning/HANDOFF.md`: same rule.

## Tests

- `Tools/release.test.sh`: the Makefile names iPhone 18 Pro Max, the five destinations use
  `SIMULATOR_NAME`, and no other Makefile line names an iPhone or iPad. Shown to catch a wrong
  value by grepping a copy with `SIMULATOR_NAME ?= iPhone Air` (fails).
- `Tools/preview.test.mjs`: picks only the standard simulator (booted first, then latest iOS), and
  fails when only other iPhones exist.

## Validation

- **Verified:** `make test-tools`: `43 passed, 0 failed` (release), `ℹ pass 8` / `ℹ fail 0`
  (preview). `make test-arabican` on `name=iPhone 18 Pro Max,OS=latest`: 117 tests passed
  (xcresult summary). Focused Quran run `make test-no-sync TARGET=LocalizationTests` on
  `-destination "name=iPhone 18 Pro Max,OS=latest"`: `Executed 53 tests, with 0 failures`,
  `Test Succeeded`.
- **Not verified:** full Quran suites and builds on the new destination (only the focused run); CI
  runners having an iPhone 18 Pro Max (CI uses the Makefile defaults with Xcode 27.2; UNVERIFIED).

## Release

- **Commit:** see the L7 entry (same push).
- **Pushed:** origin/main.
- **TestFlight:** none for this change on its own (tooling); the Arabican L7 build ships with it.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Owner: delete unused simulators if wanted (`xcrun simctl delete <udid>`); not done by an agent.
