# Quran D2: swift-fsrs approved for the root package

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** docs
- **Status:** shipped
- **Related:** [2026-11-27-v3a-recite-and-check.md](2026-11-27-v3a-recite-and-check.md); roadmap decision table (D2)

## Context

App: **Quran** (and the shared-pins rule both apps follow). After V3a, the next roadmap item is H1+H2, which needed
owner decision D2: may the root QuranEngine package depend on `open-spaced-repetition/swift-fsrs`, already pinned
exactly (6.0.0) for Arabican? The owner answered "Yes, approve D2" in chat on 2026-11-27.

## Decisions

- The root package uses the same exact pin as Arabican (`ArabicLearning/Package.swift:30`, `exact: "6.0.0"`), so
  the shared-pins rule (AGENTS.md, Two apps rule 6) covers it once H1 adds it. Only Domain/Data targets that schedule
  review may depend on it.
- Nothing is added to `Package.swift` yet: H1 adds the dependency with the code that uses it, its tests and its
  health check, so no unused dependency ships.

## Trade-offs

- **Complexity added:** none now; H1 will add one package already vetted and built for Arabican.
- **Who benefits / how often:** every Quran user of the Hifz review queue (H1–H3).
- **Rejected cheaper options:** a hand-written fixed-interval ladder (roadmap fallback); FSRS is already maintained
  and tested in this repository.
- **Ongoing cost:** one more shared pin to keep identical across three resolved files.

## Changes

- `AGENTS.md`: Dependencies (swift-fsrs approved for both packages) and Two apps rule 6 (FSRS shared once H1 adds it).
- `Documentation/agents/quran-prioritized-roadmap.md`: D2 approved; scheduler paragraph.
- `Documentation/agents/quran-roadmap-progress.md`: owner decisions, next step 1, H1 row.

## Tests

- **No new tests:** documentation of an owner decision; no source or tooling changed.

## Validation

- **Verified:** `make guardrails` on the commit.
- **Not verified:** nothing to check at runtime.

## Release

- **Commit:** see `git log` (docs(roadmap): record D2 approval).
- **TestFlight:** none: docs only.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- H1: add swift-fsrs 6.0.0 to `Package.swift`, copy the pin into `ArabicLearning/Package.resolved` and the Arabican
  project's resolved file, run `make test-tools` (`Tools/package-pins.test.sh`).
