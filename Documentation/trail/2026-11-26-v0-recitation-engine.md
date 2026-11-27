# V0 slice (a): on-device Quran recitation engine (Core ML), verse identification and benchmarks

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-26-quran-roadmap-v3-order.md](2026-11-26-quran-roadmap-v3-order.md) (owner's V0 brief, roadmap §6 V0),
  [2026-11-26-quran-roadmap-v2.md](2026-11-26-quran-roadmap-v2.md)

App: **Quran** (new QuranEngine Domain module `RecitationRecognition`, not yet used by a screen), and **both** for the
shared `VerseTextPersistence` change (Arabican imports that module).

## Context

Roadmap v3 puts V0 next: "a working engine, not a report", Quran-trained weights first, on-device, behind a QuranEngine
Swift interface that Arabican can also use (roadmap §6 V0, deliverables 1–9). The owner approved microphone use, local
inference dependencies and downloading public models and datasets (D4, 2026-11-26). This entry is slice (a): research,
runtime choice, the engine running in tests, verse identification and the first benchmarks. Slice (b) (word alignment to
canonical `Word`s) and slice (c) (dev-only microphone screen, device benchmarks) follow.

## Research: the owner-named resources (opened 2026-11-26)

| Resource | What it is | License | Size, runtime | Quality evidence | Verdict |
|---|---|---|---|---|---|
| `tarteel-ai/whisper-base-ar-quran` | Whisper base fine-tune | Apache-2.0 | `pytorch_model.bin` 290 MB (fp32); seq2seq | card: WER 5.75 on an undocumented eval set | measured below; seq2seq, no frame alignment |
| `tarteel-ai/whisper-tiny-ar-quran` | Whisper tiny fine-tune | Apache-2.0 | 151 MB fp32 | card: WER 7.05 (undocumented set) | measured below |
| `ram-a-dhan/tarteel-whisper-quran-ggml` | the two Tarteel models in whisper.cpp GGML | Apache-2.0 | base f16 148 MB / q8_0 82 MB; tiny f16 78 MB / q8_0 44 MB | none published; used through `whisper.rn` | same weights as Tarteel's; whisper.cpp would be a binary C++ dependency |
| `Tilawi/quran-asr` (MIT, TypeScript, `ab55bac8`) + `muhdur/tilawi-fastconformer-quran` (`e9448a0e`) | FastConformer large CTC (115 M parameters), fine-tuned from NVIDIA `stt_ar_fastconformer_hybrid_large_pcd_v1.0`; one ONNX graph with the feature extractor inside; verse matcher with a trust gate, word judge | code MIT; weights CC-BY-4.0; its `quran.json` Tanzil CC-BY-3.0 | 88 MB ONNX (int4 MatMul, int8 Conv); raw 16 kHz audio in, 1,025 SentencePiece CTC tokens out, 80 ms a frame | published: 599/600 EveryAyah verses correct, 0 wrong (Husary, Minshawi, Alafasy); per-clip transcripts in `eval/results` | **chosen** (CTC: frame timing for V2, forced alignment and confidence for V3) |
| `Recite-Quran/Natlu` | Flutter app; streaming int8 Zipformer (`Quran-Lab/zipformer_p-arabic-v3`) through sherpa-onnx, phoneme alignment, madd/ghunna durations | no license file | ONNX + sherpa-onnx | none published | candidate for V2 streaming and tajweed (follow-up) |
| `MuhammadNoman2/quran-ai-api` | FastAPI server: faster-whisper (CTranslate2) + ONNX, VAD, verse locator, word alignment, muaalem pronunciation | no license file | server, CPU | none published | server-side; not on-device |
| `foyzulkarim/hifz-tester` | local web app: a Quran Whisper through Python, deterministic word alignment (`src/lib/align.ts`) | MIT | Node + Python | none published | alignment ideas for slice (b) |
| `obadx.github.io/prepare-quran-dataset` | dataset pipeline; `obadx/mualem-recitations-annotated` (890 h), `obadx/recitation-segmenter-v2` (wav2vec2-BERT pause segmentation); `obadx/muaalem-model-v3_2` (phonetic CTC, 74k downloads) | not stated | — | — | phoneme/tajweed path (deliverable 9) |
| arXiv 2509.00094 (Abdelfattah, Khalil, Abbas) | multi-level CTC over a Quran Phonetic Script (11 levels incl. sifat), 848 h, `qdat_bench` (159 samples) | — | — | PER 0.21% test, 1.94% qdat_bench, tajweed F1 75.8% (authors' data) | the muaalem model; deliverable 9 |

Other public models found (Hugging Face search "quran", 2026-11-26): `TBOGamer22/wav2vec2-quran-phonetics`,
`rabah2026/wav2vec2-large-xlsr-53-arabic-quran-v_final`, `mohammed/fastconformer-quran-ar`,
`mrmuminov/quran-fastconformer-ctc-ar`, `Quran-Lab/zipformer_p-arabic-v3`, `naazimsnh02/whisper-large-v3-turbo-ar-quran`,
`deepdml/whisper-small-ar-quran-mix-norm` and many ONNX exports of the Tarteel Whispers. Not measured in this slice.

### Runtime

- **ONNX Runtime is not obtainable for iOS today.** `github.com/microsoft/onnxruntime` and
  `microsoft/onnxruntime-swift-package-manager` return 404 (`gh api`, 2026-11-26; press reports date the removal to about
  2026-11-17), and the CocoaPods archive host `download.onnxruntime.ai` serves a `*.azureedge.net` certificate
  ("no alternative certificate subject name matches", `curl -v`), so the `onnxruntime-c` pod (1.30.0, iOS 15.1) cannot be
  fetched. PyPI wheels still install (used here for reference runs).
- **Core ML** (system framework, no dependency, no binary size beyond the model) runs the model after a conversion this
  slice built: dequantize the ONNX weights, fix the input to 20 s, convert through PyTorch (`onnx2torch`) with
  `coremltools`. The dequantized float ONNX agrees with the original on every argmax frame of 112:1 and 1:2 and 99.65% of
  2:255's 849 frames (identical transcripts except one letter in a misheard word); zero padding to 20 s with `length` is
  exact (max difference 6.5e-5). Core ML float32 agrees with the original on every frame of both short clips, on CPU, GPU
  and Neural Engine.
- **Float16 compute is wrong on the CPU** (the simulator's only Core ML device): every frame decodes to `<unk>`; with the
  feature extractor kept in float32 it is right on the GPU and the Neural Engine but still wrong on the CPU. So the model
  computes in float32 and only its weights are compressed (int8 per channel, iOS 16: 125 MB; int4 per block of 32, iOS 18:
  83 MB). Finding the CPU float16 fault (probably a masked softmax or padding overflow) would let the Neural Engine run
  float16; follow-up.
- whisper.cpp / WhisperKit were not integrated: the Tarteel Whispers are measured through transformers only, as a model
  comparison; a seq2seq model gives no frame alignment for V2/V3.

## Decisions

- **Model: Tilawi FastConformer CTC first, not a Tarteel Whisper.** CTC gives per-frame timing (80 ms) and token
  posteriors: the basis for streaming follow (V2), forced alignment and per-word confidence (V3). A seq2seq Whisper can
  hallucinate fluent text on noise and gives no frame alignment. Measured comparison below.
- **Runtime: Core ML, float32 compute, int8 weights (iOS 16) as the default package; int4 (iOS 18) also built.** No
  third-party runtime (ONNX Runtime unobtainable for iOS, see Research), Neural Engine left for a later float16 fix.
- **Fixed 20 s window** with a `length` input: shape logic folds to constants (onnxslim), which made the graph convertible;
  zero padding is masked exactly. Longer audio runs in consecutive windows (a word cut at a window edge can be misheard;
  overlapping windows are a V2 follow-up).
- **Match against the app's own imla'i search text** (`quran.ar.uthmani.v2.db`, FTS table `verses`), not Tilawi's
  `quran.json`: on Tilawi's 600 published transcripts the character error rate against the app text is 1.6–2.9% per
  reciter versus 4.1–5.3% against Tanzil "simple-clean" (which keeps Uthmani spellings like العلمين, الصلوه). No new data
  asset. That table puts the basmala before verse 1 of every sura but 1 and 9; the matcher removes it there, and from a
  transcript that opens with it (found when every reciter's 39:1 matched 45:2, whose words are the same).
- **Own Swift matcher, Tilawi's constants.** Tilawi's `bestJoint03Match` (900 lines of tuned TypeScript over its own
  text adapter) was not ported line by line: retrieval by shared letter pairs, whole-text ratio, a fragment fit for part of
  a long verse, runs of 2–3 consecutive verses, and Tilawi's trust gate (score 0.8, or fragment floor 0.62 with fit 0.75,
  fit margin 0.15 and 12 letters; never under 5 letters). Identical texts tie in Quran order (55:13 ×31).
- **The model is not in git or the app yet.** Tests build it with `make recitation-model` into git-ignored `.cache/`; the
  model-backed tests skip without it and say how to build it. Shipping it to devices needs a download host: the owner's
  call (proposal: a `recitation-model-1` release asset of `nulltuple/quran`, like D6's tafsir packs).
- **Ambiguity is the UI's job.** `VerseIdentification` returns ranked candidates and `isConfident`; V1 shows candidates
  when not confident, never a guessed verse.

## Trade-offs

- **Complexity added:** Domain module `RecitationRecognition` (7 files, 705 lines) with 6 test files; `Tools/recitation-model.py`
  (452 lines) + test + pinned requirements; `GRDBQuranVerseTextPersistence.searchTextOfAllVerses` (+20 lines, shared with
  Arabican); `make recitation-model`; 459 KB of EveryAyah MP3 fixtures and a 350-transcript JSON fixture. No new package
  dependency, permission or entitlement; no persisted state.
- **Who benefits / how often:** nobody yet (no screen); V1 voice search, V2 live follow and V3 mistake detection build on
  it. Those are committed roadmap objectives; voice search alone is likely occasional use (UNVERIFIED).
- **Rejected cheaper options:** ONNX Runtime (no iOS binary today; would add a ~20 MB+ static library, size UNVERIFIED);
  whisper.cpp (C++ binary dependency, Whisper's weaknesses above); Apple `SpeechTranscriber` (owner: never the baseline);
  porting Tilawi's matcher verbatim (larger, tuned to a different text).
- **Ongoing cost:** a 125 MB (or 83 MB) on-demand download per device once shipped; 20 s windows at about 250–390 ms each
  on the simulator's CPU (device numbers: owner checklist); matcher index built once (~1 s in tests, 6,236 verses) and held
  in memory (~1 MB of letters). Re-running the conversion needs Python 3.12 and ~1 GB of packages.

## Changes

- `Domain/RecitationRecognition/Sources/`: `ArabicMatchNormalizer` (matching-only normalization), `EditDistance` (ratio,
  fragment fit), `CTCDecoder` (`CTCVocabulary`, `CTCLogProbabilities`, tokens with frame ranges), `VerseMatcher`
  (`VerseCandidate`, `VerseIdentification`, trust gate, basmala handling), `RecitationAudio` (any audio file → 16 kHz mono
  via AVFoundation), `RecitationAcousticModel` + `CoreMLRecitationModel` (actor), `RecitationRecognizer` (windows →
  transcript → verses). Platform-neutral (iPhone and iPad); no `#if`.
- `Data/VerseTextPersistence/Sources/GRDBVerseTextPersistence.swift`: `searchTextOfAllVerses(quran:)`.
- `Package.swift`, `QuranEngine-Package.xctestplan`: the module and its test target.
- `Tools/recitation-model.py` (`fetch`, `convert`, `eval` with `onnx`, `coreml` and `whisper` backends),
  `Tools/recitation-model-requirements.txt`, `Tools/recitation-model.test.sh`, `Makefile` (`recitation-model`, test-tools),
  `.gitignore` (`/.cache/`).
- `Domain/TestResources/Sources/test_data/recitation/`: four EveryAyah MP3s (Husary 112:1, Alafasy 1:2, Ghamadi 40:1 and
  2:255; sha256 in this entry's Validation) and `everyayah_transcripts.json`.
- Docs: roadmap §5/§6 V0, `quran-roadmap-progress.md`, `feature-cost-register.md`, trail index.

## Benchmarks (2026-11-26, Mac mini M4 Pro, macOS; `Tools/recitation-model.py eval`)

350 EveryAyah recordings: the same 50 verses (seed 1, whole Quran, `sample_verses`) by each of seven reciters; Husary,
Alafasy and Minshawi are the reciters Tilawi published results for, Abdul Basit (192 kbps), Shuraym, Ghamadi (40 kbps) and
Ayyoub are held out from that evaluation (whether any of them was in Tilawi's training data is UNVERIFIED: the card says
"the author's own recitation recordings"). References: the app's imla'i text, basmala removed from verse 1. Top-1/top-5:
the tool's reference matcher (letter-pair shortlist + edit ratio), with identical texts counted as correct. CER over all
clips counts a reciter's repeated phrases (going back after a pause, common in clips over 20 s) as insertions, so CER on
the 256 clips of 20 s or less is the cleaner model measure. Latency is per clip (all its 20 s windows), on the Mac, not a
phone.

| Backend | Weights | Size | Top-1 | Top-5 | CER (all) | CER (≤20 s) | WER | Latency p50 / p95 | RTF |
|---|---|---|---|---|---|---|---|---|---|
| ONNX Runtime 1.32 (Python), original | int4 MatMul + int8 Conv | 88 MB | 350/350 | 350/350 | 5.18% | 0.66% | 10.5% | 104 / 392 ms | 0.0078 |
| **Core ML, all units** | **int8 per channel (iOS 16)** | **125 MB** | **350/350** | **350/350** | **5.13%** | **0.67%** | **10.4%** | **26 / 77 ms** | **0.0030** |
| Core ML, CPU only | int8 per channel | 125 MB | 350/350 | 350/350 | 5.13% | 0.67% | 10.4% | 59 / 177 ms | 0.0048 |
| Core ML, all units | int4 per block of 32 (iOS 18) | 83 MB | 349/350 | 350/350 | 12.2% | 5.08% | 28.3% | 26 / 83 ms | 0.0022 |

Swift side (simulator, iPhone 18 Pro Max, latest iOS; Core ML on the simulator uses the CPU only):
`CoreMLRecitationModelTests/testWindowLatencyOnThisDevice` recorded `window_ms=[252, 253, 254, 276, 392]` for one 20 s
window. `VerseMatcherRecitationTests` over the Core ML int8 transcripts of the 350 recordings:
`clips=350 top1=350 top5=350 confident=346 confidentWrong=[]` (the four unconfident answers were still ranked first).

Whisper (Tarteel tiny/base through transformers on the CPU) did not finish 350 clips in 15 minutes and was stopped so the
test suites could run without CPU contention; the comparison is a follow-up on a smaller sample.

## Recommendation per use (deliverable 6, first version)

- **Voice search (V1):** Tilawi FastConformer CTC, Core ML int8, `RecitationRecognizer.identifyVerses` with the trust gate;
  show the candidate list when `isConfident` is false. Ready on the engine side; needs the model on the device (D7) and a
  microphone capture path (slice c).
- **Streaming follow (V2):** the same CTC model in shorter overlapping windows (e.g. 4–6 s every 1–2 s, padding masked by
  `length`), aligned to the expected passage with the practice range as prior; the 80 ms CTC frames give timing. Measure
  latency on a device first. Alternative to evaluate: Natlu's streaming Zipformer (`Quran-Lab/zipformer_p-arabic-v3`),
  which needs an ONNX runtime (sherpa-onnx bundles its own; availability for iOS UNVERIFIED).
- **Mistake detection (V3):** CTC forced alignment of the expected words against the frame posteriors (per-word
  confidence instead of only the greedy transcript), plus Tilawi's word judge as reference; quality gate on held-out
  recordings with planted mistakes. Phoneme-level and tajweed assessment (deliverable 9): obadx's `muaalem-model-v3_2`
  (multi-level CTC over the Quran Phonetic Script, arXiv 2509.00094: PER 0.21%/1.94%, tajweed F1 75.8% on the authors'
  data) is the candidate; next step is to open its weights and size and try the same ONNX → PyTorch → Core ML path used
  here, then evaluate on `qdat_bench`.

## Tests

- `RecitationRecognitionTests` (new, 6 files, 25 tests): `ArabicMatchNormalizerTests` (4), `EditDistanceTests` (3),
  `CTCDecoderTests` (4), `VerseMatcherTests` (9: whole verse, misheard letter, fragment of 2:255, identical texts of 55:13
  in Quran order, 112:1–2 run, basmala removed from 39:1 and from a transcript, too few letters, unrelated speech),
  `VerseMatcherRecitationTests` (1: 350 real transcripts, top-1 ≥ 347, top-5 ≥ 349, ≥ 340 confident, no confident wrong
  answer), `CoreMLRecitationModelTests` (4: three reciters end to end, a 50 s recitation in three windows, silence, window
  latency; they skip without `.cache/recitation-model`).
- `GRDBVerseTextPersistenceTests.testSearchTextOfAllVersesReadsTheSearchTableInQuranOrder` (new).
- `Tools/recitation-model.test.sh` (22 checks), in `make test-tools`.
- The basmala handling was added after the benchmark showed every reciter's 39:1 ranked under 45:2; its two
  `VerseMatcherTests` failed before the change (reasoned from the code path: the index kept the basmala, so 39:1 scored
  below 45:2 and 46:2; not run before the fix).

## Validation

- **Verified:**
  - `make format-lint`: `0/1196 files require formatting`.
  - `make test-no-sync`: 1,591 tests, 1,591 passed, 0 failed, 0 skipped (xcresult summary; the model-backed tests ran with
    `.cache/recitation-model` present). `make test-sync`: 2,070 passed, 0 failed, 0 skipped. `make test-arabican`: 117
    passed, 0 failed. Run one after the other.
  - `make test-tools`: every tool test passed, `recitation-model.test.sh` `22 passed, 0 failed`.
  - `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: `Build Succeeded` (Package.resolved
    restored after the sync build).
  - `Tools/recitation-model.py fetch` verified both assets' sha256; `convert` reproduced the two packages from scratch in
    43 s (the benchmark used those packages).
  - Fixture sha256: Alafasy_001002 `7056ff0c…6b6b`, Ghamadi_002255 `0604df1f…b2e1`, Ghamadi_040001 `c8b8f69b…6cb2`,
    Husary_112001 `bb8ed6cc…cd31` (from `https://everyayah.com/data/<reciter>/<sura><ayah>.mp3`).
- **Not verified:**
  - Any physical device: latency, memory, energy, Neural Engine use (float32 compute runs on CPU/GPU), thermal behavior on
    long recordings. Needs the model on the device (D7) and slice (c).
  - Live microphone speech (only studio EveryAyah recordings so far), noisy rooms, children's and learners' recitation.
  - Whisper comparison (stopped, see Benchmarks).
  - Release-build matcher speed (debug simulator: ~50 s for 350 identifications; release expected ~10× faster, UNVERIFIED).
  - The int4 package is built but not recommended (accuracy above); not tried on iOS 18 hardware.

## Release

- **Commit:** `c061ba9b` (feat(recitation): on-device Quran recitation engine and verse ID)
- **Pushed:** origin/main at `c061ba9b`
- **TestFlight:** Quran build 1001 (1.20.3): `Uploaded Quran iOS 1.20.3 (1001) for commit c061ba9be0e71c5fccbbb1225b83c25327af1bf2 to App Store Connect app MemQuran.`
  Arabican build 1001 (0.1.0): `Uploaded Arabican iOS 0.1.0 (1001) for commit c061ba9be0e71c5fccbbb1225b83c25327af1bf2 to App Store Connect app Arabican.`
  No user-visible change in either app (the engine is not wired to a screen; the model is not bundled).
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- **Owner decision D7:** the model's download host (roadmap §7). Slice (c) and V1 need it.
- **V0 (b):** align transcript words to canonical `Word`s (Uthmani `arabic_text` words, `uthmani_tokens` for the 6
  exceptions), keeping CTC frame ranges; word-level statuses for V3.
- **V0 (c):** dev-only microphone screen behind a debug setting; device benchmarks (latency, memory, energy).
- Whisper comparison on a smaller sample (`eval --backend whisper --n 20`); WhisperKit / whisper.cpp only if Whisper wins
  somewhere.
- Find the Core ML float16 CPU fault (likely a masked softmax or padding overflow; the mixed-precision package was right on
  GPU and Neural Engine) to run float16 on the Neural Engine; try int4 with smaller blocks or 6-bit palettization.
- Overlapping windows with a word-level merge (Tilawi's `stitch.ts`) for recordings over 20 s.
- Phoneme/tajweed: open `obadx/muaalem-model-v3_2`, convert, evaluate on `qdat_bench`.
- Arabican could use `RecitationRecognition` for its recognition research (roadmap §4); not wired.
