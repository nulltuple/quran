# 03 · Product spec (cut scope), component inventory, roadmap and risks

- **Date:** 2026-11-25 · **Supersedes:** the proposed spec v1.0 (`quranic_arabic_learning_spec.html`, M0–M18)
- **Companion docs:** [01-source-evaluation.md](01-source-evaluation.md), [02-ADR-0001-foundation-and-architecture.md](02-ADR-0001-foundation-and-architecture.md)
- **App:** **Arabican** (App Store Connect "Arabican", bundle `com.nulltup.arabican`, project `Apps/Arabican/`,
  package `ArabicLearning/`). This is not the Quran reader (MemQuran); see AGENTS.md "Two apps, one repository".
- **Licensing (owner, 2026-11-25):** personal, non-commercial use. Licenses and terms of sources (GPL, no LICENSE
  file, QUL/Quran.com terms) **do not restrict reuse** and block no release. Keep the `source` table and attribution
  for traceability; revisit only if a commercial or public release is planned. Where this document says "reference
  only", "re-author" or "GPL" for licensing reasons, direct reuse is now allowed when it is the better engineering
  choice.

## 1. What we are building (v1)

An offline iPhone/iPad app that takes a learner from **zero Arabic literacy to reading Al-Fatihah and short surahs of
Juz Amma**, with **the most frequent Quranic words understood in context** and **foundational tajweed recognized by eye
and ear**. Same curriculum for children and adults; separate local profiles.

**v1 outcomes (the release gate is about these, not lesson counts):**
1. Recognize all letters in all joining forms; discriminate the hard pairs by sound (ح/ه, ع/ء, ص/س, ط/ت, ق/ك, ذ/ز/ظ, ض/د).
2. Decode **unseen** fully vowelized Quran words (short/long vowels, sukun, shaddah, tanwin, dagger alif, hamzat al-wasl).
3. Read Al-Fatihah and a set of short surahs along with authentic recitation, word by word.
4. Know the ~300 most frequent lemmas in context (EN and BN meanings).
5. Identify noon/meem sakinah rules, qalqalah and the main madd types in text and audio.

## 2. Scope changes from the proposed spec (and why)

| Proposed | Now | Reason |
|---|---|---|
| 24 units, ~350 lessons, M0–M18 | v1 = units 1–7 + a Quran bridge + tajweed foundations + top-300 vocabulary (~90–110 lessons) | Ship a usable, reviewed core; mastery not lesson count |
| Automated pronunciation correction (M7/M8) in the main path | **Record-and-compare + reference audio**, no scoring. Recognition = research track R1 with go/no-go | No candidate is validated on beginners/children; TajweedFormer license is unusable; muaalem is 660M params with no iOS path |
| Controlled speech synthesis (M16) | **Parked** | Highest-risk item; reference recordings cover v1 needs |
| Handwriting recognition | **Stroke-guided tracing** with a deterministic path-following check (Noorine stroke data); no OCR/ML | Noorine's Vision OCR approach is unreliable for single letters |
| Family sync, CloudKit, reminders (M15) | **Local profiles + export/import file** only | Removes entitlements, schema deployment and conflict handling |
| Full nahw/sarf, i'rab, balaghah, tafsir-assisted analysis (M13/M14, units 19–24) | **Parked**; v1 shows morphology facts (root, lemma, POS, verb form) on tapped words | Large authoring and review burden; comprehension starts with vocabulary |
| Full Quran reading progression (M17) | Reading mode works for any ayah via the shared reader data; **guided** lessons only for Al-Fatihah + selected Juz Amma surahs | Guided content for 114 surahs is an authoring project, not engineering |
| "Interactive AI tutor" | **Deterministic adaptive tutor** (session planner + targeted remediation). LLM explanations parked; if revisited, on-device only and constrained to approved content | Spec forbids AI authority; privacy; offline |
| macOS, tvOS, watchOS, IndoPak script | Parked | Not needed for outcomes |
| Placement test | Kept, simplified: a 10-minute adaptive check that unlocks units 1–7 by evidence | Serves readers who already decode |

## 3. Reusable-component inventory

| # | Component | Source (exact path) | License | Action | Target module | Milestone |
|---|---|---|---|---|---|---|
| 1 | Sura/ayah/word identities | `nulltuple/quran` `Model/QuranKit` | Apache-2.0 | Import | (dependency) | L1 |
| 2 | Uthmani text DB | `Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db` via `QuranTextKit` | Apache-2.0 / source terms | Import | LearningContent | L1 |
| 3 | Word meanings EN/BN + translit, token layout | `word_by_word.db` built by `Tools/build-qul-word-data.py`; `WordTextService` | ours / QUL terms | Reuse builder output in content compile | LearningContent | L1 |
| 4 | Word timings (contextual highlight) | `qul_afasy.db`, `AudioTimingPersistence`, `QuranAudioKit` | ours / QUL terms | **Imported (L5):** `qul_afasy.db` timings compiled for the bridge suras; Afasy surah MP3s bundled byte for byte (`content/recitation.toml`); AVFoundation players in LearningUI (QuranAudioKit not needed) | LearningContent | L5 |
| 5 | Quran fonts | `UI/NoorFont/Sources/Resources/UthmanicHafs1B Ver13.ttf` | KFGQPC terms | Import | LearningUI | L2 |
| 6 | Teaching fonts | Scheherazade New / Amiri / Noto Naskh Arabic (fetch from upstream releases, not from candidates) | SIL OFL 1.1 | Add | LearningUI | L2 |
| 7 | Downloader | `Data/BatchDownloader` | Apache-2.0 | **Not needed (L6):** every recording is bundled (3.3 MB) | LearningContent | — |
| 8 | Stroke data, 30 letters × forms | Noorine `Core/course_content.json` → `letters[].strokes`, `drawingInstructions` | MIT | Convert to YAML/SQLite with attribution | Tools/learning | L1 |
| 9 | Stroke guide animation | Noorine `Features/Learning/Components/Drawing/StrokeGuideOverlay.swift`, `DrawingCanvasModel.swift` | MIT | **Not ported (L3):** a static numbered guide (`TracingCanvas`) and `TraceChecker` replace it | LearningUI | L3 |
| 10 | Diacritic helpers | Noorine `Core/DiacriticHelper.swift` | MIT | Port selectively; rewrite with tests for Quranic marks | ArabicScript | L1 |
| 11 | Qaida stage structure | mahfuz `packages/shared/src/data/learn/curriculum.ts`, `types/learn.ts`, `alphabet.ts` | no LICENSE file | Reference only; re-author | curriculum YAML | L3–L4 |
| 12 | Tajweed rule list + per-ayah tajweed markup | mahfuz `apps/web/src/routes/tajweed.tsx`; source = Quran.com `uthmani_tajweed` API | — / Quran.com terms | **Used (L6):** fetched for the bridge suras (hashes in `05-tajweed-crosscheck.md`), the cross-check for #15 | Tools/learning | L6 |
| 13 | Letter × harakat human audio | Antura `Assets/_lang_bundles/arabic/Audio/Letters/*.wav` (LFS) | CC-BY-4.0 | **Imported (L3):** 140 clips, bundled; `Tools/learning/audio.py`, log `04-audio-audition.md` | LearningContent | L3 |
| 14 | Deterministic question builders | Antura `Assets/_core/_scripts/TeacherAI/QuestionBuilding/QuestionBuilders/*`, `AIEngines/VocabularySelectionAI.cs` | BSD-2 | Port designs to Swift generators | ExerciseKit / LearningEngine | L2–L4 |
| 15 | Hafs phonetizer, sifat, tajweed spans | quran-transcript `src/quran_transcript/phonetics/{phonetizer,moshaf_attributes,sifa,tajweed_rulses}.py` | MIT | **Used (L6):** pinned build-time tool (`e30c100`, `Tools/learning/tajweed.py`) for tajweed spans; `phonetic_plan` moves to R1 | Tools/learning | L6 (spans), R1 (phonetic plan) |
| 16 | FSRS scheduler | open-spaced-repetition/swift-fsrs | MIT | SPM dependency (pin exact version) | LearningEngine | L2 |
| 17 | Lemma frequency + curriculum ordering method | QuranicWords `tools/pipeline/qw/curriculum.py`, `dataset/words.json` | GPL-3.0 | **Used (L5):** our own counts and ranks (`Tools/learning/morphology.py`), diffed against the dataset; its EN/BN lemma glosses imported | Tools/learning | L5 |
| 18 | QUL morphology (roots, lemmas, stems) | qul.tarteel.ai `word-root.db`, `word-lemma.db`, `word-stem.db` (as ayyat's `scripts/morphology_ingest/ingest.py` documents) | QUL terms | **Replaced (L5)** by QAC v0.4 from `mustafa0x/quran-morphology` (public, no sign-in, same word numbering as ours on 6,233 of 6,236 ayahs) | Tools/learning | L5 |
| 19 | Progressive substitution reading | ayyat `ayyat/Services/Storage/VocabularyStore.swift:108-360` | no LICENSE file | Reimplement idea on our mastery | LearningUI | L7 |
| 20 | Core ML audio front-end | ayyat `ayyat/Services/Audio/LogMelFeatures.swift`, `FastConformerQuranASR.swift` (CTC decode) | no LICENSE file | Reference for R1 only | (spike) | R1 |
| 21 | Standalone Quran word audio | Quran.com `audio.qurancdn.com/wbw/<sss>_<aaa>_<www>.mp3` (seen in ayyat `WordAudioCache.swift:21`) | Quran.com terms (UNVERIFIED) | **Not needed (L5):** word segments of the bundled surah recordings play each word | — | — |
| 22 | Phoneme + sifat recognizer | obadx/quran-muaalem, HF `obadx/muaalem-model-v3_2` | QML 1.0 / card MIT | Spike: Core ML conversion + test set | (spike) | R1 |
| 23 | Quran-tuned Whisper | HF `tarteel-ai/whisper-tiny-ar-quran` | Apache-2.0 | Spike baseline (word-level only) | (spike) | R1 |

Explicitly **not** reused: Noorine audio, SRS, speech, OCR and views; mahfuz/Noorine letter mp3s; ayyat `PronunciationChecker`
logic, FastConformer weights, OIDC/API clients; TajweedFormer; OpenArabic; tadabbur; Antura_arabic.

## 4. Curriculum v1 (skills-first)

| Unit | Content | Key exercise families | Assessment (unseen items) |
|---|---|---|---|
| U1 Orientation | RTL, letters vs sounds, dots, how audio works | tap-along, listen-and-choose | — |
| U2 Letters | 28 letters + hamza; shape families (mahfuz `shapeFamily` idea), dots; letter name vs sound | recognize, sound→letter, odd-one-out, contrast pairs | letter ID by sound & sight |
| U3 Joining | 4 forms, 6 non-joiners, real shaping in words, tracing | form match, find-letter-in-word (Antura LettersInWord), tracing | form ID inside unseen Quran words |
| U4 Short vowels | fathah/kasrah/dammah, blending CV | syllable read, sound→syllable, vowel select | decode unseen CV / CVCV |
| U5 Long vowels | alif/waw/ya madd, dagger alif, duration contrast | long vs short discrimination | decode unseen words |
| U6 Marks | sukun, shaddah, tanwin, hamzat al-wasl, silent letters, sun/moon lam | mark spotting, decode | decode unseen multi-syllable Quran words |
| U7 Decoding | Quran words picked by the compiler from canonical text whose graphemes are all already taught | read-then-hear, word build | unseen-word decode test → unlocks Quran bridge |
| Q1 Quran bridge | Al-Fatihah, then short surahs (112–114, 108, 103, 110, 111…) | word-by-word listen/read, repeat, record & compare, word meaning | read-along checkpoints, meaning-in-context |
| T1 Tajweed foundations | makharij overview, noon/meem sakinah, qalqalah, madd types, waqf basics | identify rule in text (tajweed spans), listen-and-spot | rule ID on unseen ayahs |
| V1 Vocabulary | top ~300 lemmas, function words first, introduced alongside U4 onward | meaning recognition/recall, contextual sense, root family | in-context recall on unseen ayahs |

Authoring: curriculum YAML in git, written by agents from approved sources, **reviewed by a qualified teacher before
release** (owner arranges). LLMs never author Quran text, tajweed labels or accepted answers.

## 5. Roadmap (dependency-ordered, each milestone is a reviewable slice)

### 5.1 Status

Update this table when a milestone lands: status, date, trail entry, commit and the Arabican TestFlight build. Every
milestone ends with an Arabican TestFlight build (`make release-testflight-arabican`).

| ID | Status | Date | Trail entry | TestFlight (Arabican) |
|---|---|---|---|---|
| L0 | **Done** | 2026-11-25 | [2026-11-25-arabican-l0-bootstrap.md](../trail/2026-11-25-arabican-l0-bootstrap.md) | build 964 (0.1.0), commit `ada7ef40` |
| L1 | **Done** | 2026-11-25 | [2026-11-25-arabican-l1-content-compiler.md](../trail/2026-11-25-arabican-l1-content-compiler.md) | build 965 (0.1.0), commit `74b12b3c` |
| L2 | **Done** (VoiceOver/Dynamic Type smoke check open) | 2026-11-25 | [2026-11-25-arabican-l2-engine-profiles-practice.md](../trail/2026-11-25-arabican-l2-engine-profiles-practice.md) | build 967 (0.1.0), commit `d0e73d4e` |
| L3 | **Done** (articulation review and on-device checks open) | 2026-11-26 | [2026-11-26-arabican-l3-literacy-audio-tracing.md](../trail/2026-11-26-arabican-l3-literacy-audio-tracing.md) | build 971 (0.1.0), commit `0d3e4d48` |
| L4 | **Done** (internal alpha; teacher review, audio and accessibility checks open) | 2026-11-26 | [2026-11-26-arabican-l4-reading-and-placement.md](../trail/2026-11-26-arabican-l4-reading-and-placement.md) | build 973 (0.1.0), commit `62773dc7` |
| L5 | **Done** (foundational beta; teacher review of glosses and bridge lessons, recording on a device, accessibility open) | 2026-11-26 | [2026-11-26-arabican-l5-quran-bridge-vocabulary.md](../trail/2026-11-26-arabican-l5-quran-bridge-vocabulary.md) | build 975 (0.1.0), commit `b60940de` |
| L6 | **Done** (teacher review of explanations, decisions and spans; four rules without examples; accessibility open) | 2026-11-26 | [2026-11-26-arabican-l6-tajweed-foundations.md](../trail/2026-11-26-arabican-l6-tajweed-foundations.md) | build 977 (0.1.0), commit `f4f5ab48` |
| L7 | **Done** (owner cut export/import and attribution; reviewer risks 2, 6, 11 accepted open; VoiceOver, iPad and device checks open) | 2026-11-26 | [2026-11-26-arabican-l7-polish.md](../trail/2026-11-26-arabican-l7-polish.md) | see trail entry |
| R1 | Not started | | | |

L0 notes: swift-fsrs and quran-transcript test suites were **not** run (that would execute downloaded third-party
code outside a dependency build); swift-fsrs is verified when L2 adds and builds it, quran-transcript when L1 or L6
first runs it. Source pinning (sha256) moves to L1, where the compiler first reads sources.

L1 notes: authored content is TOML (`Tools/learning/content/`); the `stroke` table moved to L3 and `phonetic_plan` to L6
(their first consumers). Compiled DB: `ArabicLearning/Sources/LearningContent/Resources/learning-content.sqlite`;
rebuild with `python3 -I Tools/learning/compile.py`.

L2 notes: listen-choose moved to L3 (needs letter audio); Arabic glyphs use QuranEngine's Quran font, so the OFL
teaching fonts (inventory #6) are not added; learner data uses GRDB directly, never `DatabaseConnection` (it deletes
files on open errors).

L3 notes: Antura re-confirmed as the only source with every letter's name and letter × vowel recordings
(alternatives checked 2026-11-26, see the trail entry). Audition is automated and technical
(`04-audio-audition.md`: 140 accept, 0 reject, 49 defer); articulation is unverified until a qualified listener
reviews it (risk 2). Tracing covers isolated forms; the `stroke` table holds every form. Compiled suras grew to
1, 94, 97, 103, 108, 110–114 so every letter has a plainly written word. Form identification inside unseen
words moved to L4.

L4 notes: unit checks are compiler-made lessons (`u<N>.check`, skill `check.<unit>`) for U2–U7; they use only words from
`[quran] check_suras` (504 words never shown in practice) and no transliteration, and gate the next unit. Placement
asks the checks in order and records units passed (`placement` table). Decoding tests a real word's first syllable
by ear and by eye with the letter clips, plus marks by eye; whole-word decoding by ear waits for L5's recitation
audio. Two KFGQPC encoding facts fixed in `ArabicMark`: U+0656/0657/065E are staggered tanwin; U+0652 is the "never
read" circle on ا/و/ي, not a sukun (that is U+06E1). Form identification inside words was cut (find-in-word on
unseen words is U3's check). L5 must pick Quran-bridge suras from the practice list or move them out of the checks.

L5 notes: the Quran tab is the learning-mode reader for the bridge suras 1, 112, 113, 114, 108, 103, 110, 111
(practice suras; check words stay unseen): bundled Afasy recitation with the recited word highlighted, word sheet
(meaning EN/BN, transliteration, QAC parts with lemma, root, part of speech and Quran-wide count), and record and
compare per ayah (one temporary file, deleted when the reader closes; microphone permission approved by the owner).
Morphology is QAC v0.4 (`mustafa0x/quran-morphology`) instead of QUL's sign-in downloads; `Tools/learning/morphology.py`
ranks lemmas by Quran-wide count and diffs against QuranicWords (top 300: 290 found, 7 counts differ, 10 absent and
authored in `glosses.toml`). Two compiler-made units follow `u7.check`: U8 (one bridge lesson per sura: a recited
word by ear, a word's meaning in its ayah) and U9 (the top 300 lemmas, 10 per lesson). Vocabulary is not yet
interleaved with U4–U7 (the planner offers one next lesson); exercises are English only (the UI is English only).

L6 notes: tajweed spans for the 8 bridge suras come from quran-transcript `e30c100` (Hafs, murattal, 4-count
separated/joined/stop madds; each ayah read with a stop at its end), cross-checked with Quran.com's `uthmani_tajweed`
(log, pins and the three reviewed disagreements: [05-tajweed-crosscheck.md](05-tajweed-crosscheck.md)). 13 rules in 6
lessons (unit U9, after the bridge; vocabulary is now U10); 138 examples. Each rule has an explanation (after every
answer), its examples colored in the ayah, and a listening drill on the bundled recitation. Iqlab, meem idgham, meem
ikhfa and the soft madd have no example in the bridge suras and are not taught yet. No T1 unit check (too few
examples of some rules to hold any out); `phonetic_plan` moves to R1, its first consumer; the optional audio pack
(inventory #7) is not needed (all audio is bundled).

L7 notes (owner scope, 2026-11-26): built progressive-substitution reading (reader mode "In a line, known
words in Arabic": a word whose every lemma has a mastered `lemma.meaning.*` skill shows in Arabic inside the ayah's
word-by-word meaning; adjacent known words form one right-to-left run) and a per-profile meaning language (English
or Bengali: reader, word sheet and meaning exercises; UI stays English). **Cut by the owner:** profile export/import
and the licensing/attribution screen (the `source` table and trail keep attribution). Performance budgets in
`PerformanceBudgetTests` (simulator: practice start 37 ms, Quran list 3 ms, reader 1 ms). Accessibility: Dark Mode,
accessibility-large text and landscape checked on the iPhone 18 Pro Max simulator; VoiceOver, compact iPhone and iPad
not checked (one simulator only, AGENTS.md "Simulator"). Release gate: see §6; v1 is complete for personal use.

### 5.2 Milestones

| ID | Milestone | Depends on | Scope | Exit gate (evidence required) |
|---|---|---|---|---|
| **L0** | Bootstrap & verified baseline | owner picks repo home | Create `ArabicLearning/` package + `Apps/ArabicLearning` skeleton that builds; record reader baseline test result; with owner permission run swift-fsrs and quran-transcript tests and record output; pin sources (sha256); copy these docs in; trail entry | Reader suite result quoted and unchanged; learning app launches on simulator; no change to `Package.swift` of QuranEngine |
| **L1** | Content compiler pilot | L0 | `Tools/learning/compile.py` + `validate.py` + tests; tables `letter`, `letter_form`, `stroke`, `syllable`, `skill`, `lesson`, `quran_word_ref`, `phonetic_plan` (Al-Fatihah only), `source`; `ArabicScript` module with grapheme/diacritic tests | Deterministic rebuild (same hash twice); malformed fixtures rejected; Al-Fatihah refs resolve to QuranKit words; canonical text byte-identical |
| **L2** | App shell, profiles, engine core | L1 | 4 tabs (Learn, Practice/Review, Quran, Progress); local profiles; `LearningPersistence` (GRDB, migrations); `LearningEngine` (DAG, mastery states incl. uncertain, FSRS bridge, session planner); `PresentationProfile`; 3 renderers (choice, listen-choose, match) | Profile isolation tests; progress survives kill/relaunch; deterministic generator fixtures; VoiceOver/Dynamic Type smoke check on simulator |
| **L3** | Literacy U1–U3 | L2 | Letters, forms, contrast pairs, tracing (Noorine strokes), Antura audio audition + import; renderers: tracing, find-in-word | Audio audition log (per file: accept/reject/reason); every letter/form covered; tracing check unit-tested on stroke fixtures |
| **L4** | Literacy U4–U7 + placement | L3 | Vowels, marks, unseen-word decoding using compiler-selected Quran words; placement test | Unseen-item assessments exist for each unit; no transliteration on assessments; placement unlocks by evidence → **internal alpha** |
| **L5** | Quran bridge + vocabulary core | L4 | Learning-mode reader for Al-Fatihah + first short surahs (reuse audio + timings); record & compare; QUL morphology ingest; top-300 lemma ordering (our tool, diffed against QuranicWords); word sheet (meaning, root, lemma, POS) | All lemma counts regenerated and diffed; word refs verified; recording never leaves device; **foundational beta (TestFlight)** |
| **L6** | Tajweed foundations | L5 | Full `phonetic_plan` + tajweed spans for chosen surahs (quran-transcript, Hafs defaults recorded), cross-checked against Quran.com `uthmani_tajweed`; T1 lessons; optional audio pack download | Disagreements between the two sources listed and resolved by review; each rule has explanation + verified examples + listening drill |
| **L7** | Polish & release gate | L6 | Progressive-substitution reading, export/import, accessibility pass, performance budgets, licensing/attribution screen, qualified content review | Every §6 risk with "release blocker" closed or feature disabled; physical-device checks recorded separately |
| **R1** | Recognition research (parallel after L1; time-box 2 weeks) | L1 (phonetic plans) | Collect consented test set (adult beginner, child, correct/incorrect), try `tarteel-ai/whisper-tiny-ar-quran` (word level) and muaalem → Core ML (phoneme+sifat); measure precision/recall per error type, latency, memory | Written go/no-go per error category. Go only if ≥95 % precision with stated CI on beginners **and** children for that category; otherwise record blocker and keep record-and-compare |

Parked backlog (re-plan after L7): synthesis, CloudKit sync, grammar units, balaghah/analysis, full-Quran guided
progression, macOS, IndoPak, on-device LLM explanations.

## 6. Risk register

| # | Risk | Likelihood | Impact | Mitigation | Owner input | Release blocker? |
|---|---|---|---|---|---|---|
| 1 | Wrong canonical word mapping in lessons | Low (reader data verified) | Critical | Compiler resolves every ref through QuranKit; byte-equality tests. **Closed at L7:** every compiled word ref equals the canonical word byte for byte (`Tools/learning/compile.test.py:49`), bridge words are the canonical words (`BridgeContentTests.swift:17`) | — | Closed |
| 2 | Antura voice not acceptable for Quranic articulation | Medium | High | Audition per file (L3: technical audition done, `04-audio-audition.md`; listening review pending); fallback: commission a qualified reciter for ~200 syllables | Arrange reviewer/reciter | **Accepted open by owner 2026-11-26** (personal use; review pending, letters stay enabled). Revisit before a public release |
| 3 | Licensing: QUL / Quran.com terms for redistribution | — | — | **Closed 2026-11-25:** personal use, licensing does not restrict reuse. Keep the `source` table for traceability | Revisit if commercial | No |
| 4 | GPL data bundled (QuranicWords/QAC) | — | — | **Closed 2026-11-25:** allowed (personal use). Record the source | Revisit if commercial | No |
| 5 | mahfuz/ayyat code copied without LICENSE | — | — | **Closed 2026-11-25:** allowed (personal use). Record the source | Revisit if commercial | No |
| 6 | Phonetizer edge cases (sakt, ishmam, exceptions) taught wrongly | Medium | High | Use quran-transcript defaults, record options, cross-check vs Quran.com tajweed markup, teacher review. L6: defaults and options recorded, cross-check done (3 disagreements decided by an agent, `05-tajweed-crosscheck.md`); teacher review pending | Reviewer | **Accepted open by owner 2026-11-26** (personal use; review pending, tajweed stays enabled) |
| 7 | Speech recognition never meets gate | High | Medium | Not on the v1 path; record & compare is the product | — | No |
| 8 | Learners misread "coverage %" as understanding | Medium | Medium | Show lemma counts, never "% of Quran understood" | — | No |
| 9 | Child privacy (recordings) | Low | High | On-device only, discard by default, no analytics with audio, parental gate for saving. L5: one temporary file, replaced by each recording and deleted when the reader closes; never saved, so no parental gate is needed yet. **Closed at L7:** unchanged since L5 | Review applicable rules | Closed |
| 10 | Reader regression from shared-module edits | Low | High | No edits to QuranEngine unless backward-compatible + tests; run reader suite each time. **Closed at L7** as a standing rule (AGENTS.md two-app rule 4); L7 changed no QuranEngine module | — | Closed (process) |
| 11 | Authoring/review bottleneck | High | High | Small v1, generators for item volume, review queue per lesson | Reviewer time | **Accepted open by owner 2026-11-26** (personal use; lessons unreviewed) |
| 12 | Scope creep back to 24 units | Medium | Medium | This document is the scope contract; changes need owner sign-off | — | No |

## 7. Non-negotiables carried from the proposed spec

Canonical text is never modified; no generic TTS for pronunciation; no unvalidated scores or certificates; uncertain ≠
wrong; on-device and offline by default; no obligatory account; accessibility (VoiceOver, Dynamic Type, RTL, contrast,
reduced motion, non-audio alternatives) is part of done; language learning is not religious authority.
