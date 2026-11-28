# Quran V2b: Tarteel-matched glyph highlighting, compact Practice dock, Mushaf default, and dictation reliability

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** feature | fix | ux
- **Status:** verified
- **Related:** [2026-11-27-live-practice-mistake-detection-and-latency.md](2026-11-27-live-practice-mistake-detection-and-latency.md) (`PracticeRecitationTracker` live mistakes & 300 ms streaming),
  [2026-11-27-v2b-live-practice-reveal.md](2026-11-27-v2b-live-practice-reveal.md) (live Practice reveal),
  [2026-11-27-quran-h2c-reader-practice.md](2026-11-27-quran-h2c-reader-practice.md) (translation and line-page practice)

App: **Quran** (with shared `QuranAnnotations` and `NoorUI` changes imported by **Arabican**, so Arabican is tested, built, and released too per AGENTS.md rule 5).

## Context

After testing V2b live Practice against the Tarteel screen recording (`/Users/foyzur/git/arabic/Screen Recording 2026-11-27 at 12.55.12 PM.mov`, Surah Ash-Shura Page 483, 42:1–10), the owner reported five UX and reliability issues:

1. **Highlighting & colors didn't match Tarteel:** Revealed words had no green live moving cursor; mistakes painted dull background boxes over black ink instead of recoloring the glyphs themselves; hidden lines used dark gray rounded boxes that also hid the ayah-end rosette markers (`١، ٢، ٣…`).
2. **Dictation sometimes stopped working (especially when playing audio from a MacBook into the iPhone mic):** Reproducing and benchmarking the exact pipeline uncovered five concrete root causes:
   - `AVAudioSession.setCategory(.record, mode: .measurement)` (`Domain/RecitationRecognition/Sources/RecitationMicrophone.swift:59`) disabled iOS hardware microphone AGC, attenuating quiet human voice and external speaker playback by ~20–30 dB. Benchmarking `TilawiFastConformerInt8` on the extracted 16 kHz Tarteel audio confirmed `-30 dB` (`0.03x`) dropped `حم` and `عسق` completely; peak gain normalization (`RecitationAudio.normalizeForRecognition`) restored the exact full transcript.
   - `PracticeRecitationTracker` (`Domain/RecitationRecognition/Sources/PracticeRecitationTracker.swift:202–207`) only looked ahead one ayah (`currentVerseIndex + 1`). On Page 483 (`42:1 حمٓ` + `42:2 عٓسٓقٓ`), both are 1-word ayahs, so `upperBound` was only 2 words (`[حمٓ, عٓسٓقٓ]`): missing `حمٓ` on mic startup left `42:3` completely outside the search window, freezing dictation at 0 words forever.
   - `PracticeRecitationTracker` (`PracticeRecitationTracker.swift:330`) had a hard `matchedEnd <= anchor + 8` cap while still resetting `misses = 0`, permanently deadlocking if a reciter got 9–15 words ahead after a warm-up or brief stutter.
   - `RecitationMicrophone` had no `AVAudioEngineConfigurationChange` or `AVAudioSession.interruptionNotification` recovery: any iOS route change or notification chime silently stopped `AVAudioEngine`, leaving the streaming loop reading a frozen buffer forever.
   - `SpeechLevel` alone drove both `lastSpeech` and mistake detection (`isSpeaking`); steady laptop-speaker playback with < 3× dynamic range tripped `isSpeaking == false`, disabling mistake detection and triggering `stoppedAfterSilence`.
3. **Gigantic bottom toolbar:** `HifzPracticeView` rendered a 5-row vertical glass card covering the bottom quarter of the Mushaf page.
4. **Each ayah started on a separate line with a different font:** When `QuranContentStatePreferences.shared.quranMode` was `.translation` (set persistently by Search or More Menu), Practice stayed in `ContentTranslationView` (one `List` row per ayah in `UthmanicHafs` text font, with gaps between ayahs) instead of the contiguous 15-line Madani Mushaf (`ContentImageView`), and `ContentTranslationViewModel` also returned early for `partialVerse` without active/mistake highlights.
5. **No live active word cursor wired:** `PracticeRecitationTracker.Update.currentWord` was computed but ignored by `HifzPracticeViewModel` and `PracticeMask`.

## Decisions

- **Exact Tarteel palette sampled directly from the screen recording (`UI/NoorUI/Sources/Colors/Color+extension.swift`):**
  - Active moving word glyphs: `#1AC962` light / `#27D970` dark (`Color.practiceActiveWord`, `static let`).
  - Mistake word glyphs, dotted underline, and red dock badges: `#ED4C4D` light / `#FF6364` dark (`Color.practiceMistakeWord`, `static let`), with soft coral wash (`Color.practiceMistakeGlow`, 13% light / 22% dark).
  - Hidden baseline rule: `#DCDBDC` light / white 18% dark (`Color.practiceHiddenBaseline`).
  - Circular green mic/stop button gradient: `#63DE84` → `#55DE98` (`Color.practiceMicStart`, `Color.practiceMicEnd`).
- **Direct calligraphy glyph recoloring on Mushaf PNGs (`AdaptiveImageScrollView.swift`):** Verified `hafs_1405` page PNGs are pure transparent background (`alpha == 0`) with opaque calligraphy ink (`alpha == 255`). Masking colored word rectangles with `Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)` recolors the exact Arabic strokes and diacritics to Tarteel green/red in both Light and Dark themes with zero extra bitmap assets.
- **Minimal baseline mask + visible ayah-end rosettes (`QuranPracticeMask.swift`, `ContentImageViewModel.swift`):** Replaced filled gray boxes with solid `themeColors.background` plus a crisp 1 pt horizontal baseline rule (1.5 pt red baseline when a live stumble is pending on the next hidden word). Kept each verse's final ayah-end rosette glyph visible when `imageWords` proves it lies strictly after the last mapped canonical word glyph, matching Tarteel's hidden Mushaf layout (`١، ٢، ٣…`).
- **Default Practice to contiguous Madani Mushaf (`.arabic`) with a 1-tap toggle (`QuranInteractor.swift`, `HifzPracticeView.swift`):** Entering Practice switches `quranMode` to `.arabic` (restoring the user's prior mode when Practice ends unless they explicitly toggle during Practice) and exposes a compact book icon button in the Practice dock to switch between Mushaf and Translation at any time. Fixed `ContentTranslationViewModel` so `partialVerse` also highlights active green and mistake red tokens when Translation mode is used.
- **Compact Tarteel-style bottom dock (`HifzPracticeView.swift`):** Replaced the 5-row card during `.reciting` with a floating 2-tier layout: compact top micro-status chips (red/neutral mistakes badge, `sura:ayah | accuracy%`, live `mm:ss` timer with red dot, inline hint chip) over a horizontally scrollable row of small circular icon buttons (mode toggle, grouped `< | <<` reveal-word / reveal-ayah pill, hint, listen, options, close) beside the circular green mic/stop hero button.
- **Dictation reliability fixes (`RecitationAudio.swift`, `RecitationMicrophone.swift`, `PracticeRecitationTracker.swift`, `HifzPracticeViewModel.swift`, `RecitationFollowViewModel.swift`):**
  - Switched `AVAudioSession` from `.measurement` to `.default` mode and added `RecitationAudio.normalizeForRecognition` (amplifies quiet speech with peak ≥ `0.004` up to `0.5`, capped at `20x`, leaving room silence untouched) after `SpeechLevel` checks.
  - Added `AVAudioEngineConfigurationChange` and `AVAudioSession.interruptionNotification` auto-recovery plus monotonic `sampleGeneration` tracking to skip empty (< 0.2 s) or unchanged buffers.
  - Extended `PracticeRecitationTracker` lookahead across consecutive 1–2 word ayahs (such as `42:1` + `42:2`), allowed bridging consecutive 1-word opening ayahs on ≥ 2 clean matches in the next ayah, removed the `anchor + 8` freeze cap in favor of the existing `upperBound` (`anchor + 15`), and exposed `pendingMistakeWord`.
  - Updated live speaking/activity checks so confident recognized words keep `lastSpeech` alive and mistake detection active even under low-dynamic-range speaker playback.

## Trade-offs

- **Complexity added:** ~870 net lines across 27 files (`RecitationRecognition`, `QuranAnnotations`, `NoorUI`, `QuranImageFeature`, `QuranTranslationFeature`, `QuranViewFeature`, `HifzPracticeFeature`, `RecitationFollowFeature`, and their test suites). Zero new dependencies, zero new permissions, zero new localization keys (reused `menu.arabic`, `menu.translation`, and existing `hifz_practice.*` keys), zero Core Data schema changes. Added one `NoorSystemImage` case (`.revealAyah = "chevron.left.2"`).
- **Who benefits / how often:** Every user practicing Hifz with live recitation (core Hifz experience); also benefits live-follow users via mic recovery and low-volume normalization (usage UNVERIFIED).
- **Rejected cheaper options:** Keeping background-only highlight boxes (didn't match Tarteel's glyph coloring); leaving `quranMode` untouched on Practice entry (left users confused in verse-by-verse translation layout with gaps between ayahs); keeping `.measurement` audio mode without normalization (empirically dropped `42:1–2` at `-30 dB`).
- **Ongoing cost:** SwiftUI `.mask { Image(uiImage: image) }` composites only when `wordGlyphTints` is non-empty (only during active Practice); `Color` palette properties are `static let` so SwiftUI diffing incurs zero per-frame closure allocations. Physical iPhone microphone acoustics, 10-minute battery/thermals, and VoiceOver/Dynamic Type on hardware remain UNVERIFIED.

## Changes

- `Domain/RecitationRecognition/Sources/RecitationAudio.swift`: `normalizeForRecognition(_:minPeak:targetPeak:maxGain:)`.
- `Domain/RecitationRecognition/Sources/RecitationMicrophone.swift`: `.default` audio session mode, `sampleGeneration`, `AVAudioEngineConfigurationChange` & `AVAudioSession.interruptionNotification` tap/engine recovery.
- `Domain/RecitationRecognition/Sources/PracticeRecitationTracker.swift`: consecutive short-ayah lookahead & 1-word opening bridge, removed `anchor + 8` deadlock cap, `Update.pendingMistakeWord`.
- `Model/QuranAnnotations/Sources/PracticeMask.swift`: `activeWord` and `pendingMistakeWord` properties (with `restricted(to:)`).
- `UI/NoorUI/Sources/Colors/Color+extension.swift`: Tarteel-matched `static let` practice palette (`practiceActiveWord`, `practiceMistakeWord`, `practiceMistakeGlow`, `practiceHiddenBaseline`, `practiceMicStart`, `practiceMicEnd`).
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: `.revealAyah` (`chevron.left.2`).
- `UI/NoorUI/Sources/Components/QuranPracticeMask.swift`: minimal background cover + 1 pt `#DCDBDC` baseline rule + red `pendingMistakeRects` baseline.
- `UI/NoorUI/Sources/Features/Quran/ImageDecorations.swift`, `ImageDecorationsLayout.swift`, `ImageDecorationsView.swift`, `AdaptiveImageScrollView.swift`: `WordGlyphTint` ink-masked overlay, `dottedUnderline` for live mistake highlights, `pendingMistakeMaskWords`.
- `UI/NoorUI/Sources/Features/Quran/QuranArabicText.swift`: `practiceActiveTokens` (green foreground) and `practiceMistakeTokens` (red foreground + coral wash).
- `Features/QuranImageFeature/Sources/ContentImageViewModel.swift`: ayah-end rosette preservation in `maskedImageWords`, `practiceGlyphTints`, `practicePendingMistakeMaskWords`, dotted mistake underlines, `recitedScrollWord` following `activeWord`.
- `Features/QuranTranslationFeature/Sources/ContentTranslationViewModel.swift`, `TranslationItem.swift`, `TranslationItem+View.swift`: active/mistake token highlighting on both revealed and `partialVerse` rows.
- `Features/HifzPracticeFeature/Sources/HifzPracticeViewModel.swift`, `HifzPracticeBuilder.swift`, `HifzPracticeView.swift`: wired `activeWord`, `pendingMistakeWord`, `liveRecitationStartedAt`, `toggleReaderMode`, audio normalization, stale-buffer skip, confident-word speech fallback, and compact Tarteel-style bottom dock.
- `Features/QuranViewFeature/Sources/QuranInteractor.swift`: default Practice to `.arabic` Mushaf mode (restoring prior mode on exit unless toggled), wired `togglePracticeReaderMode`.
- `Features/RecitationFollowFeature/Sources/RecitationFollowViewModel.swift`: audio normalization, `sampleGeneration` / min-length guard, confident-word speech fallback.
- Platform-neutral (iPhone and iPad); no `#if`.

## Tests

- `Domain/RecitationRecognition/Tests/PracticeRecitationTrackerTests.swift` (+4 tests): `testBridgesConsecutiveOneWordHurufMuqattaatWhenOpeningMissed`, `testRecoversWhenReciterAdvancesMoreThanEightWordsInOneWindow` (would deadlock under the old `anchor + 8` cap), `testPendingMistakeWordReportsNextHiddenWordOnStumble`, `testNormalizeForRecognitionAmplifiesQuietSpeechWithoutBoostingRoomSilence`.
- `Features/QuranImageFeature/Tests/ContentImageHeatmapTests.swift` (+1 test): `testPracticeGlyphTintsActiveWordGreenMistakeWordRedAndSkipsHiddenWords` + dotted underline check.
- `Features/QuranImageFeature/Tests/ContentRecitedWordTests.swift` (updated): asserts ayah-end rosette stays visible while all word glyphs are masked.
- `UI/NoorUI/Tests/ImageDecorationsLayoutTests.swift` (+1 test): `testGlyphTintsAndPendingMistakeMasksScaleCorrectly`.
- `Features/QuranTranslationFeature/Tests/ContentTranslationWordByWordTests.swift` (+1 test): `test_practicePartialVerseHighlightsActiveWordAndRevealedMistakes`.
- `Features/HifzPracticeFeature/Tests/HifzPracticeViewModelTests.swift` (+1 real Core ML test): `testLiveRecitationHandlesLowVolumeSpeakerAudioAndTracksMovingActiveWord` (`-30 dB` attenuated audio completes 112:1–4 and updates `activeWord`).

## Validation

- **Verified:**
  - `make format-lint`: `0/1316 files require formatting, 71 files skipped.`
  - Full sequential suites on iPhone 18 Pro Max simulator (`iOS 27.2`):
    - `make test-no-sync`: `passedTests: 1859, failedTests: 0, skippedTests: 0` (`Run-QuranEngine-Package-2026.11.27_23-05-23--0800.xcresult`).
    - `make test-sync`: `passedTests: 2340, failedTests: 0, skippedTests: 0` (`Run-QuranEngine-Package-2026.11.27_23-11-59--0800.xcresult`).
    - `make test-arabican`: `passedTests: 117, failedTests: 0, skippedTests: 0` (`Run-ArabicLearning-Package-2026.11.27_23-19-56--0800.xcresult`).
  - Final post-scrollview-adjustment check on `HifzPracticeFeatureTests` + `make build-example-no-sync` + `make build-example-sync` + `make build-arabican`: all `Build Succeeded` / `Test Succeeded`.
  - `bash Tools/package-pins.test.sh`: `5 passed, 0 failed`.
  - Direct Core ML acoustic benchmark on extracted Tarteel 16 kHz audio (`42:1–4`): raw `-30 dB` (`0.03x`) dropped `حم` and `عسق`; `RecitationAudio.normalizeForRecognition` restored `حم عق كذلك يوحي الك والذين من قبلك الله العزيز الحكيم له ما في السموات`.
- **Not verified:**
  - Live visual inspection on physical iPhone/iPad hardware in Light/Dark, portrait/landscape, compact iPhone / iPad split-view (one-simulator rule; both top chip strip and bottom icon row sit in horizontal `ScrollView`s with `@ScaledMetric` sizing and no fixed horizontal overflow).
  - Real iPhone microphone + MacBook speaker room acoustics, Bluetooth/AirPods interruption recovery on hardware, VoiceOver rotor traversal, and 10-minute battery/thermal impact.

## Release

- **Commit:** pending
- **Pushed:** pending
- **TestFlight:** pending (attempting `make release-testflight-quran` and `make release-testflight-arabican` after push)
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Verify live on physical iPhone with both human recitation and MacBook audio playback; tune `normalizeForRecognition` `minPeak`/`maxGain` if real-room noise floors vary.
- Optional: tap a red highlighted word directly on the Mushaf during Practice to open its Expected vs Recited detail popover.
- Optional: add a subtle pulsing ring animation on the green microphone hero button proportional to live microphone amplitude (`microphone.recentPeak()`).
