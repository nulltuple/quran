# Quran V2b+V3: real-time mistake detection, low-latency streaming, and Tarteel parity in Practice

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** feature | performance | fix
- **Status:** verified
- **Related:** [2026-11-27-v2b-live-practice-reveal.md](2026-11-27-v2b-live-practice-reveal.md) (`PracticeRecitationTracker`, live Practice reveal),
  [2026-11-27-v2a-live-follow.md](2026-11-27-v2a-live-follow.md) (`RecitationFollowViewModel` streaming loop),
  [2026-11-27-v3a-recite-and-check.md](2026-11-27-v3a-recite-and-check.md) (`RecitationChecker`, quality gate),
  [2026-11-27-h7-v3b-mistake-history-and-repair.md](2026-11-27-h7-v3b-mistake-history-and-repair.md) (`MistakeHeatmap`, `.model` evidence)

App: **Quran** (with shared `Localization` and `QuranAnnotations` changes, so **Arabican** is tested, built, and released too per AGENTS.md rule 5).

## Context

The owner provided a 121.8 s screen recording of Tarteel reciting Surah Ash-Shura Page 483 (42:1–10) in hidden-Mushaf memorization mode with live mistake highlighting enabled, and asked to:
1. Ensure identical or better functionality, performance, latency, and accuracy exist in our Quran app, with clear launch instructions.
2. Extract the recording's audio and verify accuracy and latency end-to-end through our internal feedback loop, upgrading or changing models if needed to match or beat Tarteel.

Benchmarking the extracted 16 kHz mono audio (`audio_16k.wav`, 42:1–10, 125 canonical words) against Tarteel's 5 fps video frames uncovered four concrete gaps in our existing V2b live Practice stack:
1. **No live mistake detection during hidden-Mushaf Practice:** `HifzPracticeViewModel` previously hardcoded `mistakenWords: []` and `.correct` on every auto-advanced ayah.
2. **Grammatical inflection blind spot:** `WordAligner.matchSimilarity = 0.70` forgave `-ون` ↔ `-ين` (e.g. `والظالمين` vs `وَٱلظَّٰلِمُونَ`, similarity `0.857`) in both Practice and `RecitationChecker`.
3. **Huruf muqatta'at 3-token split & window-edge corruption:** Tilawi FastConformer emits `عٓسٓقٓ` as three short tokens (`ع س ق`), which `WordAligner` could not regroup (only 2:1 existed), and an unanchored 8 s rolling window cut mid-word at its start.
4. **Slow 1.0 s hop:** `HifzPracticeViewModel.liveHop` and `RecitationFollowViewModel.hop` ran every 1.0 s (1.3–2.5 s reveal latency) even though Core ML `TilawiFastConformerInt8` runs in **21.7 ms p50** on Apple Silicon.

## Model evaluation (2026-11-27, extracted Tarteel recording 42:1–10)

| Model | Size / Runtime | Inference latency | Behavior on extracted 42:1–10 audio | Verdict |
|---|---|---|---|---|
| **`muhdur/tilawi-fastconformer-quran` (`TilawiFastConformerInt8`, shipped)** | **125 MB Core ML int8** | **21.7 ms p50 / 22.2 ms p95** (Apple Silicon `.all`; 286.6 ms p50 simulator CPU) | Transcribed all 125 words and every real mistake verbatim (`ويؤمن به`, `وقال الذين كفروا`, `من رب`, `وقالوا`, `والظالمين`). Zero network latency. | **Kept (already beats Tarteel)** |
| `tarteel-ai/whisper-base-ar-quran` | 290 MB PyTorch (MPS) | 3,268–8,263 ms / window (150×–380× slower) | Dropped entire 42:2–42:5 in window 1 (`حم` only); garbled `قُرْآنًا عَرَبِيًّا` → `قُلْ أَنَا نَعْرَبِيًّا`, `يُحْيِي الْمَوْتَى` → `فِي الْمَوْتَةِ`. | **Rejected** |
| `Hisnlabs/tajweed-v2` (already shipped for V4/V5) | 19.8 MB Core ML fp16/int8 | 4–22 ms CPU | Independent phonetic verification confirmed exact audio ground truth (`عِۦسِقَاا`, `وَظظَلِمِنَ`, `وَقَاالُۥۥ`). | **Used as ground-truth check** |
| `rabah2026/wav2vec2-large-xlsr-53-arabic-quran-v_final` / `mrmuminov/quran-fastconformer-ctc-ar` | 1.26 GB / 438 MB fp32 | Not converted | Unnecessary: Tilawi FastConformer + improved alignment/streaming already matched 7/7 Tarteel mistake words + 1 additional real hesitation with 0 false alarms and 0.30–2.75 s faster reveal latency than Tarteel. | **Not needed** |

## Decisions

- **Keep `TilawiFastConformerInt8` (no new model download or memory increase):** Our existing 115 M FastConformer CTC model already runs at 21.7 ms p50 on Apple Silicon and hears every mistake in the recording accurately; the bottleneck was streaming windowing, hop rate, and alignment/mistake logic, not model weights.
- **Quiet-anchored 14 s rolling window + 300 ms hop (`RecitationAudio.quietAnchoredWindow`):** Rolling buffers hold 16 s (mic retains 18 s) and trim the left edge to the quietest 80 ms frame within ±2 s of 14 s so FastConformer never sees a mid-word front cut. Both `HifzPracticeViewModel.liveHop` and `RecitationFollowViewModel.hop` drop from `1 s` to `300 ms` (sequential loop, so simulator CPU never piles up).
- **Alignment & inflection upgrades (`WordAligner`, `RecitationChecker`, `RecognizedWord`):**
  - Added `meanConfidence` alongside min `confidence` on `RecognizedWord`.
  - Added constrained 3:1 regrouping in `WordAligner` (only when all three recited tokens are ≤ 2 letters and the expected word is ≤ 6 letters, covering huruf muqatta'at like `ع س ق` → `عٓسٓقٓ`).
  - Added `WordAligner.isInflectionMismatch` catching `-ون` ↔ `-ين` and `-هم` ↔ `-كم` swaps on ≥ 4-letter words with ≥ 0.80 stem similarity, wired into both `PracticeRecitationTracker` and `RecitationChecker`.
- **Real-time mistake detection in `PracticeRecitationTracker` (`LivePracticeMistake`):**
  - Golden rule: words cleanly matched strictly behind the live edge (`confirmedClean`) are never retroactively flagged by later sliding windows.
  - Multi-window voting detects four mistake kinds with zero false alarms on clean fixtures: `.substitution` (grammatical inflections ≥ 2 windows, dissimilar confident words ≥ 3 windows), `.omitted` (≥ 3-letter words skipped ≥ 4 windows), `.stumble` (wrong non-opening, non-repeat words spoken at the active position, absorbed 2:1 wrong prefixes, or grouped wrong insertions before self-correction ≥ 2 windows), and `.hesitation` (≥ 3 repeated restarts stuck at the same next word).
  - Live mistakes automatically populate `PracticeMask.mistakeWords` (red highlight + bottom accent bar on revealed words across image Mushaf, line-page Mushaf, and translation views), record `.mistake` with exact canonical `mistakenWords` (`.model` provenance) into H7 mistake history when ayahs complete, and can be inspected (**Expected** vs **Recited**) or disputed live from the Practice card's mistake/accuracy pill.
- **One-tap entry on the current page:** Added **Practice This Page** (`hifz_practice.practice_page`) to the reader's More menu (`MoreMenuFeature` → `QuranInteractor.onPracticePageTapped`), alongside the existing Ayah Menu → Practice entry and **Highlight Mistakes** toggle in Practice Options.

## Trade-offs

- **Complexity added:** ~420 lines in `Domain/RecitationRecognition` (`PracticeRecitationTracker`, `WordAligner`, `RecitationAudio`, `RecognizedWord`, `RecitationChecker`), ~190 lines in `HifzPracticeFeature` (live mistakes state, accuracy badge, `LivePracticeMistakesSheet`, dispute), ~65 lines across `QuranAnnotations` (`PracticeMask.mistakeWords`), `QuranImageFeature`, `QuranTranslationFeature`, `MoreMenuFeature`, `QuranViewFeature`, and `RecitationFollowFeature`; 8 localization keys across 16 catalogs (agent translations); 8 new unit/integration tests. Zero new third-party dependencies, zero new permissions, zero Core Data schema changes, zero new downloaded model assets.
- **Who benefits / how often:** Memorization learners using hands-free hidden-Mushaf recitation; core flagship Hifz capability alongside live follow (usage UNVERIFIED, no remote analytics).
- **Rejected cheaper options:** Switching to `tarteel-ai/whisper-base-ar-quran` (150×–380× slower, dropped 42:2–42:5, no frame alignment); converting a 1.26 GB Wav2Vec2-Large model (massive download & iOS RAM risk when Tilawi already achieves 100% reveal and matches/beats Tarteel); post-hoc-only checking in `RecitationCheckView` (cannot reveal words or highlight mistakes live on the Mushaf).
- **Ongoing cost:** 300 ms hop increases Core ML calls from 1/s to ~3.3/s while live reciting (~7% duty cycle on Apple Silicon at 21.7 ms/call; physical iPhone 10-minute battery/thermals UNVERIFIED); 8 agent-translated keys across 15 non-English catalogs need native review.

## Changes

- `Domain/RecitationRecognition/Sources/`: `RecognizedWord.swift` (`meanConfidence`), `RecitationAudio.swift` (`quietAnchoredWindow`), `WordAligner.swift` (3:1 short-token regrouping, `isInflectionMismatch`), `RecitationChecker.swift` (inflection swap detection), `PracticeRecitationTracker.swift` (`LivePracticeMistake`, fast anchored reveal, 1-word ayah bridge, Golden Rule + live mistake detection, `removeMistake`).
- `Model/QuranAnnotations/Sources/PracticeMask.swift`: `mistakeWords`.
- `Features/QuranImageFeature/Sources/`: `ContentImageViewModel.swift` (`practiceMistakeHighlights`), `ContentLineViewModel.swift` (revealed mistake verse tint).
- `Features/QuranTranslationFeature/Sources/ContentTranslationViewModel.swift`: revealed mistake word highlights in translation view.
- `Features/HifzPracticeFeature/Sources/`: `HifzPracticeViewModel.swift` (`liveWindowSeconds = 16`, `liveHop = 300 ms`, quiet-anchored windowing, `liveMistakes`, `highlightLiveMistakes`, `liveAccuracyPercent`, `disputeLiveMistake`, `.model` mistake persistence, `onHistoryChanged`), `HifzPracticeView.swift` (Highlight Mistakes toggle, live mistakes/accuracy pill, `LivePracticeMistakesSheet`), `HifzPracticeBuilder.swift` (`onHistoryChanged`).
- `Features/RecitationFollowFeature/Sources/RecitationFollowViewModel.swift`: `windowSeconds = 16`, `hop = 300 ms`, quiet-anchored windowing.
- `Features/MoreMenuFeature/Sources/`: `MoreMenuModel.swift`, `MoreMenuViewModel.swift`, `views/MoreMenuView.swift` (`practicePage` row).
- `Features/QuranViewFeature/Sources/QuranInteractor.swift`: `practicePage = .alwaysOn`, `onPracticePageTapped()`, `onHistoryChanged` wiring.
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: 8 `hifz_practice.*` keys in all 16 languages.
- Platform-neutral (iPhone and iPad); no `#if`.

## Tests

- `Domain/RecitationRecognition/Tests/PracticeRecitationTrackerTests.swift` (+5 tests): 3-token huruf muqatta'at (`ع س ق` → `عٓسٓقٓ`), live inflection substitution (`والظالمين` vs `وَٱلظَّٰلِمُونَ`) + dispute, live stumble (`ويؤمن به` before `وَيَسۡتَغۡفِرُونَ`), Golden Rule preventing retroactive flags on `يُحۡيِ`, and `RecitationAudio.quietAnchoredWindow` pause alignment.
- `Domain/RecitationRecognition/Tests/RecitationCheckerTests.swift` (+1 test): grammatical inflection swap (`والظالمين` vs `وَٱلظَّٰلِمُونَ`) flagged as `.substituted`.
- `Features/QuranImageFeature/Tests/ContentImageHeatmapTests.swift` (+1 test): `practiceMistakeHighlights` renders only for revealed words.
- `Features/HifzPracticeFeature/Tests/HifzPracticeViewModelTests.swift` (+1 real Core ML test): live stumble (`112:1` + `1:2` + `112:2..4`) flags mistake on `PracticeMask.mistakeWords`, updates `liveAccuracyPercent`, toggles `highlightLiveMistakes`, and disputes cleanly.
- Regression evidence: verified directly on the extracted 82.5 s Tarteel recording (`42:1–10`) in both Python and real Swift `HifzPracticeViewModel` + `CoreMLRecitationModel`:
  - Swift production stack (`HifzPracticeViewModel` + `CoreMLRecitationModel`, 269 windows): `phase=finished(42:1...42:10)`, `accuracy=94%`, `mistakes=8` (`42:5:10 وَيَسۡتَغۡفِرُونَ`, `42:5:12 فِي`, `42:6:1 وَٱلَّذِينَ`, `42:6:2 ٱتَّخَذُواْ`, `42:7:4 قُرۡءَانًا`, `42:8:1 وَلَوۡ`, `42:8:7 وَلَٰكِن`, `42:8:13 وَٱلظَّٰلِمُونَ -> والظالمين`), `sessions=1`, `evidence=18`, 0 false alarms on clean ayahs (`42:1–4`, `42:9–10`), 0 false alarms on clean studio fixtures (`Husary 112:1–4` 15/15, `Ghamadi 2:255` 50/50).
  - Latency: 21.7 ms p50 / 22.2 ms p95 per window on Apple Silicon (`MLComputeUnits.all`); 286.6 ms p50 on iOS Simulator CPU-only; word reveals 0.30–2.75 s faster than Tarteel across 42:1–10.

## Validation

- **Verified:**
  - `make format-lint`: `0/1316 files require formatting, 71 files skipped.`
  - Full sequential suites on iPhone 18 Pro Max simulator (`iOS 27.2`, Core ML model present):
    - `make test-no-sync`: `passedTests: 1851, failedTests: 0, skippedTests: 0` (`Run-QuranEngine-Package-2026.11.27_21-25-26--0800.xcresult`).
    - `make test-sync`: `passedTests: 2332, failedTests: 0, skippedTests: 0` (`Run-QuranEngine-Package-2026.11.27_21-31-49--0800.xcresult`).
    - `make test-arabican`: `passedTests: 117, failedTests: 0, skippedTests: 0` (`Run-ArabicLearning-Package-2026.11.27_21-39-29--0800.xcresult`).
  - App builds & pins: `make build-example-no-sync`, `make build-example-sync` (`Package.resolved` restored), `make build-arabican` — all `Build Succeeded`; `bash Tools/package-pins.test.sh`: `5 passed, 0 failed`.
  - Real Swift production benchmark (`HifzPracticeViewModel` + `CoreMLRecitationModel` + `PracticeRecitationTracker`) on the extracted 82.5 s Tarteel recording (`42:1–10`, 269 streaming windows at 300 ms hop): completed 125/125 words, `accuracy=94%`, `mistakes=8` matching all 7 Tarteel red words plus 1 additional real hesitation (`42:8:7`), 0 false alarms on clean ayahs, `sessions=1` / `evidence=18` persisted to Core Data.
- **Not verified:**
  - Physical iPhone/iPad microphone acoustics, 10-minute battery draw and thermal behavior at 300 ms hop.
  - Compact-iPhone and iPad split-view layouts (one-simulator rule; `LivePracticeMistakesSheet` uses native `NavigationStack` + `List` with dynamic fonts and no fixed widths).
  - Native linguistic review of the 8 new agent-translated keys across 15 non-English catalogs.

## Release

- **Commit:** pending
- **Pushed:** pending
- **TestFlight:** pending
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Measure physical-device 10-minute battery/thermal impact at 300 ms hop; if battery is noticeable, adapt hop to 500 ms during silence and 300 ms while speaking (`SpeechLevel`).
- Optional: tap a red highlighted word directly on the Mushaf during Practice to open that specific word's Expected vs Recited popover (currently accessible from the Practice bar's Mistakes pill).
- Native review of the 8 new localization keys across 15 non-English catalogs.
