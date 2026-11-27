# Quran V3a: recite and check, and a simulated microphone for hands-on checks

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature | tooling
- **Status:** shipped
- **Related:** [2026-11-27-v2a-live-follow.md](2026-11-27-v2a-live-follow.md),
  [2026-11-27-v0-word-alignment.md](2026-11-27-v0-word-alignment.md),
  [2026-11-27-quran-roadmap-v4-order.md](2026-11-27-quran-roadmap-v4-order.md) (V3a is item 9 of roadmap §5)

## Context

App: **Quran** (QuranEngine modules `RecitationRecognition`, `RecitationFollowFeature`, `AyahMenuFeature`,
`QuranViewFeature`, `NoorUI`, `Localization`). Not Arabican: it imports none of these modules
(`ArabicLearning/Package.swift` names no recitation product), so Arabican is tested and built but not released.

The owner asked to continue the roadmap at its first next step, V3a (roadmap §6, progress Handoff "Next steps" 1):
pick a passage, recite, stop, and see confidence-gated omissions, substitutions and skipped ayahs, with grace for
self-correction, nothing stored, behind a release quality gate on public recordings with planted mistakes.

The owner also asked whether a loopback audio setup (BlackHole 2ch) or permanent test infrastructure would make
recitation testing and tuning more accurate, because playing fixtures through the Mac's speaker into its microphone
picks up room noise (V1 and V2a trails, Not verified) and the room cannot be quiet. They asked for it only if it is
small.

## Decisions

- **Loopback: a simulated microphone in the app, not BlackHole.** BlackHole is a system audio driver: the owner
  would install it (administrator password) and switch the Mac's default input and output to it for every check,
  silencing the Mac for anything else. The simulator records from the Mac's default input, so that is the only way
  BlackHole helps, and it still goes through the real-time audio path with resampling. A seam in
  `RecitationMicrophone` is smaller and exact: in **debug builds only** (`#if DEBUG` at the one call site), when the
  `RecitationSimulatedInput` default names audio files, `start()` plays them into the recording at real-time speed
  (100 ms chunks on a clock), each after 1 s of quiet floor (±0.002, like a still room, so `SpeechLevel` measures a
  room), then quiet floor until `stop()`. Set it with a launch argument:
  `xcrun simctl launch <udid> com.nulltup.memquran -RecitationSimulatedInput /abs/a.mp3,/abs/b.mp3`. Voice search,
  live follow and recite and check all record through `RecitationMicrophone`, so all three can be checked hands-on
  with the same audio every run, without speaker, microphone, permission prompt or room. Model *tuning* never
  needed loopback: the tests and `Tools/recitation-model.py eval` already feed files to the model; the loopback only
  makes the end-to-end UI checks repeatable. Planted-mistake audio for UI checks can be made with any audio editor
  (or by concatenating fixtures, as below).
- **Confidence from the model's own posteriors, not forced alignment of the expected text.** CTC forced alignment
  needs the expected Uthmani words tokenized into the model's SentencePiece pieces, and the model writes imla'i
  spellings (V0 (b) trail), so a correctly recited word would often score low. Instead `CTCDecoder.decode(_:)` now
  keeps each token's mean probability over its frames (`CTCToken.confidence`), and `RecognizedWord.confidence` is its
  least confident token's. A substitution is reported only when every recited word of it has confidence ≥ 0.6
  (`RecitationChecker.minimumConfidence`); otherwise the word is "uncertain" (orange, "check this", not a mistake).
  Forced alignment remains a follow-up (V3b/V4) if device results call for it.
- **Verdict rules** (`RecitationChecker`, Domain, pure): align with `WordAligner.alignWithin(preferredEnd: 0)`
  (semi-global, earliest place) so a recitation stopped early ends where it stopped instead of being stretched over
  the passage with omissions (the first version, with global `align`, marked 112:1's last words omitted when only
  112:1 was recited and matched الله to 112:2). Then: matched → correct; mismatched with similarity < 0.5 and
  confident → substituted, else uncertain; omitted → omitted; a slip with an extra recited word next to it that
  matches the expected word → correct (self-correction); words before the first recited one → omitted (the reader
  chose where the passage starts); after the last → not reached; a verse with no recited word before the last
  recited word → skipped verse. **Extra words are never mistakes**: reciters repeat phrases, and the model hears the
  basmala and isti'adha; the roadmap item lists insertions, but flagging them would mostly flag repetition. Recorded
  for V3b.
- **Absorbed omissions.** The aligner lets one recited word stand for two expected ones (script splits, joined
  words), so a left-out short word was absorbed: cutting في from 2:11 still "matched" `تفسدوا` to `تُفۡسِدُواْ فِي`.
  When each recited word fits one of the step's units alone at least as well as the step does, the other units are
  omitted (`RecitationChecker.unitsLeftOut`). This raised the gate's cut detection from 71% to 92%.
- **Quality gate** (`RecitationCheckerRecitationTests`): the 350 real model transcripts of 50 EveryAyah verses by
  seven reciters (the V0 fixtures; held out from every threshold chosen before V3a), checked as they are (any
  mistake is a false alarm) and with one planted mistake each in the middle word: cut, or swapped for a dissimilar
  word of another clip. Gate: ≤ 1 false alarm per 100 correctly recited words, ≥ 90% of cuts and of swaps found at
  the right word. Measured: 33 false alarms in 4,305 words (0.77%), cuts 213/232 (92%), swaps 212/230 (92%). Most
  misses are words the verse says twice. Text-level planting has no acoustic confidence (nil counts as confident);
  two model-backed tests cover the audio path (skipped verse, early stop).
- **Window cuts at pauses.** A passage is longer than the model's 20 s window; a word cut by the window edge is
  misheard and would be reported as a mistake. `RecitationRecognizer.recognizeWords` now ends each window (when more
  audio follows) after the quietest 80 ms frame of its last 4 s, on a whole frame from the window's start so word
  frames stay exact. V1, V2a and the lab use the same function; a single window is unchanged.
- **Passage:** the ayah menu's selection; for one selected verse, that verse to the end of its page **within its
  sura** (the first simulator run, from 112:1, ran on into suras 113 and 114 of page 604). Recording keeps at most
  300 s (`RecitationMicrophone(maximumSeconds:)`, new; ~57 MB at 48 kHz), then checks on its own.
- **The text is hidden while reciting** (it is a memory check); the result shows the passage in the Quran font with
  omitted words struck through in red, substitutions underlined in red, uncertain words underlined in orange and
  words not reached faded, a verse marker after each verse, then one line per skipped verse, left-out word and
  substitution, and a count of words to check. New NoorUI `QuranMarkedText` (Quran font is NoorUI-internal).
- **Where it lives:** in `RecitationFollowFeature` (the reader's voice feature), not a new module: it shares the
  engine loader, download and microphone handling with live follow, and a new target would add a package target,
  test target and test-plan entry for ~400 lines. Presented with the reader's existing sheet path
  (`presentTranslatedVerse`: medium/large detents, Close ×); opening it pauses audio and stops live follow;
  dismissing stops the microphone.
- **Strings:** 16 `recitation_check.*` keys in all 16 catalogs (agent translations, need native review); download,
  preparing, failed and Open Settings texts reuse `voice_search.*`.

## Trade-offs

- **Complexity added:** 44 files, 1,869 insertions with docs, 256 string lines and tests: Domain `RecitationChecker` (~190, pure),
  token/word confidence (+~25), quiet window cuts (+~30), microphone `maximumSeconds` and simulated input (+~75);
  feature view model, view, builder (~480); NoorUI `QuranMarkedText` (~95); ayah menu row and listener (+~30);
  reader wiring (+~20); 16 strings × 16 catalogs; tests ~420. No new dependency, permission or entitlement (the
  microphone usage string exists since V0 (c)). Nothing persisted. The recording (≤ 300 s) is held in memory only
  while the sheet records, then dropped.
- **Who benefits / how often:** people memorizing who want a check without a teacher at hand; likely a minority of
  readers, but it is the roadmap's flagship voice feature and the base of V3b's mistake history.
- **Rejected cheaper options:** BlackHole loopback (above); reusing live follow's capsule for the check (follow keeps
  only 10 s and shows the text); flagging insertions (repetition is not a mistake); CTC forced alignment (needs a
  tokenizer and an imla'i form per word; deferred).
- **Ongoing cost:** thresholds (0.5 similarity, 0.6 confidence, 4 s quiet search) need device tuning with the owner's
  own recitation; the gate test (~7 s) guards regressions. The model stays loaded while the sheet is open (~852 MB
  footprint on the simulator, phone UNVERIFIED). The simulated input is debug-only code in a shipped type.

## Changes

- `Domain/RecitationRecognition/Sources/RecitationChecker.swift` (new): `CheckedWord`, `RecitationCheck`,
  `RecitationChecker`.
- `Domain/RecitationRecognition/Sources/CTCDecoder.swift`: `CTCToken.confidence`, filled by `decode(_:)`.
- `Domain/RecitationRecognition/Sources/RecognizedWord.swift`: `RecognizedWord.confidence`.
- `Domain/RecitationRecognition/Sources/RecitationRecognizer.swift`: `windowEnd(_:from:length:frame:)`, used by
  `recognizeWords`.
- `Domain/RecitationRecognition/Sources/RecitationMicrophone.swift`: `init(maximumSeconds:)`; simulated input
  (`simulatedInputKey`, `simulatedSignal`, `startSimulatedInput`).
- `Features/RecitationFollowFeature/Sources/RecitationCheck{ViewModel,View,Builder}.swift` (new).
- `UI/NoorUI/Sources/Components/QuranMarkedText.swift` (new).
- `UI/NoorUI/Sources/Features/AyahMenu/AyahMenu{UI,View}.swift`: optional `reciteToCheck` action, row under Repeat.
- `Features/AyahMenuFeature/Sources/AyahMenu{ViewModel,ViewController}.swift`: `reciteToCheck`, listener method.
- `Features/QuranViewFeature/Sources/Quran{Interactor,Builder}.swift`: `recitationCheckBuilder`, `reciteToCheck(_:)`.
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: 16 keys.
- iPhone and iPad share every change; no platform conditionals.

## Tests

- `RecitationCheckerTests` (10): faithful recitation, omission, confident substitution, unsure substitution →
  uncertain, near miss → uncertain, self-correction, going back over a phrase, early stop → not reached, skipped
  verse, nothing recited.
- `RecitationCheckerRecitationTests` (1): the quality gate above.
- `CoreMLRecitationModelTests` (+2): Husary 112:1+3+4 against 112:1–4 → skipped verse 2 and nothing else, decoded
  words carry confidence; 112:1 alone → the rest not reached.
- `RecitationWindowEndTests` (3, in `RecitationAudioTests.swift`): short recording, cut inside a pause, no pause.
- `RecitationMicrophoneSimulatedInputTests` (3): the default's file list, the signal's quiet gaps, real-time feed.
- `RecitationCheckViewModelTests` (5): passage to the end of the page, stopping at the sura's end, selection as
  passage, download offered without a model, a checked recitation with a skipped verse marked on the text.
- `AyahMenuViewModelTests` (+1): Recite to Check opens the check for the selected verses.
- The window-cut and absorbed-omission fixes were each measured by the tests before the fix (gate cuts 71% → 92%;
  `testWordsAfterTheLastRecitedOneAreNotReached` failed with global alignment, output in Decisions).

## Validation

- **Verified:** `make format-lint`: `0/1238 files require formatting`. Full suites, one after the other
  (`xcresulttool get test-results summary`): `make test-no-sync` 1,691 passed, 0 failed, 0 skipped; `make test-sync`
  2,171 passed, 0 failed, 0 skipped; `make test-arabican` 117 passed, 0 failed, 0 skipped. Builds:
  `make build-example-no-sync`, `make build-example-sync`, `make build-arabican` each `Build Succeeded`. Focused runs: `RecitationRecognitionTests` `Executed 105
  tests, with 0 failures`; `RecitationFollowFeatureTests` `Executed 10 tests, with 0 failures`; `NoorUITests`
  `Executed 275 tests, with 0 failures`; `LocalizationTests` `Executed 53 tests, with 0 failures`. Model-backed tests
  ran (model in `.cache/recitation-model`; none skipped).
- **Simulator (iPhone 18 Pro Max), through the simulated microphone** (launched with
  `-RecitationSimulatedInput` Husary 112:1, 112:3, 112:4): page 604, long press 112:1 → ayah menu shows Recite to
  Check under Repeat → sheet: Preparing, then the instruction and Start Reciting → Start → Stop and Check after ~20 s
  → "Mistakes: 2", verse 2 (ٱللَّهُ ٱلصَّمَدُ) struck through in red, verses 1, 3, 4 plain, "Skipped verse 2". Checked
  in Light at the default size and in Dark at Extra Extra Large text (wraps, no clipping).
- **Not verified:** a real microphone on a phone, the owner's own recitation and its mistakes (thresholds may need
  tuning: checklist item 26); memory and latency of a 5-minute check on a phone; landscape; VoiceOver reading of the
  result (the summary is announced; the marked text reads as plain Arabic without the marks: a follow-up if it
  matters); iPad sizes (reasoned: one column, no fixed widths); the agent translations.

## Release

- **Commit:** `b5d48dfd` feat(reader): recite and check with a simulated microphone (V3a)
- **Pushed:** origin/main at `b5d48dfd` (fast-forward from `c20bf70a`).
- **TestFlight:** Quran build 1015 (1.20.3): `Uploaded Quran iOS 1.20.3 (1015) for commit
  b5d48dfde177b7eef7309ddb36d60e0bc42f2515 to App Store Connect app MemQuran.` No Arabican build: it imports none of
  the changed modules.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Owner device check (checklist item 26): recite a known passage with a deliberate skip, a wrong word and a
  self-correction; report false alarms. Tune `minimumConfidence`, `uncertainSimilarity` and the quiet-cut search on
  the result.
- VoiceOver: expose each marked word's verdict in the result text (accessibility labels per run).
- CTC forced alignment of the expected text for per-word confidence of omissions (needs an imla'i form per word).
- Insertions as mistakes, if the owner wants them, distinguishing repetition from added words.
- V3b records confirmed mistakes as evidence (after H1/H7).
