# ADR-0001 · Foundation, seed selection and architecture

- **Status:** Accepted 2026-11-25. The owner chose repository home option A ("Nested in quran repo", §6)
- **Date:** 2026-11-25
- **Evidence:** [01-source-evaluation.md](01-source-evaluation.md)

## 1. Context

We are building a native SwiftUI app that teaches Quranic Arabic, from zero literacy to reading and early
comprehension, for children and adults, offline and private. The provisional plan was: Noorine as the native seed,
mahfuz for Qaida/Tajweed, ayyat for AI, QuranicWords for vocabulary, Antura for children's pedagogy. We already own
a modular Swift Quran reader (`nulltuple/quran`, QuranEngine).

## 2. Decision summary

1. **No candidate is forked as the seed.** Start a **new SwiftUI app plus a new learning Swift package** that depends on
   the existing QuranEngine modules. Pull specific, licensed pieces from candidates (§4).
2. **Repository home (recommended):** inside `nulltuple/quran` as a **separate nested package** `ArabicLearning/` and app
   `Apps/ArabicLearning/`. The reader's `Package.swift` and deployment target stay untouched. (Alternative in §6.)
3. **Content is compiled at build time** (Python tools in `Tools/`, like the existing word-data pipeline) into a
   versioned, read-only `learning-content.sqlite`. The app ships no Python and no network dependency for core learning.
4. **Pronunciation v1 = verified reference audio + record-and-compare, with no automated scoring.** Speech recognition is
   a time-boxed research spike with an explicit go/no-go; synthesis is parked.
5. **One curriculum and one adaptive engine; child/adult is a presentation profile**, never separate content or progress.
6. **Dependencies:** GRDB (already used), swift-fsrs (new, MIT, zero deps). Nothing else in v1. Accepting this ADR does not approve swift-fsrs:
   AGENTS.md §6 still requires owner approval when L2 adds it.

## 3. Challenge to the provisional recommendation

| Provisional role | Finding in source | Decision |
|---|---|---|
| Noorine = native seed | MSA conversational syllabus (café dialogue, "I am a student"); 1 empty test; 2,000-line views; OCR-based "handwriting recognition" with `contains` matching; generic `SFSpeechRecognizer`/`AVSpeechSynthesizer`; TTS-like audio of unknown provenance; Xcode-project-only, watch + widgets + live activities | **Rejected as seed.** Take only the stroke dataset and `StrokeGuideOverlay` (MIT). A fork would cost more to delete than to build clean |
| mahfuz = Qaida/Tajweed reference | Real 14-stage, ~70-lesson typed curriculum and 16 rules — but TypeScript, zero tests, no audio wired into lessons, no LICENSE file | **Kept as structural reference**; our lessons are re-authored. Ask the author for a LICENSE before copying anything verbatim |
| ayyat = native AI reference | ASR pipeline is real (Whisper/FastConformer Core ML), but its pronunciation verdict uses Apple Speech and **accepts ص→س, ط→ت, ق→ك**; FastConformer weights `license:other`; no LICENSE file | **Demoted** to reference for the Core ML audio front-end (log-mel, CTC) and for the progressive-substitution reading idea. Not an AI-tutor reference |
| QuranicWords = vocabulary reference | Excellent pipeline and data, but GPL-3.0 code **and** dataset | **Kept as method + cross-check.** We regenerate lemma frequency and ordering from QUL morphology with our own tool unless the owner accepts GPL |
| Antura = children's pedagogy | Mature pedagogy and TeacherAI designs (BSD-2); CC-BY human letter × harakat recordings; MSA kids' vocabulary | **Kept**, and upgraded: its letter audio is the only openly licensed human recording set found (audition required) |
| (not in the provisional plan) | quran-transcript: deterministic, tested Hafs phonetizer with sifat and tajweed rules (MIT) | **Added** as the phonetic foundation (build-time) |
| (not in the provisional plan) | Our own QuranEngine: verified word identities, EN/BN meanings, word timings, audio, fonts, downloader; every module is a library product | **Primary foundation** |
| TajweedFormer (spec's first prototype) | Closed encrypted core, API key, revocable no-profit license that forbids benchmarking other models with it | **Rejected** |

## 4. Architecture

### 4.1 Layout (recommended monorepo option)

```
nulltuple/quran
├── Package.swift                      # QuranEngine — unchanged (iOS 15)
├── Core/ Model/ Data/ Domain/ UI/ Features/   # unchanged
├── ArabicLearning/                    # NEW nested package (iOS 17), depends on .package(path: "..")
│   ├── Package.swift
│   └── Sources/
│       ├── LearningModel/             # pure types: Skill, Lesson, ExerciseSpec, Attempt, Evidence, Profile
│       ├── LearningContent/           # read-only GRDB access to learning-content.sqlite (+ QuranKit identities)
│       ├── LearningEngine/            # prerequisite DAG, mastery, FSRS bridge, session planner, placement
│       ├── ExerciseKit/               # deterministic generators + graders (no UI)
│       ├── LearningPersistence/       # learner state (GRDB, per-profile, migrations, export)
│       ├── LearningAudio/             # reference-audio resolver + recorder/compare (AVAudioEngine)
│       ├── ArabicScript/              # letters, joining forms, diacritics, grapheme clusters (tested)
│       └── LearningUI/                # SwiftUI renderers, PresentationProfile, tracing canvas
├── Apps/ArabicLearning/               # NEW app target (own bundle id, own scheme, own release lane)
└── Tools/learning/                    # NEW content compiler (Python, `python3 -I`), validators, tests
```

Rules: `ArabicLearning` may import `QuranKit`, `QuranText`, `QuranTextKit`, `WordTextService`, `QuranAudio`,
`QueuePlayer`, `QuranAudioKit`, `NoorFont`, `SQLitePersistence`, `BatchDownloader`, `Utilities`, `VLogging`.
It must not import `Features/*`, `NoorUI` page-reader views, `CoreDataPersistence`, `AuthenticationClient` or MobileSync.
QuranEngine never imports ArabicLearning. A shared extension (e.g. a public initializer) goes into QuranEngine as a small,
backward-compatible change with its own tests.

### 4.2 Shared packages with the reader

Share now (already libraries): identities, Uthmani text, word meanings/translit, audio playback and timings, fonts,
downloader, logging. Candidate to **promote later** into QuranEngine only when the reader needs it: `ArabicScript`
(letter/diacritic utilities) and the word-morphology lookup. Nothing learning-specific goes into the reader.

### 4.3 Content pipeline

```
QUL / Quran.com sources (pinned sha256) ─┐
quran-transcript phonetizer (pinned) ────┤
authored curriculum YAML (in git) ───────┼─► Tools/learning/compile.py ─► learning-content.sqlite (+ manifest.json)
Noorine stroke JSON (MIT) ───────────────┤        └─ validate.py: canonical refs, Unicode, prerequisites,
Antura letter audio (CC-BY, auditioned) ─┘           accepted answers, audio existence, rights column per row
```

Tables (v1): `letter`, `letter_form`, `stroke`, `syllable` (letter × mark, with audio ref), `skill`, `skill_prereq`,
`lesson`, `lesson_step`, `exercise_template`, `quran_word_ref` (sura, ayah, word → existing identity), `lemma`, `root`,
`word_lemma`, `phonetic_plan` (sura, ayah, word, mode wasl/waqf, phonemes, rule spans, options hash, tool version),
`tajweed_span`, `audio_asset` (id, kind, path/url, voice, context, checksum, provenance, license, review_status),
`source` (name, version, sha256, license). Learner state lives in a separate per-profile DB; content upgrades never touch it.

### 4.4 One engine, two presentations

- **Skills** are the unit of evidence: e.g. `letter.recognize.ب`, `letter.form.ب.medial`, `sound.discriminate.ح-ه`,
  `syllable.decode.fatha`, `word.decode.unseen.cvc`, `lemma.meaning.رَبّ`, `tajweed.identify.ikhfa`.
- **Lessons** declare the skills they teach and assess; a lesson's steps are `explain → demonstrate → guided → independent
  → check`. Exercises come from templates + deterministic seeded generators (Antura question-builder style), so the same
  item set is reproducible in tests.
- **Mastery:** per skill, a Beta-style evidence counter (successes/attempts with recency decay) gives `notAssessed /
  learning / uncertain / mastered`. Unscorable attempts (no audio, skipped) are recorded as `uncertain`, never wrong.
  FSRS (swift-fsrs) schedules recall items only (letters, forms, lemma meanings).
- **Session planner:** due FSRS reviews → weakest unlocked skills → next lesson; caps by profile session length.
- **PresentationProfile** (environment value): `child` = 3–7 min sessions, 4–6 items per step, larger targets, one
  instruction sentence, optional celebration/mascot, no timers; `adult` = 5–20 min, denser steps, grammar notes,
  transliteration fades faster. Lesson text has a required `adult` string and an optional `child` override. Items,
  answers, skills and progress are identical.

### 4.5 Pronunciation stack (v1)

`PronunciationPlan` (from `phonetic_plan`) → `ReferenceAudioResolver` returns `reference(asset)` or `unavailable`.
Never falls back to TTS. Recorder captures the learner (on device, discarded unless saved), shows both waveforms and
replays A/B. Self-assessment ("same / not sure / different") feeds evidence with low weight. Automatic correction stays
off until the research gate (roadmap R1) passes per error category.

## 5. Consequences

- **Pros:** maximal real reuse (our verified data pipeline is stronger than anything in the candidates); no deletion
  work; the reader's binary, schema and iOS 15 target are untouched; licensing is clean by construction.
- **Cons:** all UI is new (≈ the same effort as refactoring Noorine's monolithic views); speech AI is deferred, so v1 has
  no "AI teacher"; Quranic letter audio depends on auditioning Antura recordings or commissioning a qualified reciter.
- **Reversibility:** the nested package can be moved to its own repository later with `git subtree split`.

## 6. Repository home (decided: A)

| Option | Pros | Cons |
|---|---|---|
| **A. Nested package in `nulltuple/quran` (recommended)** | Atomic changes to shared modules; reuses Tools, CI, agent contract, trail, data builders; no fork needed | Repo grows; needs a second release lane; agents must respect two apps |
| B. New repo (e.g. `nulltuple/quran-arabic`) depending on QuranEngine by pinned git revision | Clean separation; independent history | Shared-module changes need two PRs and a pin bump; word-data build tools must be duplicated or invoked cross-repo |
| C. Fork Noorine | Fastest first screenshot | Rejected (§3) |
