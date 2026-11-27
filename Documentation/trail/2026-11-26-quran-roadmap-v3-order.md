# Quran roadmap v3 order: Quran AI Engine and voice search before Hifz

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** docs
- **Status:** shipped
- **Related:** [roadmap v2](2026-11-26-quran-roadmap-v2.md) (the order this revises),
  [C2 occurrences](2026-11-26-c2-word-occurrences.md) (the session this came from)

App: **Quran** (roadmap only; no code). Arabican is affected only in that V0's recognition interface must be
consumable by Arabican.

## Context

The owner proposed a new order (screenshot, 2026-11-26): C2 → V0 → V1 → H1+H2 → V2 → H3–H5 → H7 foundation + V3 →
remaining (P1, H6, H7 completion, C3, P2, M2), asking for a call-out if it was a bad idea. The agent accepted it and
suggested V0 be a go/no-go gate. The owner rejected the gate: "V1–V3 are committed product objectives. Failure of a
particular model, runtime or implementation must result in evaluating alternatives, not dropping the AI milestones."
The owner renamed V0 "Quran AI Engine — Technology Selection and Implementation", approved D4, required Quran-trained
models before Apple's generic `SpeechTranscriber`, listed resources to evaluate first, and set ten deliverables.

## Decisions

- **Order adopted as the owner proposed** (roadmap §5). The agent's view, recorded for the next agent: V0 before H1
  is right (H1's evidence model already plans for model provenance, and what the engine can do shapes H2's reveal);
  V1 before H1 delays the core Hifz loop by one milestone in exchange for proving microphone, model delivery and
  audio capture on a low-stakes feature; P1 (iCloud sync) at the end is acceptable because F2 backup protects data,
  but a household reading on both iPhone and iPad will miss it.
- **No go/no-go gate** (owner). Per-result confidence gates and per-release quality gates stay; a failing model,
  runtime or quantization leads to trying alternatives, and a persistent on-device limitation is documented with
  proposals for owner approval. V1–V3 are never silently dropped or deferred.
- **D4 approved (owner, 2026-11-26):** microphone permission; evaluating and integrating local inference
  dependencies; downloading publicly available models and evaluation datasets. Family recordings are optional and
  never block development. Each new dependency still gets its Trade-offs entry and cost-register row (AGENTS.md §3).
- **V0 spec rewritten** (roadmap §6 V0) from the owner's brief: deliverables 1–10, the resources to evaluate first
  (named by the owner, not yet opened: UNVERIFIED), on-device and privacy priorities, model size secondary.

## Trade-offs

- **Complexity added:** none in code. The roadmap's V0 is now L, not M: a working engine with a runtime dependency,
  model download, microphone permission and benchmarks, rather than a spike.
- **Who benefits / how often:** voice search and live follow serve every memorizing family member; V0 itself is
  infrastructure.
- **Rejected cheaper options:** keeping v2's order (Hifz before AI), which the owner overrode; a go/no-go spike,
  which the owner rejected.
- **Ongoing cost:** an ML runtime and model files to keep working across iOS releases; benchmark fixtures to
  maintain.

## Changes

- `Documentation/agents/quran-prioritized-roadmap.md`: version-3 note, §5 table, §6 V0 and V1–V3, §7 D4.
- `Documentation/agents/quran-roadmap-progress.md`: Handoff, Next steps, milestone rows, owner decisions.

## Tests

- **No new tests:** documentation only.

## Validation

- **Verified:** the roadmap and tracker name the same order; `make guardrails` (see the commit).
- **Not verified:** the owner-named resources (URLs) were not opened in this session.

## Release

- **Commit:** see `git log` for `docs(roadmap): v3 order`.
- **TestFlight:** none (docs only).
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- C2 slice c2, then V0, then V1 (progress tracker, Next steps).
- Ask D1 and D2 before H1.
