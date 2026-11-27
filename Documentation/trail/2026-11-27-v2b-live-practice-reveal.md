# Quran V2b: automatic reveal and advance in Practice from live recitation

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** feature
- **Status:** verified
- **Related:** [2026-11-27-v2a-live-follow.md](2026-11-27-v2a-live-follow.md) (`RecitationFollower`, rolling microphone buffer, `SpeechLevel`),
  [2026-11-27-h1-h2a-learning-store-and-practice.md](2026-11-27-h1-h2a-learning-store-and-practice.md) (`MemorizationService`, `Quran 4` evidence provenance),
  [2026-11-27-h2b-practice-listen-cues-cumulative-resume.md](2026-11-27-h2b-practice-listen-cues-cumulative-resume.md) (listen & repeat, cumulative steps, draft resume),
  [2026-11-27-quran-h2c-reader-practice.md](2026-11-27-quran-h2c-reader-practice.md) (translation & line-page practice, AX-XL follow-up)

App: **Quran** (Domain `RecitationRecognition`, `MemorizationService`; Features `HifzPracticeFeature`, `QuranViewFeature`;
Core `Localization`). Arabican imports `Localization`, so it is tested, built and released too; it imports none of the
recitation, memorization or reader modules.

## Context

Roadmap §5 #11 and §6 V2b: "H2's practice mode reveals and advances from live recitation (V2a's streaming path) with the
practice range as the prior; manual override always wins."

With H1 and H2 (slices a–c) shipped in build 1022, Practice already drives word masking across image Mushafs, line-page
Mushafs (ayah spans plus canonical word cues in the bar), and the translation view through a single `PracticeMask` value
and navigates across pages automatically when the current ayah changes. V2b layers live recitation directly onto
`HifzPracticeViewModel` so hands-free reveal and advance works in every reader mode without duplicating reader logic.

## Decisions

- **Bounded practice tracker (`PracticeRecitationTracker`, pure Domain in `RecitationRecognition`).** Reuses
  `WordAligner.alignWithin` and `RecitationFollower.isOpening`, but enforces the practice stretch as a strict prior:
  - Search region keeps `unitsBehind = 20` behind the revealed point (so the 8 s rolling window still aligns across
    already-recited ayah boundaries) and looks at most `unitsAhead = 15` forward inside the current ayah, admitting the
    immediately next ayah only within 4 units of the current ayah's end (or for short ≤ 4-unit ayahs). Whole-Quran
    `VerseMatcher` relocation is never used.
  - Skip guard: matching only into the next ayah never completes the current ayah unless at least one word of the
    current ayah was matched (earlier or in the same window).
  - Short-ayah threshold: `requiredMatches = min(2, currentRange.count)`, so 1-word (`103:1`) and 2-word (`112:2`)
    sole stretches complete instead of stalling on V2a's 3-word start threshold.
  - Monotonic reveal and manual override: `revealedUnitEnd` only advances, and `sync(verse:revealedWords:)` synchronizes
    manual `Next Word` peeks or manual advances so live windows never hide manually revealed words.
  - Off-track detection: 3 consecutive speaking windows (`SpeechLevel`) that fail to fit (excluding basmala/isti'adha)
    set `isOffTrack = true` with a non-blocking status line and VoiceOver announcement; pauses never count as misses.
- **Rolling buffer boundary for cumulative jumps (`RecitationMicrophone.clearBuffer()`).** When cumulative order finishes
  step $k$ and jumps backward (e.g. `112:2` → `112:1, 112:2`), `HifzPracticeViewModel` rebuilds the tracker for the new
  step and clears the rolling microphone buffer so audio from the previous step cannot falsely reveal the repeated ayah.
- **Manual override always wins:**
  - `revealNextWord()` and `showHint()` work while live recitation runs, increment `assistance`, and never get undone.
  - `check()` stops live recitation immediately, reveals the full ayah, and enters manual `.grading` (`.manual` provenance).
  - `toggleListening()` (Listen & Repeat) stops live recitation first, and starting live recitation stops Listen & Repeat;
    playback and microphone never run together.
  - Tapping the Practice bar's microphone button or the reader's top-right Recite button (`QuranInteractor.onReciteBarButtonTapped`)
    toggles live recitation; leaving the reader or backgrounding (`stopRecitationFollow()`) stops the microphone while
    keeping Practice open.
  - Ending Practice stops the microphone and drops the loaded `RecitationRecognizer` (~852 MB simulator footprint).
- **Model provenance in evidence and draft v2:** ayahs auto-advanced by live recitation record `VerseRecall(..., provenance: .model)`
  with `.hint` when `assistance > 0` and `.correct` otherwise; manual grading stays `.manual`. `PracticeStateStore` bumps
  `StoredDraft.currentVersion` from 1 to 2, persists `provenance` optionally, and decodes both v1 (defaulting to `.manual`)
  and v2 drafts while still rejecting `version > 2`.
- **Accessibility Extra-Large polish (H2c follow-up):** removed double-scaling in `HifzPracticeView` (previously
  `@ScaledMetric` combined with `.font(.custom(..., relativeTo: .title3))`) and stacked `.reciting` and `.grading` action
  rows cleanly when `dynamicTypeSize.isAccessibilitySize` so buttons never clip or truncate (`Mist...` / `Corr...`) at AX-XL.
- **Strings:** 4 new `hifz_practice.recite*` keys added across all 16 `Localizable.strings` catalogs (agent translations);
  model download, preparing, silence timeout, failure and microphone-denied alerts reuse V1/V2a keys.

## Trade-offs

- **Complexity added:** `PracticeRecitationTracker` (228 lines) and `RecitationMicrophone.clearBuffer()` (+6 lines) in
  `RecitationRecognition`; provenance support and v1/v2 draft migration in `MemorizationService` (+50 lines across 3 files);
  live recitation wiring and AX-XL layout in `HifzPracticeFeature` (~480 lines across 3 files); 8 lines in
  `QuranInteractor`; 4 strings × 16 catalogs; 15 new tests across 3 test targets. No new third-party dependency,
  permission, entitlement, or Core Data schema change (Core Data `Quran 4` already had `provenance`).
- **Who benefits / how often:** learners memorizing passages hands-free while reciting aloud from the Mushaf or
  translation view; likely a minority of readers, used in multi-minute practice sessions (UNVERIFIED, no analytics).
- **Rejected cheaper options:** reusing `RecitationFollower` unmodified (its 3-word start threshold breaks 1- and 2-word
  ayahs and its 80-unit lookahead plus whole-Quran relocation would skip unrecited ayahs and falsely mark them correct);
  pausing for manual grading after every ayah (breaks hands-free memorization flow); building a separate hands-free
  screen (would duplicate masking, drafts, cues and navigation across all three reader presentations).
- **Ongoing cost:** one Core ML window call per second while live recitation is toggled on (none while off); ~852 MB
  simulator footprint while loaded (released on Practice exit; phone footprint and 10-minute battery UNVERIFIED);
  recognition thresholds and short-ayah sensitivity may need device tuning.

## Changes

- `Domain/RecitationRecognition/Sources/PracticeRecitationTracker.swift` (new): bounded monotonic practice tracker with
  skip guard, short-ayah thresholds, manual `sync`, and off-track detection.
- `Domain/RecitationRecognition/Sources/RecitationMicrophone.swift`: `clearBuffer()` for cumulative step boundaries.
- `Domain/MemorizationService/Sources/Passage.swift`: `VerseRecall.provenance` (defaults to `.manual`).
- `Domain/MemorizationService/Sources/MemorizationService.swift`: writes `recall.provenance` to `RecallEvidenceRecord`.
- `Domain/MemorizationService/Sources/PracticeStateStore.swift`: draft v2 storing `provenance`, backward-compatible with v1.
- `Features/HifzPracticeFeature/Sources/HifzPracticeBuilder.swift`: wires `RecitationEngineLoader` and rolling `RecitationMicrophone`.
- `Features/HifzPracticeFeature/Sources/HifzPracticeViewModel.swift`: live recitation lifecycle, download, 1 s streaming
  loop, silence timeout, monotonic reveal, auto-advance, cumulative buffer reset, manual overrides.
- `Features/HifzPracticeFeature/Sources/HifzPracticeView.swift`: live-recite mic button, inline live status / model
  download banner, alerts, VoiceOver announcements, AX-XL responsive stacking, fixed double-scaled Arabic font size.
- `Features/QuranViewFeature/Sources/QuranInteractor.swift`: reader mic button toggles live recitation during Practice;
  `stopRecitationFollow()` and practice restart stop Practice's live microphone.
- `Core/Localization/Sources/Resources/*/Localizable.strings`: 4 `hifz_practice.recite*` keys in all 16 catalogs.
- `Package.swift`: `BatchDownloader` added to `HifzPracticeFeatureTests` testDependencies.
- Docs: `Documentation/agents/quran-prioritized-roadmap.md`, `Documentation/agents/quran-roadmap-progress.md`,
  `Documentation/agents/feature-cost-register.md`, `Documentation/trail/README.md`.
- Platforms: iPhone and iPad (one universal target); no platform conditionals.

## Tests

- `Domain/RecitationRecognition/Tests/PracticeRecitationTrackerTests.swift` (9 new tests): word-by-word reveal and
  advance across 112:1–4; 1-word (`103:1`) and 2-word (`112:2`) sole stretches; skip guard; seamless crossing after
  matching current ayah; manual `sync` override never un-reveals; basmala/silence ignored and 3-miss off-track recovery;
  trailing self-correction; 30-word ayah bounded lookahead; `RecitationMicrophone.clearBuffer()`.
- `Domain/MemorizationService/Tests/PracticeStateStoreTests.swift` (+updated/expanded): v1 draft decodes with `.manual`,
  v2 round-trips `.model`, v3 rejected.
- `Domain/MemorizationService/Tests/MemorizationServiceTests.swift` (+1 test): `recordSession` persists `.model` vs
  `.manual` provenance.
- `Features/HifzPracticeFeature/Tests/HifzPracticeViewModelTests.swift` (+5 tests, 4 with real Core ML model):
  missing model offers download without blocking manual practice; real-model streaming of `Husary_112001..112004` reveals
  progressively, auto-advances 112:1–4, saves 4 `.model` `.correct` records and finishes; manual hints/peeks + `Check` +
  Listen & Repeat override live recitation; cumulative order across step boundaries (`112:1`, `112:2`, `112:1+2`);
  line-page cues update live as words are recited.
- Regression evidence: verified behavior via new owning-module tests and visual simulator inspection (the initial AX-XL
  simulator screenshot revealed horizontal overflow on `.reciting` and truncated `Mist...`/`Corr...` on `.grading`;
  stacking under `dynamicTypeSize.isAccessibilitySize` resolved both, confirmed by re-capturing the screenshots).

## Validation

- **Verified:**
  - `make format-lint`: `0/1259 files require formatting, 61 files skipped.`
  - Focused no-sync targets:
    - `PracticeRecitationTrackerTests`: `Executed 9 tests, with 0 failures (0 unexpected)`
    - `MemorizationServiceTests`: `Executed 24 tests, with 0 failures (0 unexpected)`
    - `HifzPracticeFeatureTests`: `Executed 18 tests, with 0 failures (0 unexpected)` (all 4 Core ML streaming tests ran)
    - `LocalizationTests`: `Executed 53 tests, with 0 failures (0 unexpected)`
  - Full Quran no-sync suite (`make test-no-sync`): `passedTests: 1757`, `failedTests: 0`, `skippedTests: 0`
    (`Run-QuranEngine-Package-2026.11.27_13-06-23--0800.xcresult`).
  - Full Quran sync suite (`make test-sync`): `passedTests: 2238`, `failedTests: 0`, `skippedTests: 0`
    (`Run-QuranEngine-Package-2026.11.27_13-12-42--0800.xcresult`).
  - Full Arabican suite (`make test-arabican`): `passedTests: 117`, `failedTests: 0`, `skippedTests: 0`
    (`Run-ArabicLearning-Package-2026.11.27_13-19-23--0800.xcresult`).
  - App builds & pins: `make build-example-no-sync` (`Build Succeeded`), `make build-example-sync` (`Build Succeeded`,
    tracked no-sync `Package.resolved` restored), `make build-arabican` (`Build Succeeded`),
    `bash Tools/package-pins.test.sh` (`5 passed, 0 failed`).
  - Simulator UI verification on iPhone 18 Pro Max (`C4D112D1-BB82-4A00-A6AE-9CAE1A7A7148`, iOS 27.2) with simulated
    microphone (`-RecitationSimulatedInput Husary_112001..112004.mp3`):
    - Light mode, Portrait (Hafs 1405): Practice started on 112:1, tapping `Recite to Reveal` showed `"Listening… Recite
      to reveal each word."` with red active mic, automatically uncovered 112:1 → 112:2 → 112:3 and advanced to 112:4
      without touching the screen, and tapping `Check` stopped live recitation immediately (`** TEST SUCCEEDED **`).
    - Dark mode + Accessibility Extra-Large Dynamic Type (`accessibility-extra-large`) + Landscape: after fixing AX-XL
      stacking, re-verified clean card margins, stacked icon row + full-width `Check`, and stacked `Forgot`/`Mistakes`/
      `Correct` with zero truncation (`** TEST SUCCEEDED **`). Left simulator in Light mode, Large text.
- **Not verified:**
  - Physical device real-microphone latency, room-noise rejection, memory footprint, and 10-minute battery draw (owner
    checklist item 30).
  - Compact-iPhone width and iPad split view (reasoned via `dynamicTypeSize.isAccessibilitySize`, flexible frames, no
    fixed widths).
  - On-device VoiceOver announcements (off-track / silence stop) and focus order.
  - Native review of the 4 new agent-translated strings in the 15 non-English catalogs.

## Release

- **Commit:** pending commit
- **Pushed:** pending push
- **TestFlight:** pending upload (both Quran and Arabican — `Localization` changed)
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Tune `PracticeRecitationTracker` and `SpeechLevel` thresholds from physical-device hands-free memorization feedback
  (owner checklist item 30).
- Proceed to **H3** (Memorization map and passage review queue: declare memorized ranges, juz → surah → ayah map, due
  queue with Sabaq/Sabqi/Manzil buckets opening H2/V2b Practice).
