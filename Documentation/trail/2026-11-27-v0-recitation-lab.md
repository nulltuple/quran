# V0 slice (c): developer Recitation Lab (live microphone recognition) behind debug logging

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-27-v0-word-alignment.md](2026-11-27-v0-word-alignment.md) (slice b),
  [2026-11-26-v0-recitation-engine.md](2026-11-26-v0-recitation-engine.md) (slice a)

App: **Quran** (new Features module `RecitationLabFeature`, `SettingsFeature` Diagnostics row, `RecitationRecognition`
additions, `Example` Info.plist microphone string). Arabican does not import any of these modules.

## Context

Roadmap §6 V0 deliverable 8: "a development-only demonstration screen if needed to validate live microphone recognition
(not shipped to testers, or behind a debug setting)", and deliverable 5's device benchmarks (latency, memory). The owner
approved the microphone permission (D4, 2026-11-26). Where the 125 MB model is downloaded from on a phone is still open
(D7, roadmap §7).

## Decisions

- **Behind a new "Developer tools" switch, off by default.** The first version gated the row on "Enable debug logging",
  but the simulator check showed that switch is on and disabled in every build (`Container.isDebugLoggingAlwaysEnabled`
  returns `true`, `Example/QuranEngineApp/Classes/Container.swift:98`), TestFlight included, so every tester would have
  seen the lab. Settings > Diagnostics now has a "Developer tools" switch (`DiagnosticsPreferences.showDeveloperTools`,
  key `showDeveloperTools`, default off) that reveals the "Recitation Lab" row. One Bool preference.
- **English only, not localized.** A developer screen; adding ~20 keys to 16 catalogs for it is cost without benefit.
  Every tester sees the "Developer tools" switch and its footer in English on the Diagnostics screen (which already says it
  is for the developer); the microphone prompt (`NSMicrophoneUsageDescription`, English) appears only after opening the lab
  and tapping Record.
- **The model is installed by hand until D7.** `RecitationModelStore` loads `TilawiFastConformerInt8.mlpackage` and
  `vocab.json` from `Application Support/RecitationModel`, compiles the package on first load and keeps the compiled
  `.mlmodelc` beside it. Without the files the screen says where to put them. A download replaces the hand copy once the
  owner decides D7.
- **Recording into memory, resampled once at the end.** `RecitationMicrophone` taps `AVAudioEngine`'s input, keeps the
  first channel at the hardware rate under a lock (at most 60 s, ~11 MB at 48 kHz) and resamples to 16 kHz with the existing
  `RecitationAudio.resample` when recording stops. A streaming converter waits for V2. Nothing is written to disk.
- **The audio session is put back.** `QueuePlayer` sets `.playback` once at launch; the microphone saves the session's
  category, mode and options before switching to `.record`/`.measurement` and restores them on stop.
- **One model run per recording.** `RecitationRecognizer.identifyVerses(in: [RecognizedWord])` identifies from the words
  `recognizeWords` produced, and `WordAligner` aligns those same words, instead of transcribing twice.

## Trade-offs

- **Complexity added:** Features module `RecitationLabFeature` (4 files), Domain `RecitationModelStore`,
  `RecitationVerseText`, `RecitationMicrophone`, `RecitationAudio.resample(mono:sampleRate:)`,
  `RecitationRecognizer.identifyVerses(in:)`; a Diagnostics row; the app now links `RecitationRecognition` (Core ML,
  AVFoundation: both system frameworks). New permission string: microphone (D4). New failure modes: microphone denied
  (alert says where to allow it), model missing (screen says where to copy it), a corrupt model (load error shown).
- **Who benefits / how often:** the owner and agents validating V0 on a device; testers never see it unless they turn on
  debug logging. Rarely used by design.
- **Rejected cheaper options:** a unit-test-only validation (cannot prove live microphone capture or device latency);
  bundling the model (125 MB to every install, D7 proposes a download); a new hidden preference (debug logging already is
  the developer switch).
- **Ongoing cost:** binary size of the new Swift code (small; no model bundled). No launch cost: nothing runs until the
  screen opens. Peak memory while recognizing: the model (~125 MB of weights) plus Core ML's working memory; measured on the
  simulator below, device numbers are the owner's.

## Changes

- `Domain/RecitationRecognition/Sources/`: `RecitationModelStore` (find, compile once, load), `RecitationVerseText`
  (matcher + expected words from the bundled databases), `RecitationMicrophone` (`AVAudioEngine` tap into memory, session
  restore; `RecitationMicrophoneError`), `RecitationAudio.resample(mono:sampleRate:)`,
  `RecitationRecognizer.identifyVerses(in: [RecognizedWord])`. The module now also depends on `Utilities`
  (`ManagedCriticalState`).
- `Features/RecitationLabFeature/` (new): `RecitationLabBuilder` (model directory `Application Support/RecitationModel`),
  `RecitationLabViewModel` (model state, recording state, result with candidates, transcript, aligned words with seconds,
  audio length, input peak in dBFS, recognition ms, real-time factor, memory footprint), `RecitationLabView`,
  `ProcessMemory` (`task_vm_info.phys_footprint`).
- `Features/SettingsFeature/Sources/Diagnostics/`: `DiagnosticsPreferences.showDeveloperTools`; the view model's
  `showDeveloperTools` and `openRecitationLab()`; the view's Developer tools section; the builder passes a
  `RecitationLabBuilder`.
- `Example/QuranEngineApp/Info.plist`: `NSMicrophoneUsageDescription`.
- `Package.swift` (the new target; SettingsFeature and its tests depend on it), `QuranEngine-Package.xctestplan`.
- Platform-neutral: the same screen on iPhone and iPad; no `#if`.

## Tests

- `RecitationModelStoreTests` (3): empty directory, vocabulary without a model, compile once and keep (the kept compiled
  model loads after the package is removed; with the real model).
- `RecitationAudioTests` (3): 48 kHz tone → 16 kHz length and level kept; 16 kHz unchanged length; empty input.
- `RecitationLabViewModelTests` (2): no model → `.notInstalled` with the directory; with the real model and the Husary
  112:1 recording fed to `analyze`: 112:1 confident, 4 matched words with timing, the first `112:1:1 قُلۡ`, audio length,
  input peak above −20 dBFS, recognition time and footprint present.
- `DiagnosticsViewModelTests` (+2): developer tools off by default (with debug logging always on) and saved;
  `openRecitationLab()` pushes a screen titled Recitation Lab.
- The microphone itself has no unit test (platform boundary, needs sound): checked in the simulator (Validation).

## Validation

- **Verified:**
  - `make test-no-sync TARGET=RecitationRecognitionTests`: 53 passed, 0 skipped; `TARGET=RecitationLabFeatureTests`: 2
    passed, 0 skipped; `TARGET=SettingsFeatureTests`: 43 passed (xcresult summaries).
  - Simulator (iPhone 18 Pro Max, `make run-example-no-sync`; model copied into the app's
    `Application Support/RecitationModel`, microphone granted with `xcrun simctl privacy … grant microphone`):
    Diagnostics shows Developer tools off by default, on → Recitation Lab row; the lab compiled and loaded the model
    (first open 1,800 ms including the compile; later opens 1,325–1,336 ms); Record → Stop recognized 11.5–14.1 s of
    audio in 267–281 ms (real-time factor 0.020–0.023, the simulator runs Core ML on the Mac's CPU); memory footprint
    851–852 MB after recognition (simulator; float32 compute; device number is the owner's). Live microphone: Husary 112:1
    played through the Mac's speakers at volume 13 was heard as «قُ هو اللهَح» (the verse is «قل هو الله احد»); the
    matcher answered "not confident" with candidates instead of guessing, and the word list showed the first candidate's
    alignment with times. With the speakers muted the input peaked at −26 dBFS (room noise) and the transcript was one
    letter, as expected.
  - `make format-lint`: `0/1213 files require formatting`.
  - `make test-no-sync`: 1,623 passed, 0 failed, 0 skipped; then `make test-sync`: 2,102 passed, 0 failed, 0 skipped;
    then `make test-arabican`: 117 passed, 0 failed (xcresult summaries; one after the other; model present).
  - `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: `Build Succeeded` (Package.resolved
    restored after the sync runs).
- **Not verified:**
  - Any physical device: latency, memory, energy, Neural Engine use, a real reciter at normal distance (owner checklist
    item 23; needs the model on the phone, D7 or a hand copy through Xcode's device container).
  - Dark mode, the largest text size and VoiceOver on the lab (a developer screen; plain `List` rows and system controls).
  - The audio session restore after recording while a recitation plays (reasoned from the code: category, mode and
    options saved and restored).
  - iPad layout (no iPad simulator per AGENTS.md; a plain list).
  - The 852 MB footprint is high: float32 compute of a 115 M parameter model plus Core ML buffers on the simulator; on a
    device the Neural Engine is unused until the float16 fault is fixed (slice a follow-up). A memory measurement on a
    phone decides whether V1 needs the int4 package or a smaller window.

## Release

(recorded after the full suites, builds and upload)

## Follow-ups

- **D7:** the model download (owner decision), then a Download button on this screen and V1.
- Device benchmarks by the owner (checklist item 23): latency, memory footprint, energy, a real recitation.
- Memory: measure on a phone; if far above ~500 MB, try the int4 package, a shorter window, or the float16 fix for the
  Neural Engine.
- V2 will need a streaming converter (the lab resamples once at the end).
