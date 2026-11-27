# Quran V2a: live recitation follow in the reader

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-27-v1-voice-search.md](2026-11-27-v1-voice-search.md) (loader, microphone, level thresholds),
  [2026-11-27-v0-word-alignment.md](2026-11-27-v0-word-alignment.md) (`WordAligner`, `ExpectedWordsReader`),
  [2026-11-26-v0-recitation-engine.md](2026-11-26-v0-recitation-engine.md) (streaming recommendation),
  [2026-11-27-quran-roadmap-v4-order.md](2026-11-27-quran-roadmap-v4-order.md) (V2a after V1)

App: **Quran** (Domain `RecitationRecognition`; Features `RecitationFollowFeature` (new), `QuranViewFeature`; UI `NoorUI`;
Core `Localization`). Arabican imports `NoorUI` and `Localization`, so it is tested, built and released too; it imports
none of the recitation or reader modules.

## Context

Roadmap §6 V2a: "a 'Recite' control in the reader starts the microphone; streaming recognition (overlapping windows, V0
trail) aligned to the expected text from the current page onward, with the visible page as a soft prior; the recited word
is highlighted with the existing word-highlight path (the one recitation audio uses) and the page scrolls or turns as the
reciter moves on. Losing the place pauses following and says so; it resumes when a confident match returns. Mic indicator
always visible; stop is one tap; nothing recorded is kept. Measure latency (target: highlight within ~1 s of the word) and
battery for 10 minutes on a device."

The V0 recommendation (slice a trail) was the same CTC model in overlapping windows, 4–6 s every 1–2 s. The Core ML model
pads every call to 20 s (`CoreMLRecitationModel.windowSampleCount`), so a window costs the same to recognize at any length.

## Decisions

- **Window 8 s every 1 s** (`RecitationFollowViewModel.windowSeconds`, `hop`). Longer than V0's 4–6 s because the model
  cost is fixed per call; more words give the alignment context. Each update takes 220–254 ms on the simulator (M4 Pro host),
  so the highlight trails the voice by about the hop plus recognition, ~1–1.3 s; on a phone UNVERIFIED.
- **Place tracking is a pure Domain type, `RecitationFollower`.** Each window's words are aligned with a new
  `WordAligner.alignWithin` (semi-global: the passage's words before and after the recited stretch are free; of equal
  places, the one ending nearest the expected place wins, so 114:1–3's repeated النَّاسِ resolves to where the reciter is).
  The window moves the place only when it fits where it ends: ≥2 matched words (≥3 before the first fit, when the whole
  loaded passage is searched) and ≥2 of its last 4 words matched. When the window ends on words that don't fit after the
  last match, those trailing words are aligned again on their own, so a reciter who goes back to repeat a phrase is
  followed back (one order-keeping alignment cannot hold both places).
- **Search region:** 20 units behind and 80 ahead of the place; before the first fit, the pages in view plus the next page.
  More text is appended a page at a time when fewer than 100 units remain ahead; at most 600 units are kept.
- **Lost:** 3 windows of speech in a row that don't fit lose the place; the capsule says so and the last word stays
  highlighted. Every window while lost is matched against the whole Quran (`VerseMatcher`, off the main actor); a trusted
  match restarts following at its page. Before the first fit there is no place to lose: the state stays "Listening", but
  repeated misses also search the whole Quran, so reciting another sura finds it without touching the screen. The basmala
  and isti'adha are not misses (`RecitationFollower.isOpening`), so a sura change doesn't flash "lost".
- **Pauses are not misses:** the model hears a few junk words in room noise. A window counts as a miss only when its last
  second is speech by `SpeechLevel` (V1's thresholds: ≥3× the room's noise and ≥−40 dBFS; the room's noise is the quietest
  0.1 s heard, so a window recited from its first sample still has the gaps between words). The first version used every
  recognized word and showed "Lost" 5 s into listening before any recitation (logged in the simulator).
- **Highlight path:** the interactor sets `highlightReadingAyah` (only when the verse changes) and `highlightRecitedWord`,
  exactly as audio playback does, so the page scrolls and turns with the existing `verseToScrollTo` logic; words are read
  in the reader's edition (pages give `AyahNumber`s of `ReadingPreferences.reading.quran`; tests use Hafs 1440).
- **Entry point:** a microphone bar button in the reader (`NoorSystemImage.reciteAlong`, alias of `mic`), left of the
  bookmark. Tapping it again while following stops. The Mushaf and translation views share it.
- **Status capsule where the audio banner sits:** the banner hides while following (the microphone and playback don't run
  together) and the capsule stays visible when the bars auto-hide, as the microphone indicator must. It shows Preparing,
  Download (84 MB), Listening, Following + verse, Lost, Stopped after a minute without speech, and Stop (×). Liquid Glass
  capsule like the banner (`glassEffect(in: .capsule)`). Taps on it don't toggle the bars.
- **Audio:** Recite pauses recitation audio; starting audio (banner or ayah menu Play) stops following.
- **The microphone stops** when Stop is tapped, the reader disappears, the app enters the background (also covers the lock
  screen), or after 60 s without speech. `RecitationMicrophone(keepingLatestSeconds:)` keeps only the latest 10 s in memory
  (dropping the oldest once 20 s are held), so 10 minutes of following hold no more than a search does.
- **After the download the capsule waits for Recite**, as V1 does after its download.
- **Strings:** 9 `recitation_follow.*` keys in all 16 catalogs (agent translations); the download, preparing, failed,
  microphone-unavailable and Open Settings texts reuse V1's `voice_search.*` keys, whose meaning is identical.
- **VoiceOver:** the capsule's text reads as one element; losing the place and stopping after silence are announced (each
  word is not: it would talk over the reciter).

## Trade-offs

- **Complexity added:** `RecitationFollower` (~205 lines) and `SpeechLevel` (~50) in Domain, `WordAligner.alignWithin`
  (+~45), `RecitationMicrophone` rolling buffer and `recentSamples` (+~40); new `RecitationFollowFeature` (view model ~360,
  capsule ~200, builder ~55); reader wiring (~125 lines over 4 files); 9 strings × 16 catalogs; 3 EveryAyah fixtures
  (+155 KB, Husary 112:2–4 at 64 kbps). No new dependency, permission or entitlement (microphone usage string shipped in V0
  (c)). Background work: one model call a second while following (~25% of a simulator core); none otherwise.
- **Who benefits / how often:** people who recite from the Mushaf and want the page to keep up (hands-free reading, a
  self-check of the place); likely a minority, used in sessions of minutes (UNVERIFIED, no analytics). It is the streaming
  base V2b (Practice) and V3a reuse.
- **Rejected cheaper options:** highlighting only the verse (simpler, but the roadmap asks for the word and audio already
  has a word path); a streaming Zipformer (needs an ONNX runtime, unavailable, V0 trail); recognizing the whole recording
  each second (cost grows without bound); a full-screen recite mode (hides the reader the person is reading).
- **Ongoing cost:** the thresholds (matches, misses, level gate) will need tuning from device use; memory while following
  is the loaded model (~852 MB footprint on the simulator during recognition, phone UNVERIFIED); battery for 10 minutes
  UNVERIFIED (owner checklist item 25).

## Changes

- `Domain/RecitationRecognition/Sources/RecitationFollower.swift` (new): the place tracker.
- `Domain/RecitationRecognition/Sources/SpeechLevel.swift` (new): speech vs. room noise per window.
- `Domain/RecitationRecognition/Sources/WordAligner.swift`: `alignWithin(_:to:preferredEnd:)`;
  `WordAlignmentStep.expectedUnits`; shared step building.
- `Domain/RecitationRecognition/Sources/RecitationMicrophone.swift`: `init(keepingLatestSeconds:)`, `recentSamples(seconds:)`,
  `append(_:to:capacity:keepsLatest:)`.
- `Features/RecitationFollowFeature/` (new): `RecitationFollowViewModel`, `RecitationFollowView` (+ `RecitationFollowCapsule`
  with a `#Preview`), `RecitationFollowBuilder`.
- `Features/QuranViewFeature/Sources/`: `QuranInteractor` (Recite, stop, highlight, page changes, audio hand-off),
  `QuranViewController` (bar button, present/dismiss, stop on disappear and background), `QuranView` (capsule slot,
  audio bar hidden while following), `QuranBuilder` (builder wiring).
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: `reciteAlong`.
- `Core/Localization/Sources/Resources/*/Localizable.strings`: 9 `recitation_follow.*` keys.
- `Package.swift`, `QuranEngine-Package.xctestplan`: the new module and its tests.
- `Domain/TestResources/Sources/test_data/recitation/Husary_112002–4.mp3` (from
  `https://everyayah.com/data/Husary_64kbps/112002.mp3` …; sha256 `f6dc6fb3…7a4`, `5d7ecaaf…b42b`, `4d39323e…2c22`).
- Docs: roadmap progress, roadmap §5/§6, feature-cost-register, trail index.
- Platforms: iPhone and iPad (one universal target); no platform conditionals.

## Tests

- `RecitationFollowerTests` (16, new): first fit starts at its last word; the window slides word by word through 112:1–4
  (a cut-off last word stays on the last fitting one); crossing into 113 after the basmala; 114's repeated النَّاسِ followed
  where the reciter is; going back to repeat 112:2 follows the repeat; silence keeps the place; recitation elsewhere loses
  the place after 3 misses and coming back finds it; before the first fit misses keep searching; words heard in a pause are
  not misses; one common word doesn't start; the opening is recognized; appending keeps the place and drops old units;
  `alignWithin` covers only the recited part and prefers the nearest of equal places; `SpeechLevel` from the room's noise;
  the microphone's rolling buffer.
- `CoreMLRecitationModelTests.testStreamingWindowsFollowAlIkhlasWordByWord` (new, real model): Husary 112:1–4 streamed 8 s
  every 1 s, 27 windows of 220–254 ms; followed 1:3, 1:4, 2:1, 2:2, 3:2, 3:3, 3:4, 4:1, 4:3, 4:4, 4:5 (11 of 15 words),
  only forward.
- `RecitationFollowViewModelTests` (6, new; 5 use the real model): no model → download offered; 112:1–4 highlighted word by
  word in Hafs 1440 and ends following 112:4; Al-Fatihah in view but Al-Ikhlas recited → found in the whole Quran; turning
  the page while listening follows from the new page; Stop clears the highlight, closes, and drops a late window; silence
  keeps the highlight.
- Regression evidence: `testStoppingClearsTheHighlightAndCloses` failed before `stop()` reset the state (a window after
  Stop still highlighted: 4 highlights, expected 3); `testGoingBackToRepeatAVerseFollowsTheRepeat` failed before the
  trailing re-alignment (stayed on 112:3); the pause and before-first-fit tests encode the simulator's false "lost"
  (reasoned from the logs, written after the fix).

## Validation

- **Verified:**
  - `make format-lint`: `0/1228 files require formatting`.
  - Focused: `make test-no-sync TARGET=RecitationRecognitionTests/RecitationFollowerTests`: `Executed 16 tests, with 0
    failures`; `TARGET=RecitationFollowFeatureTests`: `Executed 6 tests, with 0 failures`;
    `TARGET=RecitationRecognitionTests/CoreMLRecitationModelTests`: `Executed 8 tests, with 0 failures`.
  - `make test-no-sync`: 1,667 passed, 0 failed, 0 skipped; then `make test-sync`: 2,146 passed, 0 failed, 0 skipped; then
    `make test-arabican`: 117 passed, 0 failed (xcresult summaries, one after the other, model-backed tests ran with
    `.cache/recitation-model` present). `make test-tools`: every tool test passed (`22 passed, 0 failed` for
    `recitation-model.test.sh`).
  - `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: `Build Succeeded` (Package.resolved
    restored after the sync runs).
  - Simulator (iPhone 18 Pro Max, page 604, Hafs 1405): the mic button opens the capsule "Listening… Recite from this
    page." in the audio bar's place; Husary 112:1–4 played through the Mac speakers was followed (screens at 112:2 ٱلصَّمَدُ
    with "the Eternal, the Absolute", and 112:4 أَحَدٌ, capsule "Following your recitation · Al-Ikhlāṣ 112:4"); the bars
    auto-hid and the capsule stayed; Stop removed it, cleared the highlight, and the audio bar came back with the bars. Dark
    mode at accessibility XL: the capsule wraps and following works (112:1). 12 s of room noise before reciting stayed on
    "Listening".
- **Not verified:**
  - In the simulator, a pause after reciting still showed "Lost" once: the Mac microphone's room noise peaks at up to 5× its
    own floor (V1 trail logs 0.02–0.10), above the speech gate. A phone held close should separate them; UNVERIFIED (owner
    checklist item 25).
  - Latency and battery on a phone over 10 minutes; memory on a phone; a page turn while following (crossing 604 is the
    last page, so the simulator check could not turn; covered by the content's existing playing-verse scroll and the
    appending tests); the translation view while following; landscape; iPad sizes and split view; VoiceOver announcements on
    a device; the download flow in this capsule (same loader as V1 and the lab); native review of 15 translated catalogs.
  - The first tap on the reader's bar right after opening it was dropped twice in the simulator (the bookmark button too
    in earlier sessions' notes); a second tap worked. Not specific to this button (UNVERIFIED on a device).

## Release

- **Commit:** the `feat(reader): live recitation follow (V2a)` commit (SHA in the follow-up trail commit)
- **Pushed:** pending
- **TestFlight:** pending (Quran and Arabican: NoorUI and Localization changed)
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Tune `RecitationFollower` and `SpeechLevel` thresholds from the owner's device use (checklist item 25).
- Per-word confidence from CTC forced alignment (V3a) could replace the "≥2 of the last 4 matched" rule.
- A Settings row to delete the 125 MB model (carried from V1).
