# Quran: roadmap v2 reconciles the Tarteel research with shipped work

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** docs
- **Status:** shipped
- **Related:** [2026-11-24-prioritized-quran-roadmap.md](2026-11-24-prioritized-quran-roadmap.md),
  [2026-11-25-m3-1-local-verse-collections-store.md](2026-11-25-m3-1-local-verse-collections-store.md),
  [2026-11-26-arabican-l5-quran-bridge-vocabulary.md](2026-11-26-arabican-l5-quran-bridge-vocabulary.md)

## Context

App: **Quran** only (no Arabican change). The owner asked to confirm where the Quran roadmap
stands ("we were at M3"), read Codex's Tarteel research
(`~/Downloads/Tarteel_Quran_Research_and_Implementation_Roadmap.html`, now in the repo at
`Documentation/agents/research/2026-11-26-tarteel-competitive-research.html`, sha256
`e2e06210c36a65d1360bc0245c026d3a38df625285c4b94d050c687c414df4f8`) and "update the full roadmap
... to build the best Quran app, not just for memorization, but for reading and comprehension",
keeping work modular for Arabican, reordering opinionatedly, and reinventing only when better
than what is openly available.

Status confirmed: M1 shipped (builds 955–959), M2 blocked on owner QUL downloads, M3.1 shipped
at `88b60523` (build 961), M3.2 next. `git log` shows no Quran commit after `dbeb4894`; the
later ones are Arabican L0–L7 and the one-simulator tooling change.

Code checks behind the corrections in roadmap §2:

- No tafsir support: `grep -rli "tafsir\|tafseer"` over the Swift sources finds only
  `UI/NoorFont/Sources/FontName.swift`, `UI/NoorUI/Sources/Font/FontName++.swift`,
  `UI/NoorUI/Sources/Features/Quran/QuranTranslationFootnoteChunk.swift`,
  `Features/QuranTranslationFeature/Sources/Translation+UI.swift`, `Model/QuranAudio/Sources/Reciter.swift`
  (font names and footnotes, no tafsir content).
- Editions: `Model/QuranKit/Sources/Reading.swift:11-17` (`hafs_1405` … `indoPak`);
  `Example/QuranEngineApp/Classes/Container.swift:38` `remoteResources: ReadingRemoteResources? = nil`.
- Two-page layout exists: `Features/QuranPagesFeature/Sources/QuranPaginationView.swift`,
  `Features/MoreMenuFeature/Sources/MoreMenuModel.swift`.
- CloudKit-capable stack: `Data/CoreDataPersistence/Sources/CoreDataStack.swift:123`
  (`NSPersistentCloudKitContainer`), `Container.swift:91` (`supportsCloudKit { false }`).
- Arabican's FSRS wrapper: `ArabicLearning/Sources/LearningEngine/ReviewScheduler.swift` (44 lines).
- `SpeechTranscriber` is declared in the iOS 27.2 SDK's `Speech.swiftmodule`; Arabic on-device
  support UNVERIFIED.
- Translation list endpoint `/data/translations.php`
  (`Domain/TranslationService/Sources/TranslationNetworkManager.swift:12`); whether it lists
  tafsirs is UNVERIFIED.

## Decisions

- **Order:** reader and comprehension (F1, R1, C1, F2, C2) before Hifz (H1–H7), Hifz before AI
  (V0–V3). Codex put reader and comprehension last (Q16); the owner asked for reading and
  comprehension too, and those items are cheap because the code or data pipeline exists.
- **Area IDs** (F/R/C/H/V/P) instead of renumbering M4+: reordering never renumbers, and old M
  ids in trail entries stay meaningful through the mapping table (roadmap §8).
- **Learning records in Core Data**, CloudKit-compatible, not a GRDB file like Arabican's: the
  existing stack can sync through `NSPersistentCloudKitContainer`, so P1 needs no second sync
  engine.
- **Passage-level scheduling** (FSRS if the owner allows swift-fsrs in the root package, else a
  ladder): a hafiz revises passages, not words; word mistakes drive repair.
- **No standalone primitives milestone** (Codex Q2): primitives ship inside H1 with H2's first
  slice, per AGENTS.md's release gate.
- **Move, not copy, `ArabicScript`** to QuranEngine when H2 needs graphemes (first-letter hints);
  Arabican then imports it. Morphology becomes a shared full-Quran database (C2) that Arabican
  can switch to later.
- **F1 Bookmarks tab shape decided** (was an open owner question): sync build's collections list,
  then the page-bookmarks section. Reversible UI, so decided per AGENTS.md "conservative option".
- **Excluded:** Tarteel import, multiple riwayat, family/teacher backend, leaderboards, LLM
  explanations of scripture, generated Quran audio, Pencil, desktop/watch/TV, prayer times.
  **Parked:** phonetic/tajweed assessment, recording retention, static tajweed in the translation
  view, local multi-profile, dual-language meanings.
- Stored the research HTML in the repo so later sessions can consult it (no scripts in it,
  156 KB).

## Trade-offs

- **Complexity added:** documentation only: roadmap rewritten (one file), progress table and
  handoff updated, one 156 KB research HTML, this entry. No code, dependency or permission.
- **Who benefits / how often:** every later Quran session; the owner sees one ordered plan.
  Features flagged as likely rarely used inside the plan: spot-test timers, Khatmah presets
  beyond Ramadan and Friday, widgets.
- **Rejected cheaper options:** appending Codex's Q list beside M1–M15 (two conflicting
  backlogs); renumbering M4+ (breaks old trail references).
- **Ongoing cost:** keep the roadmap and progress file in step each slice; the research HTML is a
  snapshot and will go stale (dated in its name).

## Changes

- `Documentation/agents/quran-prioritized-roadmap.md`: v2 spec (status, corrections, product
  shape, shared architecture, ordered milestones, specs, owner decisions, id mapping).
- `Documentation/agents/quran-roadmap-progress.md`: v2 milestone rows, handoff, next steps.
- `Documentation/agents/research/2026-11-26-tarteel-competitive-research.html`: Codex's report.
- `Documentation/trail/README.md`: index line.

## Tests

- **No new tests:** documentation-only change; no source, tool or test file changed.

## Validation

- **Verified:** code facts above by `grep`/`sed` at `a3f5f5ef`; `make guardrails` before commit
  (result line in the commit session).
- **Not verified:** everything marked UNVERIFIED in the roadmap (edition download URLs, tafsir in
  the translations endpoint, Arabic `SpeechTranscriber` support, QUL mutashabihat datasets).

## Release

- **Commit:** see `git log` (docs-only)
- **Pushed:** origin/main
- **TestFlight:** none; documentation-only change (AGENTS.md step 7 exception).
- **iCloud / CloudKit schema:** unchanged

## Follow-ups

- F1 is next (progress file, Next steps 1).
- Owner decisions D1–D5 (roadmap §7); ask D1 and D2 before H1/H2.
