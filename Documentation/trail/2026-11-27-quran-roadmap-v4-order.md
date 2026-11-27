# Quran roadmap v4 order: the voice track before Hifz, split where Hifz is needed

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** docs
- **Status:** shipped
- **Related:** [roadmap v3 order](2026-11-26-quran-roadmap-v3-order.md) (the order this revises),
  [V0 model download](2026-11-27-v0-model-download.md) (the state V0 ended in)

App: **Quran** (roadmap only; no code).

## Context

The owner asked (2026-11-27): "do you think it is worth pulling the AI related stuffs first, such as V0 → V1 → V2a →
V2b → V3a → V3b → V4 → V5 → H1–H7 → remaining milestones. Only reorder the milestones if you agree." The roadmap had
no V2a, V2b, V3a, V3b, V4 or V5 (`grep` over `Documentation/` found none); v3's order was V1 → H1+H2 → V2 → H3–H5 →
H7 foundation + V3 → remaining.

## Decisions

- **Agreed to pull the voice track forward, as far as dependencies allow.** For: V0's engine, its streaming plan and
  the alignment code are fresh; the engine already does verse identification and word alignment, so live follow and
  recite-and-check are mostly product work on it; they are useful to a memorizing household without a learning store.
  V1 first is unchanged.
- **V2 and V3 split** (the IDs the owner used, defined here): V2a live follow in the reader and V3a recite-and-check
  (mistakes shown, nothing stored) need no Hifz code. V2b (automatic reveal in Practice) cannot exist before H2's
  practice mode, and V3b (mistakes recorded as evidence, dispute, heatmap) needs H1's store and H7's heatmap. So
  V2b and V3b stay after H2 and H7. Building them first would mean building H2/H7 under another name.
- **V4 and V5 after the Hifz loop, not before it (disagreed with that part).** They did not exist; the nearest items
  were parked (P3): phoneme/vowel and tajweed-rule assessment, "research only after V3, needs qualified reviewers".
  They are now V4 (phoneme and vowel assessment, research first, lab only) and V5 (tajweed feedback), both gated on a
  qualified reviewer before any tester sees a verdict. Placing them before H1 would delay the core memorization loop by
  two large research milestones whose output cannot reach testers until a reviewer is found.
- **Order:** V1 → V2a → V3a → H1+H2 → V2b → H3–H5 → H7 foundation + V3b → V4 → V5 → remaining (P1, H6, H7 completion,
  C3, P2, M2). Recording retention and replay stays parked.

## Trade-offs

- **Complexity added:** none in code. Two more milestones before H1 (V2a, V3a, both L): the core Hifz loop arrives
  later, and D2 (swift-fsrs) can wait until then.
- **Who benefits / how often:** V2a serves anyone reciting from the page (daily for a memorizer); V3a serves
  self-testing. Both depend on device performance the owner has not measured yet (checklist item 23): if the phone's
  memory or latency is poor, V2a's streaming is the first place it shows.
- **Rejected options:** the owner's literal order (V2b/V3b before H, V4/V5 before H; reasons above); keeping v3's order
  (H1+H2 right after V1), which leaves the engine context to go cold for three milestones.
- **Ongoing cost:** more milestones in the tracker; V2a and V3a each need held-out evaluation fixtures.

## Changes

- `Documentation/agents/quran-prioritized-roadmap.md`: version-4 note, §5 table (rows 7–16), parked list, §6 voice
  track (V1, V2a, V3a, V2b, V3b, V4, V5), §8 ids.
- `Documentation/agents/quran-roadmap-progress.md`: Handoff order, Next steps, milestone rows.

## Tests

- **No new tests:** documentation only.

## Validation

- **Verified:** the roadmap §5 table, §6 voice track and the tracker name the same order; `make guardrails` (see the
  commit).
- **Not verified:** nothing to run.

## Release

- **Commit:** see `git log` for `docs(roadmap): v4 order`.
- **TestFlight:** none (docs only).
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- V1, then V2a, then V3a (tracker, Next steps). Ask D2 before H1.
