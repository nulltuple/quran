# 01 · Source-level repository evaluation

- **Date:** 2026-11-25
- **Author:** Claude Code (claude-opus-5-5)
- **Method:** shallow clones (no Git LFS objects) of each repository at the commit below, read with
  `git ls-files`, `wc`, `grep`, `sqlite3` and targeted file reads. README claims were checked against
  the implementing files. Model-weight licenses were read from the Hugging Face model API.
- **Not done (UNVERIFIED):** no candidate's test suite was executed (running downloaded code was
  blocked in this session); no LFS audio/model binaries were downloaded or auditioned; no app was
  built. M0 of the roadmap repeats these checks with execution.

## 1. Low-cut filter (applied before deep reading)

| Repository | Commit | Stack | Verdict | Why |
|---|---|---|---|---|
| vgwb/Antura_arabic | 4bea102 (2022-03-09) | Unity 2018 | **Cut** | README: "this repository is now closed"; superseded by vgwb/Antura, which carries the same Arabic content |
| edenmind/OpenArabic | 97b3121 (2024-03-30) | Kubernetes, MongoDB, Fastify, React Native | **Cut** | Platform for classical scholarly texts (al-Hasan al-Basri, Abu Hanifa…), not Quran literacy; server infrastructure contradicts offline-first; stale since 2024 |
| Sosoisworking/tadabbur | bc8dc9a (2026-08-29) | Flutter PWA + Supabase | **Cut (ideas only)** | No LICENSE file (all rights reserved); "AI-first" claim has **no AI code** (no LLM provider referenced in `app/` or `supabase/`); SM-2 runs server-side (`supabase/functions/srs-review/index.ts:2`); content lives in 49 SQL migrations |
| The other nine | — | — | Deep read | — |

## 2. Evaluation matrix

Scores: ●●● strong · ●● usable · ● weak · ✕ unusable. "Reuse" = what legitimately enters our code or content.

| Repo | Commit | Lang / platform | Real implementation | Tests | Architecture | License (code / content / models) | Reuse |
|---|---|---|---|---|---|---|---|
| **nulltuple/quran** (ours) | dbeb4894 | Swift 5.8 SPM, iOS 15 | ●●● shipped reader, 77,432 verified words | ●●● module test targets + guardrails | ●●● layered Core/Model/Data/Domain/UI/Features, every target exported as a library | Apache-2.0 (upstream quran-ios) | **Foundation** for identities, text, word data, audio, fonts, downloads |
| Yns1000/Noorine | 9840642 (2026-02-25) | SwiftUI, iOS 17, watchOS 11.6, Xcode project (no SPM) | ●● general MSA course (café dialogues, French) | ✕ 1 empty test (`NoorineTests/NoorineTests.swift`) | ● monolithic views (`LevelDetailView.swift` 2,065 lines, `ProfileView.swift` 1,886) | MIT code; audio provenance **unknown** (`Core/GeneratedAudio/*.mp3`, 274 files) | **Stroke data + stroke-guide view only** |
| theilgaz/mahfuz | (default branch, pushed 2026-06-08) | TypeScript web (TanStack, Drizzle, Turbo) | ●●● 14-stage Qaida, 16 tajweed rules, 8 games, multiplayer | ✕ 0 test files | ●● typed curriculum schema, but web-bound | README says "MIT", **no LICENSE file**; 28 letter mp3s of unknown provenance | **Curriculum structure as reference** (re-author, don't copy until LICENSE added) |
| Muno459/ayyat | 2c98362 (2026-05-24) | SwiftUI, iOS 17.4, GRDB 7, WhisperKit | ●● progressive-substitution reader, hifz, quiz, on-device ASR | ● 39 tests (bidi wrap, word audio, misc) | ● large views (`ContentView.swift` 1,090 lines), OIDC + server API client | README says "Code: MIT", **no LICENSE file**; FastConformer weights `license:other`; Tarteel Whisper Apache-2.0 | **Core ML audio pipeline + substitution algorithm as reference** |
| rmrashahriar/QuranicWords | 4fd80e1 (2026-10-15) | Kotlin Android + static web + Python pipeline | ●●● 3,833 lemmas, 1,423 roots, 8 languages, curriculum order | ●● 16 pipeline tests (`tools/pipeline/tests/test_pipeline.py`) | ●●● reproducible pipeline with pinned sha256 sources | **GPL-3.0** code and **GPL-3.0-or-later dataset** (derived from Quranic Arabic Corpus) | **Validation reference / curriculum ordering method**; bundling the data requires owner GPL decision |
| vgwb/Antura | 838704bcb (2026-11-10) | Unity C# | ●●● mature children's literacy game, many languages | ● Teacher tester scenes, little automated | ●● TeacherAI separated from minigames | BSD-2-Clause code; **CC-BY-4.0** content and audio | **Human-recorded letter × harakat audio (CC-BY) + TeacherAI design** |
| open-spaced-repetition/swift-fsrs | 74cb029 (2026-11-12) | Swift 5.10 SPM, iOS 14, zero deps | ●●● FSRS-5 and FSRS-6 | ●●● 106 test functions (not run here) | ●●● small, strict-concurrency | MIT | **Adopt as dependency** |
| Quran-Lab/tajweedformer-apple | e9ff5d2 (2026-11-24) | Swift 6 SPM + closed binary `QuranLabCore.xcframework` | ●● real SDK, but model is encrypted and leased | ●● fixtures + tests | n/a (closed core) | **Quran-Lab No-Profit License 1.3**: revocable at any time, no charging, no use of outputs to train/evaluate other models, API key per bundle id, first-run download from `cdn.quranlab.ai` | **No-go** as a dependency |
| obadx/quran-muaalem | b310432 (2025-11-03) | Python, Wav2Vec2-BERT 660M multi-level CTC | ●●● phoneme + sifat recognition (server/GPU) | ●● ~2k lines of tests | ●● | **QML 1.0** = Apache-2.0 + mandatory AI notice (EN+AR), "Islamic Sharia" compliance clause, no ads, free-access path; model card v3_2 says `mit` (conflict) | **Research spike only** (Core ML feasibility unproven; 660M params) |
| obadx/quran-transcript | e30c100 (2026-11-19) | Python | ●●● deterministic Hafs phonetizer with sifat, tajweed rule objects, error explainer | ●●● ~15k lines of tests (`tests/phonetics_pytest.py` 6,468 lines) | ●●● | MIT code; bundled Tanzil text CC-BY-3.0 "verbatim, no changes" | **Adopt as build-time G2P** (precompute; no Python on device) |

## 3. Per-repository findings (file-level)

### 3.1 nulltuple/quran (existing app) — reuse inventory

Read at `dbeb4894`. `Package.swift:57` exports every target as a library product (`products: libraries(from: targets)`), so another
package can depend on individual modules. `platforms: [.iOS(.v15)]` (`Package.swift:55-56`). `QURAN_SYNC` and the
`mobile-sync-spm` dependency are opt-in via environment variable (`Package.swift:15-37`) and stay off for the learning app.

| Module / asset | Path | Reuse for learning app |
|---|---|---|
| `QuranKit` | `Model/QuranKit` | Canonical Sura/Verse/Word identities and readings — **use directly** |
| `QuranText`, `QuranTextKit`, `VerseTextPersistence` | `Model/QuranText`, `Domain/QuranTextKit`, `Data/VerseTextPersistence` | Uthmani text lookup (`Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db`) |
| `WordTextPersistence`, `WordTextService` | `Data/WordTextPersistence`, `Domain/WordTextService` | Word meanings (EN, BN), transliteration |
| `word_by_word.db` | `Example/QuranEngineApp/Resources/word_by_word.db` (8.4 MB) | Tables `word_meanings(sura, ayah, word, english, bengali, transliteration)`, `uthmani_tokens`, `hafs_1405_glyph_words`. Built by `Tools/build-qul-word-data.py`; 77,432 words with EN/BN/translit, 2:181, 8:6 and 13:37 realigned (`Documentation/trail/2026-11-24-m1-canonical-word-data.md`) |
| `qul_afasy.db` + `AudioTimingPersistence` | `Example/QuranEngineApp/Resources/qul_afasy.db` | Cleaned word segments for Al-Afasy; 372 words have no segment of their own. For **contextual highlight only**, never cropped as standalone pronunciation |
| `QuranAudio`, `QueuePlayer`, `QuranAudioKit`, `ReciterService` | `Model/QuranAudio`, `Core/QueuePlayer`, `Domain/QuranAudioKit` | Ayah playback, looping, word-timed highlight |
| `NoorFont` | `UI/NoorFont/Sources/Resources` | `UthmanicHafs1B Ver13.ttf`, `Kitab-Regular.ttf`, `noorehira.ttf`, `surah_names.ttf` |
| `BatchDownloader`, `NetworkSupport` | `Data/BatchDownloader`, `Data/NetworkSupport` | Optional content/audio pack downloads |
| `SQLitePersistence` (GRDB 6.29) | `Data/SQLitePersistence` | Read-only content DB access pattern |
| Agent contract, trail, guardrails | `AGENTS.md`, `Documentation/trail/`, `Tools/check-agent-guardrails.sh` | Process reuse (no subagents, tests per change, trail entries) |

Not reusable as-is: UIKit-heavy reader features (`Features/QuranViewFeature`, `QuranImageFeature`), page-image geometry,
`GenericDataSources`/`Popover` UI dependencies, Core Data notes/collections. The learning app must not depend on `Features/*`.

### 3.2 Yns1000/Noorine

- **Inventory:** 96 Swift files, ~15k lines; `Core/course_content.json` (3,350 lines) holds `letters` (30), `vowels` (6),
  `words` (75), `roots` (40), `phrases` (45), `dialogues` (3) and `levels` (42 in `en`, plus `fr`).
- **Curriculum is not Quranic:** level types are `wordBuild` 15, `phrases` 10, `vowels` 7, `alphabet` 6, `speaking` 2,
  `solarLunar` 1, `dialogue` 1. The dialogue is "At the Café"; phrases are "أَنَا طَالِب" (I am a student).
- **Handwriting "recognition"** (`Features/Learning/Components/Drawing/RecognitionEngine.swift:8-60`) is Vision
  `VNRecognizeTextRequest` OCR over a rendered image with `contains` matching (`:49`), which returns 1.0 whenever either
  string contains the other. It is not stroke assessment and gives unreliable verdicts for isolated letters.
- **SRS** (`Core/SRSEngine.swift:43-70`) is an SM-2 variant on SwiftData. Superseded by swift-fsrs.
- **Speech:** `Core/SpeechManager.swift:13` uses `SFSpeechRecognizer(locale: "ar-SA")` (general MSA STT; may use Apple
  servers). `Core/AudioManager.swift:11,396` speaks via `AVSpeechSynthesizer` with a system Arabic voice. Both violate the
  spec's "no generic STT/TTS for pronunciation instruction" rule.
- **Audio:** `Core/GeneratedAudio/` (274 mp3, names like `abyad.mp3`, `akhdar.mp3`); "Generated" and no provenance
  record → treat as TTS output of unknown rights; **do not reuse**.
- **Valuable (MIT):**
  - Stroke-order data for all 30 letters, every applicable contextual form (isolated/initial/medial/final; non-joiners
    isolated+final), normalized `[0,1]` control points with `line`/`curve` types and EN/FR drawing instructions —
    `Core/course_content.json` → `letters[].strokes`, `letters[].drawingInstructions`.
  - Animated stroke guide — `Features/Learning/Components/Drawing/StrokeGuideOverlay.swift` (269 lines; path
    linearization, arc-length animation, arrow heads).
  - Canvas model — `Features/Learning/Components/Drawing/DrawingCanvasModel.swift` (112 lines).
  - Diacritic detection/highlight helpers — `Core/DiacriticHelper.swift` (443 lines; needs tests and a review against
    Quranic marks such as dagger alif, small high marks).
- **Verdict:** **not a seed.** Forking would import a watch app, widgets, live activities, a French catalog, a MSA
  syllabus, untested monolithic views and forbidden speech paths, then require deleting most of it.

### 3.3 theilgaz/mahfuz

- **What is real:** typed curriculum schema `packages/shared/src/types/learn.ts` (Level → Stage → Lesson →
  ContentBlock[] + Exercise[] + `conceptIds` for SRS + `prerequisites`); data `packages/shared/src/data/learn/curriculum.ts`
  (1,921 lines) with 14 stages: letters, connecting, fatha, kasra, damma, longVowels, sukun, tanwin, shadda, basicWords,
  shortSurahs, basicTajweed, maddRules, advancedTajweed. Explicit lessons: s1 9, s2 5, s3 7, s6 4, s7 5, s8 4, s9 4,
  s11 8, s12 6, s13 5, s14 8; s4/s5 via `generateHarakatLessons` (`:897`, `:907`), s10 via `generateWordLessons` (`:1236`).
- Exercise types used: `tajweed_identify` 42, `word_read` 35, `harakat_read` 31, `letter_recognition` 21, `matching` 6,
  `word_build` 4, `form_match` 4, `letter_order` 1, `fill_blank` 1. `audioRef` occurs **0 times** in the curriculum: the
  lessons have no audio wired.
- Letter data `packages/shared/src/data/learn/alphabet.ts` (371 lines): forms, makhraj (5 coarse classes), shape family,
  dot count/position, harakat combinations.
- Tajweed: 16 rules in `apps/web/src/routes/tajweed.tsx:39-193`; per-ayah tajweed markup is **fetched from Quran.com**
  (`apps/web/scripts/fetch-tajweed.ts:9` → `api.quran.com/api/v4/quran/verses/uthmani_tajweed`) into
  `apps/web/public/tajweed/{1..114}.json`. We can fetch the same source ourselves.
- Letter audio: `apps/web/public/kids/audio/*.mp3` (28), falling back to Web Speech `ar-SA`
  (`apps/web/src/components/alifba/LetterAudioButton.tsx:3`). Provenance unknown.
- Text strings live in `apps/web/src/locales/{tr,en,ar,de,es,fr,nl}.ts`; comments in the curriculum are Turkish.
- **Tests:** none (`git ls-files | grep -E '\.(test|spec)\.tsx?$'` → 0).
- **License:** README `## License … MIT` (`README.md:183-185`) but no LICENSE file. Treat as **reference only** until the
  author adds a LICENSE; re-author our lessons rather than transliterating theirs.

### 3.4 Muno459/ayyat

- **Progressive substitution** (show Arabic words inside the English translation as mastery grows):
  `ayyat/Services/Storage/VocabularyStore.swift:108-360` (`displayMode`, `wordSubstitutionScore`, lemma override,
  pre-graduation cap). A good, small idea for our Quran-reading tab; reimplement on our mastery model.
- **On-device ASR:** `ayyat/Services/Audio/TarteelWhisperKit.swift` (WhisperKit with `tarteel-ai/whisper-tiny-ar-quran`,
  Apache-2.0), `FastConformerQuranASR.swift` (custom CTC model from `huggingface.co/Muno459/fastconformer-quran`,
  `license:other`), `LogMelFeatures.swift` (261 lines, Swift log-mel), greedy CTC decoding (`FastConformerQuranASR.swift:9-17`).
  Export scripts `scripts/export_tarteel_*.py`, `scripts/export_fastconformer_to_coreml_ane.py`.
- **"Pronunciation check" is word recall, not pronunciation:** `PronunciationChecker.swift` uses **Apple Speech as the
  primary engine** (comment at `:516`) and collapses letters into phonetic classes (`:585-600`: د/ت/ط/ض, س/ث/ص/ز/ذ/ظ,
  ر/ل, ك/ق, ع/غ) so that a learner who says س for ص, ت for ط or ك for ق is **accepted**. Those are exactly the
  contrasts the spec says we must teach. Not reusable as assessment logic.
- Data: `ayyat/Resources/Data/quran.db` (29 MB; words, verses, roots, lemmas, stems from QUL via
  `scripts/morphology_ingest/ingest.py`). We build our own from QUL.
- Word audio: `ayyat/Services/Audio/WordAudioCache.swift:20-21` streams `audio.qurancdn.com/wbw/…` (Quran.com
  word-by-word recordings, which are **standalone word recordings**, not cropped segments). A candidate source for us.
- Infra we don't want: `Services/API/OIDCAuthService.swift`, `UserAPIClient.swift` (Quran Foundation accounts).
- **License:** README says "Code: MIT" (`README.md:186-188`) but no LICENSE file → reference only.

### 3.5 rmrashahriar/QuranicWords

- Dataset `dataset/words.json` (3,833 lemmas, ordered by frequency rank, `curriculum {chapter, section, lesson}`,
  `verb_form` with past/present/masdar, meanings in en/bn/ur/hi/id/tr/fa/fr, example verse), `dataset/roots.json`
  (1,423), `dataset/verses.json` (4,839 ayahs with char spans). Chapter sizes 66/150/250/250/500/350/650/369/650/598.
- Pipeline `tools/pipeline/qw/*.py` (curriculum ordering in `curriculum.py`: function words first, then frequency bands
  so اللَّه, رَبّ, يَوْم appear early), validation `qw/validate.py`, tests `tools/pipeline/tests/test_pipeline.py` (16).
- Sources (`NOTICE`): Quranic Arabic Corpus morphology v0.4 via `mustafa0x/quran-morphology` (GPL), GTAF word glosses,
  alquran.cloud/quran.com translations, Tanzil for verification.
- **"97.4 % coverage"** counts QAC morphological segments (94,618 occurrences), not the 77,4xx words the app shows;
  never surface it as "you understand 97 % of the Quran" (spec §7).
- **License:** GPL-3.0 code; `dataset/metadata.json` declares the dataset GPL-3.0-or-later. Bundling it (or the QAC
  data) in an App Store binary needs an explicit owner decision (GPL-on-App-Store conflict). Default: regenerate
  frequencies and ordering from QUL morphology with our own tool; use QuranicWords only to cross-check.

### 3.6 vgwb/Antura

- **Human-recorded Arabic letter audio, CC-BY-4.0:** `Assets/_lang_bundles/arabic/Audio/Letters/*.wav` (189 files:
  `<letter>__lettername`, `_fathah`, `_kasrah`, `_dammah`, `_sukun`, `_fathah_tanwin`, `_dammah_tanwin`…), plus
  `arabic_legacy/Audio/Letters` (164). Stored in Git LFS (the checkout has 130-byte pointers); fetch with
  `git lfs pull --include "Assets/_lang_bundles/arabic/Audio/Letters/*"`. Voice is MSA children's-game narration:
  **must be auditioned** for Quranic articulation (ض, ظ, ق, ع, ح, emphatics) before use.
- Content DBs (Unity YAML): `Assets/_config/content_Arabic/DB Arabic_{Letter,Word,Phrase,LearningBlock,PlaySession}.asset`.
  Children's MSA vocabulary, not Quranic.
- **TeacherAI (BSD-2):** `Assets/_core/_scripts/TeacherAI/` — `AIEngines/VocabularySelectionAI.cs` (744 lines, weighted
  selection by score/recency/focus), `DifficultySelectionAI.cs`, `MiniGameSelectionAI.cs`, deterministic question builders
  in `QuestionBuilding/QuestionBuilders/` (LettersInWord, LetterFormsInWords, LetterAlterationsInWords, WordsBySunMoon,
  CommonLettersInWords…). These are good **designs** for our deterministic exercise generators; port ideas, not Unity code.
- Pedagogy: Stage → LearningBlock → PlaySession journey, short sessions, assessments after blocks. Children's mode reference.

### 3.7 open-spaced-repetition/swift-fsrs

- `Package.swift`: `FSRS` library, iOS 14 / macOS 10.13, no dependencies, strict concurrency.
- FSRS-5 (19-weight) and FSRS-6 (21-weight), auto-detected (`Sources/FSRS/Models/FSRSDefaults.swift:9-31`); basic and
  long-term schedulers, reschedule, Codable compatibility tests. 106 test functions.
- **Adopt as an SPM dependency (MIT).** Use only for recall-type items (letters, vocabulary, forms); not for decoding or
  passage skills, which use the mastery model.

### 3.8 Quran-Lab/tajweedformer-apple

- SDK source is visible but the model runs inside a closed binary (`Package.swift`: `.binaryTarget(name: "QuranLabCore",
  url: "https://cdn.quranlab.ai/sdk/apple/4.0.3/…")`); model files are encrypted and leased; first use needs network and an
  API key per bundle id (`README.md:91-97`); endpoints `api.quranlab.ai`, `cdn.quranlab.ai/models`.
- License NPL-1.3: revocable by Quran-Lab "for You or for everyone… at any time"; on termination you must delete the
  Work, its Outputs and what you made from them; no charging; outputs may not be used to train **or evaluate/benchmark**
  other models (a model compared using the Work becomes a Derivative).
- **No-go:** violates offline-first, opacity and supply-chain stability; the benchmark clause conflicts with the spec's
  own plan to compare recognizers. Do not integrate. Re-evaluate only if the license changes.

### 3.9 obadx/quran-muaalem

- Wav2Vec2-BERT multi-level CTC (phonemes + 10 sifat), 660M parameters (`README_EN.md:85`), trained on expert
  recitations with Tarteel-generated text (`:99-103`). Model: `obadx/muaalem-model-v3_2` (HF card `license:mit`) — the
  repo's QML license says model derivatives are covered; treat QML as binding until the author confirms.
- No on-device path exists; 660M params ≈ 1.3 GB fp16 / ~0.7 GB int8. Core ML conversion, latency and beginner/child
  accuracy are **unproven**.
- QML conditions (AI notice in every UI language + Arabic, Sharia-compliance clause, no ads, free path) fit a free,
  ad-free app but the Sharia clause is legally vague → owner decision before any distribution.
- **Use:** time-boxed research spike only.

### 3.10 obadx/quran-transcript

- `src/quran_transcript/phonetics/phonetizer.py:49` `quran_phonetizer(...)`; `moshaf_attributes.py` exposes Hafs options
  (madd_monfasel_len 2–5, madd_mottasel_len 4–6, madd_aared_len 2/4/6, sakt points, yabsut س/ص, noon_tamnna ishmam/rawm,
  recitation_speed…); `sifa.py` computes per-phoneme sifat; `tajweed_rulses.py` defines rule classes (madd families,
  izhar/idgham/iqlab/ikhfa for noon and meem, ghunnah, tanween deletions at pause…); `error_explainer.py` explains
  phoneme differences.
- Tests: `tests/phonetics_pytest.py` (6,468 lines), `test_sub_with_tagged_mapping_pytest.py`, `aya_pytest.py`,
  `test_error_pat_pytest.py` (49 tests)…
- **Adopt at build time:** run the phonetizer in `Tools/` to precompute a phonetic plan + tajweed rule spans per word in
  context (wasl and waqf) for every ayah, store in the content DB with version and options. No Python ships in the app.
  Port to Swift only if arbitrary on-device input becomes a requirement. Note: bundled Tanzil text is CC-BY-3.0
  "verbatim, no changes"; we keep our canonical text from QUL/Quran.com and use Tanzil only to verify.

## 4. Licensing summary (independent per asset class)

| Asset | Source | License | Use decision |
|---|---|---|---|
| Reader code | nulltuple/quran | Apache-2.0 | Use; keep headers |
| Stroke data, stroke-guide view | Noorine | MIT | Use with attribution |
| Noorine audio | Noorine `Core/GeneratedAudio` | Unknown (likely TTS) | **Do not use** |
| Qaida curriculum | mahfuz | README-only "MIT", no LICENSE | Reference; re-author; ask author to add LICENSE before copying anything |
| mahfuz audio | `apps/web/public/kids/audio` | Unknown | Do not use |
| Substitution algorithm, Core ML pipeline | ayyat | README-only "MIT", no LICENSE | Reimplement from understanding; no verbatim copy |
| FastConformer weights | HF Muno459/fastconformer-quran | `other` | Do not use |
| Tarteel Whisper tiny/base | HF tarteel-ai | Apache-2.0 | Spike candidate |
| Vocabulary dataset | QuranicWords | GPL-3.0-or-later | Cross-check only unless owner accepts GPL |
| QAC morphology | corpus.quran.com | GPL | Same as above |
| QUL morphology / word data | qul.tarteel.ai | QUL terms (already used by our reader; previous owner instruction put licensing out of scope there) | Owner must confirm terms before public release |
| Letter × harakat audio | Antura | CC-BY-4.0 | Use after audition, with attribution |
| TeacherAI designs | Antura | BSD-2 | Port ideas |
| FSRS | swift-fsrs | MIT | Dependency |
| TajweedFormer SDK + models | Quran-Lab | NPL-1.3 (revocable, closed) | **No** |
| Muaalem code + model | obadx | QML 1.0 (Apache + conditions); model card MIT | Spike only; owner decision before shipping |
| Phonetizer | quran-transcript | MIT (+ Tanzil CC-BY-3.0 text) | Build-time tool |
| Word audio | Quran.com `audio.qurancdn.com/wbw` | Quran.com terms (UNVERIFIED) | Candidate; owner confirms |
| Fonts | KFGQPC Hafs (ours), Amiri Quran, Scheherazade New, Noto Naskh Arabic | KFGQPC terms; SIL OFL 1.1 | Teaching UI: OFL fonts; Quran text: existing KFGQPC font |
