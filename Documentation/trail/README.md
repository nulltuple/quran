# Change trail

Every feature, fix, refactor and tooling change has an entry here. Agents write the entry while
they work and commit it with the change, so the next agent can recover the context, decisions
and trade-offs without the original conversation.

The trail starts on 2026-11-24, when this fork became agent-only. Earlier history is upstream
QuranEngine work: read it with `git log` and the pull requests it links (`quran/quran-ios`).

## Rules

- One file per change: `YYYY-MM-DD-<kebab-slug>.md`, copied from [TEMPLATE.md](TEMPLATE.md).
  Every template section is required; `Tools/check-agent-guardrails.sh` rejects a code commit
  without a complete entry.
- Commit the entry with the code, and name it in the commit message: `Trail: Documentation/trail/<file>.md`.
- Recording release facts afterwards (pushed SHA, TestFlight build) is a trail-only commit:
  `docs(trail): record TestFlight build for <slug>`.
- Never rewrite an old entry's history. Add a new entry and set the old one's **Status** to
  `superseded by <new entry>`.
- No secrets, tokens, personal data or user content.

## Finding context

```sh
grep -ril "<area or symbol>" Documentation/trail        # entries that touched an area
ls Documentation/trail | sort | tail -20                # most recent work
grep -rn "^- \*\*Status:\*\* in-progress" Documentation/trail   # unfinished work
grep -rn -A4 "^## Follow-ups" Documentation/trail       # open follow-ups
```

## Index

Newest first. Add one line per entry.

- [2026-11-26 — Quran roadmap v3 order: Quran AI Engine and voice search before Hifz](2026-11-26-quran-roadmap-v3-order.md)
- [2026-11-26 — Quran C2: word study occurrence list that moves the reader and returns](2026-11-26-c2-word-occurrences.md)
- [2026-11-26 — Quran C2: full-Quran morphology database and the word study sheet](2026-11-26-c2-word-study-sheet.md)
- [2026-11-26 — Quran C1: English Ibn Kathir and Bengali Ahsanul Bayaan tafsir packs](2026-11-26-c1-english-bengali-tafsir.md)
- [2026-11-26 — Quran F2: JSON backup and restore with preview, merge or replace](2026-11-26-f2-backup-restore.md)
- [2026-11-26 — Quran C1: tafsir sheet from the ayah menu, Arabic tafsir passages](2026-11-26-c1-tafsir-sheet.md)
- [2026-11-26 — Quran R1: downloadable Mushaf editions from verified files.quran.app packs](2026-11-26-r1-mushaf-editions.md)
- [2026-11-26 — Quran F1 follow-up: collection and note marks in the no-sync translation view](2026-11-26-f1-collection-marks-no-sync.md)
- [2026-11-26 — Quran F1: collections and Favorites in the shipping (no-sync) build](2026-11-26-f1-local-collections-ui.md)
- [2026-11-26 — Quran: roadmap v2 reconciles the Tarteel research with shipped work](2026-11-26-quran-roadmap-v2.md)
- [2026-11-26 — Arabican L7: progressive substitution, Bengali meanings, release gate](2026-11-26-arabican-l7-polish.md)
- [2026-11-26 — Both apps: agents use only the iPhone 18 Pro Max simulator](2026-11-26-one-simulator-iphone-18-pro-max.md)
- [2026-11-26 — Arabican L6: tajweed foundations from two cross-checked sources](2026-11-26-arabican-l6-tajweed-foundations.md)
- [2026-11-26 — Arabican L5: Quran bridge reader, record and compare, top-300 vocabulary](2026-11-26-arabican-l5-quran-bridge-vocabulary.md)
- [2026-11-26 — Arabican L4: vowels, marks, unseen-word checks and placement](2026-11-26-arabican-l4-reading-and-placement.md)
- [2026-11-25 — Quran: SQLite user-data stores keep their file on open errors](2026-11-25-sqlite-keep-user-data-on-open-errors.md)
- [2026-11-26 — Arabican L3: letter audio, joining forms, find-in-word, tracing](2026-11-26-arabican-l3-literacy-audio-tracing.md)
- [2026-11-25 — Arabican L2: profiles, learner store, engine core, practice](2026-11-25-arabican-l2-engine-profiles-practice.md)
- [2026-11-25 — Arabican L1: content compiler pilot, ArabicScript, LearningContent](2026-11-25-arabican-l1-content-compiler.md)
- [2026-11-25 — Arabican L0: second app bootstrap, two-app tooling and guidelines](2026-11-25-arabican-l0-bootstrap.md)
- [2026-11-25 — Arabic learning app: source evaluation, ADR and cut-scope roadmap](2026-11-25-arabic-learning-source-evaluation.md)
- [2026-11-25 — M3.1: no-sync personal data audit, local verse collections store](2026-11-25-m3-1-local-verse-collections-store.md)
- [2026-11-24 — M1.5: transliteration line in word-by-word meanings](2026-11-24-m1-5-word-by-word-transliteration.md)
- [2026-11-24 — M1.4: word-by-word localization, VoiceOver and large-text layout](2026-11-24-m1-4-word-by-word-localization-accessibility.md)
- [2026-11-24 — M1: verified canonical word data, unified word pointer, media-clock fixes](2026-11-24-m1-canonical-word-data.md)
- [2026-11-24 — Prioritized Quran competitive roadmap](2026-11-24-prioritized-quran-roadmap.md)
- [2026-11-24 — Word-by-word recitation highlighting and word meanings from QUL](2026-11-24-word-by-word-recitation.md)
- [2026-11-24 — Agent-only contract, change trail, Quran rebrand and TestFlight path](2026-11-24-agentic-contract-rebrand-testflight.md)
