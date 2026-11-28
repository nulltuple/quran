# Quran roadmap v5 order: pull V4 pronunciation and V5 tajweed assessment ahead of H7/V3b

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** docs
- **Status:** shipped
- **Related:** [roadmap v4 order](2026-11-27-quran-roadmap-v4-order.md) (the order this revises),
  [H5 similar verses](2026-11-27-h5-similar-verses.md) (completed before this reorder),
  [V0 recitation engine](2026-11-26-v0-recitation-engine.md) (baseline engine & deliverable 9)

App: **Quran** (roadmap only; no code; V4/V5 shared engine design will be reusable by **Arabican** via QuranEngine).

## Context

H5 shipped in Quran 1.20.3 (1030) and Arabican 0.1.0 (1030). The owner revised the execution order on 2026-11-27 to
deliver practical, on-device Quran pronunciation assessment (V4) and tajweed assessment (V5) next, ahead of H7/V3b:

`V4 → V5 → H7 foundation → V3b → H7 completion → H6 → P1 → C3 → P2 → deferred resource milestones`

All existing requirements, milestone IDs, and owner decisions (D1–D7, licensing, one simulator, reviewer/quality gates)
are preserved.

## Decisions

- **V4 and V5 move directly after H5.** V4 builds a practical, accurate, on-device phoneme and vowel assessment engine
  in QuranEngine (reusable by Arabican without reversing dependency direction) and integrates it into the existing
  Recitation Lab, preserving the Tilawi engine and all V0–V3 features. V5 builds rule-level tajweed assessment
  (prioritizing madd, ghunnah, and qalqalah first, expanding only where reliable acoustic evidence supports it) on V4.
- **H7 splits explicitly into foundation and completion around V3b**, followed by H6, P1, C3, P2, and deferred resource
  milestones (M2 synchronized reciters, R1 IndoPak Mushaf pack).
- **Guardrails locked into the v5 spec:** on-device inference only (no cloud without approval); memorization,
  pronunciation, and tajweed assessments stay separate; no learning-store redesign during V4/V5; never treat uncertain
  recognition as a confirmed mistake; qualified-reviewer and quality gates remain required before exposing V4/V5
  verdicts to users; if external review blocks user release, continue with H7 foundation / V3b.

## Trade-offs

- **Complexity added:** none in code (documentation update only).
- **Who benefits / how often:** accelerates on-device pronunciation and tajweed capabilities that benefit both Quran
  recitation practice and Arabican's future pronunciation exercises; defers H7 mistake heatmap and V3b history wiring
  until after V4/V5 land in the Recitation Lab.
- **Rejected options:** keeping v4's order (H7 + V3b before V4/V5), which the owner explicitly superseded.
- **Ongoing cost:** none beyond keeping the roadmap progress tracker synchronized.

## Changes

- `Documentation/agents/quran-prioritized-roadmap.md`: version-5 note, §5 execution-order table (rows 13–22), §6 voice
  track order and expanded V4/V5 specifications.
- `Documentation/agents/quran-roadmap-progress.md`: Handoff v5 note, revised Next steps order, updated V4/V5 milestone
  rows.
- `Documentation/trail/README.md`: added index line for this entry.

## Tests

- **No new tests:** documentation only.

## Validation

- **Verified:** roadmap §5 table, §6 voice track, and `quran-roadmap-progress.md` name the identical v5 order and
  preserve H5 shipped status (build 1030) and all owner decisions; `make guardrails` (verified before commit).
- **Not verified:** no code or runtime behavior changed in this entry.

## Release

- **Commit:** pending commit (`docs(roadmap): update Quran roadmap to v5 order`).
- **TestFlight:** none (docs only).
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Immediately begin V4: validate the leading on-device candidate (`Hisnlabs/tajweed-v2` distilled from
  `obadx/muaalem-model-v3_2`, with `obadx/muaalem-model-v3_2` as fallback) on `obadx/qdat_bench` and real/planted
  pronunciation mistakes, convert to Core ML, integrate into `RecitationRecognition` and `RecitationLabFeature`, and
  measure accuracy, latency, memory, and size.
