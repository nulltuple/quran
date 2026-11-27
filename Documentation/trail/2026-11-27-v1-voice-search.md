# V1: offline voice search on the Search tab

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-27-quran-roadmap-v4-order.md](2026-11-27-quran-roadmap-v4-order.md) (V1 first in the voice track),
  [2026-11-27-v0-model-download.md](2026-11-27-v0-model-download.md) (the download this offers),
  [2026-11-27-v0-recitation-lab.md](2026-11-27-v0-recitation-lab.md) (the lab flow this reuses),
  [2026-11-26-v0-recitation-engine.md](2026-11-26-v0-recitation-engine.md) (engine, matcher, trust gate)

App: **Quran** (Features `SearchFeature`, `RecitationLabFeature`, `FeaturesSupport`; Domain `RecitationRecognition`;
UI `NoorUI`; Core `Localization`). Arabican imports `NoorUI` and `Localization`, so it is tested, built and released too;
it imports none of the recitation or search modules.

## Context

Roadmap §6 V1: "Search tab mic button, top-k ayah candidates with context, disambiguation, cancel; no recording kept.
Offers the model download (84 MB, D7) first." V0 finished the engine, the developer lab and the model download.

## Decisions

- **Entry point: a mic bar button on the Search tab** (`SearchViewController`), beside the search field, opening a
  medium/large sheet "Search by Recitation". Rejected: a row in the empty-state list (pushed down by recents) and the
  search bar's bookmark-button slot (UIKit's dictation mic could appear near it and confuse the two).
- **Listening starts as soon as the sheet opens** when the model is installed: tapping the mic is the request to listen.
  After a download the sheet waits on a Recite button (the person may have looked away during 84 MB).
- **Hands-free stop: `EndOfRecitationDetector`** (Domain, pure). Polls the microphone's recent peak every 200 ms; speech
  is a level at least 3× the room's noise floor (the quietest window) and above −40 dBFS; after speech, a 2 s pause in the
  lowest 20% of the noise-to-loudest range ends the recitation; nothing but room noise for 8 s gives "Nothing Heard";
  30 s is the limit. "Search Now" stops by hand. The first version (quiet = below 10% of the loudest, speech = above
  −40 dBFS) never stopped in the simulator, whose Mac microphone hears room noise of 0.03–0.10 (logged levels, Validation):
  both thresholds now measure from the room.
- **Trust gate decides the wording, not whether to answer:** a confident match shows "Best Match" then "Other
  Possibilities"; an unconfident one shows every candidate under "Is It One of These?" with "Not sure which verse you
  recited". Candidates are offered only when `VerseIdentification.isWorthOffering` (trusted, or at least
  `VerseMatcher.minimumTrustedLetters` letters): silence produced five unrelated unconfident verses in the first test run.
- **Runs starting at the same verse are offered once** (the matcher ranks 1:2 and 1:2–3 separately; both open 1:2 and
  showed the same text in the simulator).
- **Candidates are re-expressed in the reader's edition** (`ReadingPreferences.shared.reading.quran`): the matcher indexes
  Hafs 1405, navigation needs the edition shown; all Hafs editions number ayahs alike.
- **One loader for both screens:** `RecitationEngineLoader` (Domain) owns store, downloader and verse text and returns a
  ready `RecitationRecognizer`; the lab now uses it, so the load and download logic exists once. The model is loaded when a
  sheet opens and released when it closes (it takes hundreds of MB), not cached app-wide.
- **Download progress always ends at 1:** `RecitationModelDownloader` reports 1 after the stream ends, because a download
  that finished before the progress loop subscribed delivered no values (a `RecitationModelDownloaderTests` failure seen
  once in this session, 3/3 passes alone; the test now asserts the final 1).
- **No recording kept:** samples stay in memory until recognized (`RecitationMicrophone` as in the lab); the sheet's
  footnote says "Recognized on this device. Nothing is saved or sent." The first copy said "Nothing is recorded", which is
  false (the audio is recorded into memory), so it was changed.
- **Analytics:** opening a result logs `openingQuran(from: .voiceSearch)` (a new `Screen` case); no transcript or verse
  leaves the device (`LoggingAnalyticsLibrary` only logs locally anyway).
- **Strings:** 30 `voice_search.*` keys in all 16 catalogs, agent translations (native review UNVERIFIED). The size uses
  the existing Android `download_amount_in_megabytes` ("%@ MB") with `NumberFormatter.shared`; the download percentage a
  percent formatter on `Locale.fixedCurrentLocaleNumbers`.
- **SF Symbols:** `NoorSystemImage.voiceSearch` (`mic`), `.listening` (`mic.fill`), `.heardNothing` (`mic.slash`).

## Trade-offs

- **Complexity added:** `VoiceSearchViewModel` (~275 lines), `VoiceSearchView` (~220), `EndOfRecitationDetector` (~90),
  `RecitationEngineLoader` (~60), `RecitationMicrophone.recentPeak` (+12), `VerseIdentification.letterCount` /
  `isWorthOffering` (+12), 30 strings × 16 catalogs, 3 symbols. No new dependency, permission or entitlement (the
  microphone usage string shipped with V0 (c)). New failure modes: the pause detector stopping early in a noisy room
  (Search Now and Recite again cover it) or late (30 s limit).
- **Who benefits / how often:** anyone who hears a verse and wants to find it, or recites from memory and wants its place;
  likely occasional (UNVERIFIED, no analytics). The 84 MB download is opt-in at first use.
- **Rejected cheaper options:** a plain record/stop button without pause detection (two taps and a timer to watch while
  reciting); caching the loaded model app-wide (fast second open, but hundreds of MB held for a rarely used screen);
  showing only the confident answer (the unsure case is where a list helps most).
- **Ongoing cost:** 30 strings to keep translated; thresholds that may need tuning from device use; memory while the sheet
  is open (~852 MB footprint on the simulator during recognition, phone UNVERIFIED, owner checklist item 23).

## Changes

- `Domain/RecitationRecognition/Sources/`: `RecitationEngineLoader.swift` (new), `EndOfRecitationDetector.swift` (new),
  `RecitationMicrophone.recentPeak(seconds:)`, `RecitationModelStore.defaultDirectory`, `RecitationVerseText.text(of:)`,
  `RecitationModelDownloader.archive` public and final progress 1, `VerseIdentification.letterCount`/`isWorthOffering`.
- `Features/SearchFeature/Sources/`: `VoiceSearchViewModel.swift`, `VoiceSearchView.swift` (new); `SearchViewController`
  mic item and sheet; `SearchBuilder` wiring; `SearchViewModel.selectRecitedVerse(_:)`.
- `Features/RecitationLabFeature/Sources/`: view model and builder use `RecitationEngineLoader`.
- `Features/FeaturesSupport/Sources/Analytics.Screen.swift`: `.voiceSearch`.
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: three voice search cases.
- `Core/Localization/Sources/Resources/*/Localizable.strings`: `voice_search.*` (16 catalogs).
- `Package.swift`: `RecitationRecognition` adds `QuranText`; `SearchFeature` adds `RecitationRecognition` (and test deps).
- Docs: roadmap progress, roadmap §5/§6, feature-cost-register, trail index.
- Platforms: iPhone and iPad (one universal target); the Search screen stays portrait-only on iPhone as before.

## Tests

- `VoiceSearchViewModelTests` (5, new; 4 use the real model and skip without `make recitation-model`): no model → offers
  the 84,288,886-byte download without listening; Husary 112:1 → trusted first candidate in the reader's edition (Hafs
  1440), with its Arabic text, ids in order, each verse once; Ghamadi 2:255 → selecting opens 2:255; Alafasy 1:2 → 1:2
  first and no repeated first verse; 3 s of silence → no match.
- `EndOfRecitationDetectorTests` (7, new): pause after speech ends at 2 s; breaths of 1.4 s keep listening; loud room
  under loud speech counts as quiet; quiet measured from the room's noise (simulator-like levels); a noisy room alone is not
  speech; silence gives up at 8 s; the time limit.
- `RecitationEngineLoaderTests` (4, new), `VerseMatcherTests.testOnlyTrustedOrLongEnoughTranscriptsAreWorthOffering`
  (new), `RecitationModelDownloaderTests` (final progress 1), `RecitationLabViewModelTests` (new initializer).
- Regression evidence: the silence test failed before `isWorthOffering` (five unconfident candidates); the dedupe
  assertion would fail on the 1:2 / 1:2–3 pair seen in the simulator (reasoned from the screenshot, not run before the
  fix); `testQuietIsMeasuredFromTheRoomsNoise` and `testANoisyRoomAloneIsNotSpeech` fail with the first thresholds
  (reasoned from the arithmetic: 0.01 noise is not below 10% of 0.04, and 0.03 noise is above the 0.01 floor).

## Validation

- **Verified:**
  - `make format-lint`: `0/1222 files require formatting`.
  - Focused: `make test-no-sync TARGET=SearchFeatureTests`: 6 passed; `TARGET=RecitationLabFeatureTests`: 2 passed;
    `TARGET=LocalizationTests`: 53 passed; `RecitationRecognitionTests/EndOfRecitationDetectorTests`: 7 passed;
    `TARGET=RecitationRecognitionTests` (before the detector's last change): 66 run, 1 failure in
    `RecitationModelDownloaderTests` (the progress race, fixed above; 3/3 passes alone before the fix).
  - `make test-no-sync`: 1,644 passed, 0 failed, 0 skipped; then `make test-sync`: 2,123 passed, 0 failed, 0 skipped; then
    `make test-arabican`: 117 passed, 0 failed (xcresult summaries; one after the other; the model-backed tests ran with
    `.cache/recitation-model` present). `make test-tools`: every tool test passed (`22 passed, 0 failed` for
    `recitation-model.test.sh`).
  - Simulator (iPhone 18 Pro Max, light): Search tab shows the mic button; the sheet prepares, listens, and with
    Alafasy 1:2 played through the Mac speakers offered 1:2 and 37:182 under "Is It One of These?"; with Husary 112:1 it
    stopped on its own after the pause (logged levels: room 0.02–0.10, recitation peaks to 0.11; decision `finished`) and
    showed "Best Match" Al-Ikhlāṣ 112:1; tapping it closed the sheet and opened the page at 112:1 with the ayah
    highlighted. Dark mode at the XXXL text size with the model moved aside: "Recognize Your Recitation" with "Download
    (84 MB)". The model was put back afterwards.
  - `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: `Build Succeeded` (Package.resolved
    restored after the sync build).
- **Not verified:**
  - A phone: microphone levels close to the mouth, the pause detector in a quiet and a noisy room, memory, latency,
    the download over cellular (owner checklist).
  - The download button's whole flow in this sheet (the same `RecitationModelDownloader` path was verified in the lab,
    V0 model-download trail); VoiceOver order in the sheet; iPad sheet sizing; the "Nothing Heard" and microphone-denied
    alerts on screen (reached only through the code paths and tests).
  - Native review of the 15 translated catalogs.

## Release

- **Commit:** `c5c8815b` (feat(search): offline voice search by recitation (V1)); roadmap order `19f2768f`.
- **Pushed:** origin/main at `c5c8815b`
- **TestFlight:** Quran build 1011 (1.20.3): `Uploaded Quran iOS 1.20.3 (1011) for commit c5c8815bbc98638075f8b638d8697c9319e0efbf to App Store Connect app MemQuran.`
  Arabican build 1011 (0.1.0): `Uploaded Arabican iOS 0.1.0 (1011) for commit c5c8815bbc98638075f8b638d8697c9319e0efbf to App Store Connect app Arabican.`
  (NoorUI and Localization changed; Arabican imports both.)
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Tune `EndOfRecitationDetector` from the owner's device use (quiet room, car, mosque).
- A Settings row to delete the 125 MB model (carried from the D7 trail).
- V2a live follow in the reader reuses `RecitationEngineLoader` and the detector's level reading.
