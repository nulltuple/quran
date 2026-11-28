# V4: on-device Quran pronunciation assessment (phonemes & vowels) in QuranEngine and Recitation Lab

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** feature
- **Status:** verified
- **Related:** [roadmap v5 order](2026-11-27-quran-roadmap-v5-order.md),
  [V0 recitation engine](2026-11-26-v0-recitation-engine.md) (baseline Tilawi engine & deliverable 9),
  [V0 recitation lab](2026-11-27-v0-recitation-lab.md),
  [V0 model download](2026-11-27-v0-model-download.md) (D7 GitHub release pattern)

App: **Quran** (`Domain/RecitationRecognition`, `Features/RecitationLabFeature`, `Tools/phonetic-model.py`). Arabican
does not yet import `RecitationRecognition`, so only the Quran binary changes; the new phonetic engine and pure
`PronunciationAssessor` live in `QuranEngine` (`Domain/RecitationRecognition`) with custom non-Quran reference support so
Arabican can reuse them directly without reversing dependency direction.

## Context

Roadmap v5 places V4 (practical, accurate on-device pronunciation assessment for phonemes and vowels) directly after H5.
Existing Tilawi V0–V3 features (voice search, live follow, recite-and-check, live practice reveal) must remain intact,
memorization / pronunciation / tajweed assessments must remain strictly separate, no learning-store redesign is allowed,
uncertain recognition must never be treated as a confirmed mistake, and results stay in the developer Recitation Lab
until qualified-reviewer and quality gates pass.

## Candidate survey (verified 2026-11-27)

| Candidate | Params / Size | Access / License | On-device Core ML Feasibility | Phoneme / Vowel / Tajweed Evidence | Verdict |
|---|---|---|---|---|---|
| **`Hisnlabs/tajweed-v2`** (`b3b0503d32b4d9a8a0447880b4564fd3e9d69c15`, 2026-11-06) | 20.6 M params; 82.5 MB safetensors, 23.2 MB ONNX int8; **19.84 MB Core ML fp16/int8** | Public, ungated, Apache-2.0 | Standard Whisper-base encoder (6 layers, 512 dim, 50 fps) + 11 CTC heads; converts cleanly to Core ML ML Program with dynamic `RangeDim(4..3000)`; **13.5 ms p50** on CPU (`RTF 0.0015`) | Distilled from `obadx/muaalem-model-v3_2` on `tarteel-ai/whisper-base-ar-quran`; exact same 42-symbol Quran Phonetic Script (QPS) + 10 sifat heads; ships Apache-2.0 `imam.py` rule engine. Measured below on 159 `qdat_bench` learners + real/planted errors. | **Selected (primary V4/V5 engine)** |
| `obadx/muaalem-model-v3_2` (`01a1ef9f`) + `muaalem-v3_2-torchscript` (`cb1a38f4`) | ~600 M params (`w2v-bert-2.0`); **2.31 GB fp32**, **1.15 GB fp16** (~600 MB int8 / ~320 MB int4) | Public, ungated, MIT (`model`), QML 1.0 (`quran-muaalem`) | Heavy alongside Tilawi (125 MB / ~852 MB simulator RAM); risks iOS jetsam memory limits | Gold-standard teacher (4.9% PER on `qdat_bench`, same QPS + 10 sifat heads) | **Deferred fallback** (not needed; `Hisnlabs/tajweed-v2` passed error-detection and latency bars) |
| `Quran-Lab/zipformer_p-arabic-v3` (`db89c0fc`) | 65.5 M params; 62 MB float8 / 123 MB float16 `.mlpackage` | **Gated (`manual`)**, custom license (`quran-lab-npl-1.3`) | Pre-built Core ML packages exist, but inaccessible without manual HF approval & auth token | Streaming phoneme CTC | **Blocked by manual gating** |
| `Quran-Lab/tajweedformer-v4` (`2f630bee`) | 65 M params | Proprietary SDK + API key (`qlk_v1_...`), no HF weights | Requires proprietary SDK fetching weights from Quran Lab servers | Streaming phonemes + timestamps | **Rejected** |
| `obadx/muaalem-model-v3-mini`, `w2v2-384` | No weight files uploaded | Public, empty repos | N/A | N/A | **Not usable** |

Evaluation datasets checked: `obadx/qdat_bench` (`8003b22e`, ungated Apache-2.0, 85.8 MB, 159 real learner recordings
of Al-Ma'idah 5:109 with human phonetic transcripts, sifat, 6 madd counts, 2 ghunnah labels, qalqalah); `IqraEval/QuranMB.v2`
audio is public (220 MB) but its labels (`IqraEval/IqraEval_Test_GT`) are gated (`401 Unauthorized` without HF token).

## Decisions

- **Acoustic model: `Hisnlabs/tajweed-v2` converted to Core ML ML Program (`HisnLabsTajweedV2Int8.mlpackage`, 19.84 MB,
  `FLOAT16` compute, `int8` per-channel weights, dynamic mel length `[1, 80, 4..3000]`).** Exports 4 log-softmax CTC heads:
  `phoneme_log_probs` (43 classes: blank + 42 QPS symbols) plus `qalqalah_log_probs`, `ghunnah_log_probs`, and
  `tafkheem_log_probs` ready for V5. Defaults to `MLComputeUnits.cpuOnly`: on Apple Silicon with dynamic `RangeDim`,
  `.cpuOnly` runs in **13.5 ms p50** with zero dynamic-shape recompilation jitter (whereas `.all` incurred ~444 ms ANE
  shape-recompilation stalls per distinct clip length).
- **Exact Whisper 80-bin log-mel in Swift (`WhisperMelSpectrogram.swift`, `Accelerate`/`vDSP_mmul`).** Matches Hugging
  Face `WhisperFeatureExtractor` to `< 1e-3` (verified in `WhisperMelSpectrogramTests`), keeping dynamic lengths simple
  and avoiding STFT conversion quirks.
- **Unicode scalar indexing (`Unicode.Scalar`, not Swift `Character`).** Arabic short vowels (`َ`, `ُ`, `ِ`) are separate
  CTC tokens with independent probabilities and timestamps and are indexed as Unicode scalars in `quran-transcript`. Using
  `Unicode.Scalar` throughout `PhoneticAcousticModel`, `PhoneticReference`, and `PronunciationAssessor` prevents Swift
  extended grapheme clusters from collapsing letter + harakah.
- **Precompiled 6,236-ayah Hafs QPS reference DB (`quran_phonetics.db`, built by `Tools/phonetic-model.py build-ref` via
  `obadx/quran-transcript`).** Shipped inside the on-demand `phonetic-model-1.zip` pack (21.86 MB total zip, 0 bytes
  added to the app binary), read on demand via system `SQLite3` (no full-corpus load at launch). Stores 6,236 ayahs,
  77,433 words, and 86,549 Hafs tajweed spans so V4 excludes fine tajweed rules from clear pronunciation mistakes and V5
  can read the exact same DB. `PhoneticReference` is also constructible directly in memory for Arabican's non-Quran drills.
- **Confidence gating & error separation (`PronunciationAssessor`).** Only flags clear pronunciation mistakes (lahn jali:
  wrong vowel, wrong consonant, dropped/added sound, missing shadda, word not heard) when the mismatched span's minimum
  CTC posterior probability meets `0.70` (`0.85` within the first 3 onset symbols). Below threshold, findings are reported
  as `.uncertain` and never counted as confirmed mistakes. Fine tajweed differences (madd length, ghunnah, ikhfa, iqlab,
  idgham, qalqalah) are left for V5.
- **On-demand GitHub release asset (`phonetic-model-1`, D7 pattern).** Published at
  `https://github.com/nulltuple/quran/releases/download/phonetic-model-1/phonetic-model-1.zip` (`21,857,882` bytes,
  sha256 `0e62540c9f3c3d1d435210792d483ba9ee84a41e8ba4ed166a14f5129d8f23ac`), downloaded via `DownloadManager` into
  `Application Support/PhoneticModel/`. `recitation-model-1` is untouched.

## Benchmarks & error-detection verification (2026-11-27)

### 1. Real learner benchmark (`obadx/qdat_bench`, 159 recordings, 1,465.2 s total audio, M4 Pro CPU_ONLY)

| Core ML export | Size | PER | Madd exact / ±1 (954) | Qalqalah error F1 (P / R) | Ghunnah error F1 (P / R) | Latency p50 / p95 | RTF |
|---|---:|---:|---:|---:|---:|---:|---:|
| `fp16` | 39.40 MB | 8.83% | 82.3% / 91.0% | 90.6% (100.0% / 82.8%, 0 FP) | 84.9% (96.9% / 75.6%, 1 FP) | 13.5 / 22.7 ms | 0.0015 |
| `fp32_int8` | 19.97 MB | 8.98% | 81.9% / 90.8% | 92.6% (100.0% / 86.2%, 0 FP) | 84.9% (96.9% / 75.6%, 1 FP) | 20.7 / 33.8 ms | 0.0023 |
| **`fp16_int8` (shipped)** | **19.84 MB** | **8.98%** | **81.9% / 90.8%** | **92.6% (100.0% / 86.2%, 0 FP)** | **84.9% (96.9% / 75.6%, 1 FP)** | **13.5 / 21.0 ms** | **0.0015** |

On the first 30 `qdat_bench` clips, `CoreML fp16_int8` PER was 8.17% vs original `ONNX fp32` 7.89% (+0.28% delta).

### 2. Spoken error detection (verifying the model hears actual audio rather than guessing expected text)

Verified both in Python and in Swift on the iPhone 18 Pro Max simulator (`CoreMLPhoneticModelTests`, 1.076 s total):
- **Clean studio recitations:** Husary `112:1` → exact QPS match `قُلهُوَللَااهُءَحَدڇ` (100.0% match, 0 mistakes); Alafasy
  `1:2` → >95% match, 0 mistakes.
- **Planted vowel error (`أَحِدٌ` vs audio `أَحَدٌ`):** detected `.wrongVowel(expected: .kasra, heard: .fatha)`.
- **Planted consonant error (`أَسَدٌ` vs audio `أَحَدٌ`):** detected `.wrongConsonant(expected: "س", heard: "ح")`.
- **Audio-spliced truncation (last 38% of `112:1` cut off):** model emitted `قُلهُوَللَااه` (did NOT hallucinate `أَحَدٌ`)
  and flagged word 4 as `.wordNotHeard`.
- **Wrong-verse audio (`1:2` audio assessed against `112:1`):** transcribed `1:2` verbatim, <40% match, ≥3 confirmed
  mistakes.

## Trade-offs

- **Complexity added:** 5 Swift files in `Domain/RecitationRecognition/Sources/` (~1,200 lines: `WhisperMelSpectrogram`,
  `PhoneticAcousticModel`, `PhoneticReference`, `PronunciationAssessor`, `PhoneticModelStore`), 4 test files (+15 tests);
  `RecitationLabFeature` extended (+~295 lines across 3 files + 1 test); `Tools/phonetic-model.py` (~375 lines) +
  requirements + `Tools/phonetic-model.test.sh` (14 checks); `quran_phonetics_sample.db` (577 KB in `TestResources` only,
  never in the app bundle). Zero new Swift package dependencies, zero new permissions/entitlements, zero Core Data schema
  changes, zero app binary size growth (the 21.86 MB pack downloads on demand).
- **Who benefits / how often:** developers and reviewers in the Recitation Lab now; once reviewer/quality gates pass,
  Quran memorizers and Arabican learners benefit from on-device vowel and consonant feedback. Currently developer-only
  (rarely used by design until V4/V5 gates clear).
- **Rejected cheaper options:** keeping only Tilawi word-level ASR (cannot hear short vowels/harakat or phonetic traits);
  converting 600M `obadx/muaalem-model-v3_2` first (~600 MB–2.3 GB, heavy RAM/latency on iOS when its 20.6M distillation
  already clears the accuracy bar); shipping a Python phonetizer or rebuilding a rule-based Arabic phonetizer from scratch
  (precomputing all 6,236 ayahs from `obadx/quran-transcript` is deterministic and exact).
- **Ongoing cost:** `phonetic-model-1` GitHub release asset must stay published (never delete/replace; publish `-2` for
  updates); ~40 MB device storage when downloaded + compiled (package + `.mlmodelc` + `quran_phonetics.db`); small
  maintenance surface in `RecitationRecognition`.

## Changes

- `Domain/RecitationRecognition/Sources/`:
  - `WhisperMelSpectrogram.swift`: Accelerate/vDSP 80-bin Whisper log-mel extractor.
  - `PhoneticAcousticModel.swift`: `PhoneticSymbol`, `PhoneticTranscription`, `PhoneticVocabulary`,
    `PhoneticAcousticModel`, `CoreMLPhoneticModel` (actor).
  - `PhoneticReference.swift`: `PhoneticTajweedUnit`, `WordPhoneticSpan`, `PhoneticReference`, `PhoneticReferenceStore`
    (read-only `SQLite3`).
  - `PronunciationAssessor.swift`: `PhoneticVowel`, `PronunciationIssue`, `WordPronunciationAssessment`,
    `PronunciationAssessment`, `PhoneticAlignment`, `PronunciationAssessor`.
  - `PhoneticModelStore.swift`: `PhoneticModelArchive` (`phonetic-model-1`), `PhoneticModelStore`,
    `PhoneticModelDownloader`, `PhoneticEngineLoader`.
- `Features/RecitationLabFeature/Sources/`: `RecitationLabBuilder.swift`, `RecitationLabViewModel.swift`,
  `RecitationLabView.swift` (added V4 Pronunciation Engine section, optional target-verse override, QPS expected/heard,
  per-word `OK`/`Mistake`/`Uncertain` display, and lab-only reviewer gate note; preserved Tilawi V0).
- `Tools/`: `phonetic-model.py`, `phonetic-model-requirements.txt`, `phonetic-model.test.sh`; `Makefile` (`phonetic-model`,
  `test-tools`).
- `Domain/TestResources/Sources/test_data/recitation/quran_phonetics_sample.db`: 227-ayah test fixture.
- Docs: `feature-cost-register.md`, `quran-prioritized-roadmap.md`, `quran-roadmap-progress.md`, trail index.

## Tests

- `Domain/RecitationRecognition/Tests/`:
  - `WhisperMelSpectrogramTests.swift` (2 tests): exact match to HF `WhisperFeatureExtractor` on 440 Hz sine wave + silence.
  - `PronunciationAssessorTests.swift` (9 tests): sample DB read, clean recitation, wrong vowel, wrong consonant, onset
    threshold, low-confidence → `.uncertain` (never confirmed mistake), tajweed excluded from V4, missing word, custom
    non-Quran reference for Arabican reuse.
  - `CoreMLPhoneticModelTests.swift` (2 tests): real Core ML inference on Husary 112:1 & Alafasy 1:2 (0 false alarms) +
    planted vowel/consonant errors, audio-spliced truncation, and wrong-verse audio.
  - `PhoneticModelDownloaderTests.swift` (2 tests): zip sha256 verification + install; corrupt archive rejected & deleted.
- `Features/RecitationLabFeature/Tests/RecitationLabViewModelTests.swift` (3 tests, updated): un-installed state, full V0 +
  V4 analysis on Husary 112:1, verse override parser.
- `Tools/phonetic-model.test.sh` (14 checks): vocabulary, CTC decode, word mapping, SQLite schema, attribution.
- Regression note: `Unicode.Scalar` indexing fix was verified directly after initial test run failed on Swift grapheme
  cluster collapsing of Arabic letter + harakah (`"قُ"`).

## Validation

- **Verified:**
  - `make format-lint`: `0/1297 files require formatting, 66 files skipped.`
  - `make test-tools`: all tool suites passed (`phonetic-model.test.sh: 14 passed, 0 failed`).
  - `make test-no-sync`: `passedTests: 1810, failedTests: 0, skippedTests: 0` (xcresult summary; includes all 129
    `RecitationRecognitionTests` and 3 `RecitationLabFeatureTests` with Core ML models executed).
  - `make test-sync`: `passedTests: 2291, failedTests: 0, skippedTests: 0`.
  - `make test-arabican`: `passedTests: 117, failedTests: 0, skippedTests: 0`.
  - `make build-example-no-sync`, `make build-example-sync` (`Package.resolved` restored), `make build-arabican`:
    all `Build Succeeded`.
  - GitHub release `phonetic-model-1` published and verified (`HTTP/2 200`, `content-length: 21857882`).
  - Simulator (`iPhone 18 Pro Max`, iOS 27.2): `make run-example-no-sync` built, installed, and launched with
    `-RecitationSimulatedInput Husary_112001.mp3` and both Tilawi + Phonetic models staged in `Application Support`.
- **Not verified:**
  - Physical iPhone/iPad latency, peak memory, thermal behavior, and live microphone acoustics (no physical device here;
    added to owner checklist).
  - Compact-iPhone and iPad split-view layouts (one-simulator rule; uses standard `NoorList`/`NoorBasicSection` with no
    fixed widths).
  - Interactive tap-through of Recitation Lab UI on the simulator (no `idb`/`axe`/`cliclick` installed; SwiftUI
    `RecitationLabView` uses standard `NoorList` rows verified in `RecitationLabViewModelTests` and app launch check).
  - Qualified Quran teacher / reviewer sign-off on real learner recordings across diverse voices (women, children,
    non-native learners) — required before exposing V4 outside Recitation Lab.

## Release

- **Commit:** `a0b017a2c26bbbbb1f73d6c3615b57c610862976` (`feat(recitation): on-device V4 pronunciation assessment engine and lab`)
- **Pushed:** `origin/main` at `a0b017a2`
- **TestFlight:** `make release-testflight-quran` archived `Quran 1.20.3 (1033)` cleanly, but `xcodebuild -exportArchive`
  failed (70) in this non-interactive session: `error: exportArchive Failed to Use Accounts` (App Store Connect access for
  team `NBMD2V39VV` required). Owner can upload V4+V5 together with `make release-testflight-quran` from an interactive
  Xcode-signed-in shell (no Arabican binary change).
- **GitHub release:** `https://github.com/nulltuple/quran/releases/tag/phonetic-model-1`
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- **V5 (next):** implement `TajweedAssessor` on top of V4's `PhoneticTranscription` + `PhoneticReference.units` + timing
  (madd, ghunnah, qalqalah first; expand only where reliable acoustic evidence holds), validated on `qdat_bench` and wired
  into Recitation Lab.
- Owner physical-device benchmark of V4 phonetic latency/memory and real microphone pronunciation tests in Recitation Lab.
- Qualified reviewer evaluation before surfacing V4/V5 verdicts outside the developer Recitation Lab.
- Arabican consumer wiring (separate Arabican task) once ready to add pronunciation feedback to Arabican drills.
