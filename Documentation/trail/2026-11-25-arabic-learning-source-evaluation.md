# Arabic learning app: source evaluation, ADR and cut-scope roadmap

- **Date:** 2026-11-25
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** docs
- **Status:** shipped
- **Related:** [prioritized Quran roadmap](2026-11-24-prioritized-quran-roadmap.md) (reader roadmap, unaffected)

## Context

The owner is starting a standalone SwiftUI Quranic Arabic learning app for children and adults. They asked for an
"exhaustive source-level evaluation" of 12 repositories (Noorine, mahfuz, ayyat, QuranicWords, Antura, Antura_arabic,
tadabbur, OpenArabic, swift-fsrs, tajweedformer-apple, quran-muaalem, quran-transcript) and of this repository. They
asked the evaluation to "adversarially challenge" the provisional plan of using Noorine as the native seed. They also
asked to "cut scope to keep things simple and manageable or reorder milestones". During the work they asked to filter
out useless repositories before reading deeply, to save tokens. After the evaluation they chose "Nested in quran repo" for the app's
home.

## Decisions

- **No candidate is forked.** The learning app is a new nested package `ArabicLearning/` plus `Apps/ArabicLearning/`
  on top of the QuranEngine library products. Evidence and alternatives are in
  [ADR-0001](../ArabicLearning/02-ADR-0001-foundation-and-architecture.md).
- **v1 scope cut:** units 1–7, a Quran bridge (Al-Fatihah and short surahs), tajweed foundations and about 300 lemmas.
  Pronunciation is reference audio plus record-and-compare. Recognition is the time-boxed research track R1.
  Synthesis, sync, grammar/rhetoric, macOS and the LLM tutor are parked
  ([03](../ArabicLearning/03-spec-roadmap-risks.md) §2).
- **Low-cut filter:** Antura_arabic (archived, superseded), OpenArabic (server platform for classical texts) and
  tadabbur (no license, no AI code) were cut on metadata before any deep reading.

## Trade-offs

- **Complexity added:** four Markdown files under `Documentation/ArabicLearning/` and this entry. No code, dependencies,
  permissions or persisted state.
- **Who benefits / how often:** future agents and the owner, once per learning-app milestone.
- **Rejected cheaper options:** forking Noorine. It gives a faster first screenshot, but it carries an MSA syllabus, zero tests and
  speech paths the spec forbids. A separate repository was also rejected: shared-module changes would need cross-repo pin bumps.
- **Ongoing cost:** the docs must be kept in sync as milestones land. A second app in this repo adds review and release
  surface from L0 onward.

## Changes

- `Documentation/ArabicLearning/01-source-evaluation.md`: evaluation matrix, file-level findings, licensing.
- `Documentation/ArabicLearning/02-ADR-0001-foundation-and-architecture.md`: accepted decision and module layout.
- `Documentation/ArabicLearning/03-spec-roadmap-risks.md`: v1 scope, component inventory, milestones L0–L7 + R1, risks.
- `Documentation/ArabicLearning/HANDOFF.md`: instructions for the session that starts L0.
- `Documentation/trail/README.md`: index line.

## Tests

- **No new tests:** documentation-only change. No source, tooling or package files changed.

## Validation

- **Verified:** findings cite files read in shallow clones of each candidate at the commits listed in 01 §1–2. The model
  licenses were read from the Hugging Face model API (`tarteel-ai/whisper-tiny-ar-quran` apache-2.0,
  `Muno459/fastconformer-quran` other, `obadx/muaalem-model-v3_2` mit). `make guardrails` was run before the commit
  (result in the final report).
- **Not verified:** no candidate test suite was executed (running downloaded code was blocked in that session); no LFS audio
  was downloaded or auditioned; no candidate app was built. `make format-lint`, the package test suites and the example
  builds were not run because no Swift, package or tooling file changed.

## Release

- **Commit:** see `git log` for `docs(arabic-learning): …`
- **Pushed:** origin/main
- **TestFlight:** none. The change is confined to docs and the trail (AGENTS.md §8 step 7).
- **iCloud / CloudKit schema:** unchanged

## Follow-ups

- Milestone L0 per [HANDOFF.md](../ArabicLearning/HANDOFF.md).
- Owner inputs: learning-app bundle id and App Store Connect app, swift-fsrs approval, QUL/Quran.com terms, GPL stance,
  a qualified reviewer or reciter.
