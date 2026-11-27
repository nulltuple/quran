# C2 (Quran): tap-to-hear a word and a word study entry from the Mushaf pointer

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped (C2 slice c2; C2 is complete)
- **Related:** [C2 occurrences](2026-11-26-c2-word-occurrences.md) (slice c1, whose Follow-ups this ships),
  [C2 word study sheet](2026-11-26-c2-word-study-sheet.md) (slices a, b), [roadmap v2](2026-11-26-quran-roadmap-v2.md) §6 C2

App: **Quran**. Shared QuranEngine modules touched, which Arabican also compiles: `Localization` (5 keys in 16
catalogs), `NoorUI` (one `NoorSystemImage` case), `UIx` (`ByPassTouchesView.secondaryCatchTouchesView`), so both
apps' suites and builds ran and both are released. The rest is in Quran-only modules (`QuranAudioKit`,
`WordTextService`, `WordStudyFeature`, `WordPointerFeature`, `AudioBannerFeature`, `QuranViewFeature`).

## Context

The owner asked to "continue the Quran roadmap ... starting with the first item under Next steps", which was C2
slice c2 (`Documentation/agents/quran-roadmap-progress.md`, Next steps 1): tap-to-hear in the word study sheet from
the Afasy word timings, "labeled as an excerpt of connected recitation, without disturbing or replacing the main
player's session"; a word study entry from the Mushaf page (design it first); optionally the 45% landing of a
navigated verse. Roadmap §6 C2: "Tap-to-hear a word: plays the Afasy recording between the word's timings".

Evidence read: word timings come from `GRDBAyahTimingPersistence.getWordTimings(for:)`
(`Data/AudioTimingPersistence/Sources/GRDBAyahTimingPersistence.swift:60`) through
`ReciterTimingRetriever.wordTimings(for:suras:)`; the word-timing reciter is id 1001 in
`Example/QuranEngineApp/Resources/reciters.plist` (bundled `qul_afasy.db`, sura MP3s from
`https://audio-cdn.tarteel.ai/quran/surah/alafasy/murattal/mp3/`). `qul_afasy.db` (app copy) has 79,450 word timing
rows over 114 suras; the test copy has suras 1, 2, 112–114. Repeated words exist (2:14 recites words 7–11 twice) and
some words have no timing (2:27 word 18). The pointer's popover (`Popover_OC`) is added to the pointer's
`ByPassTouchesView`, which only accepts touches on the pointer itself, and its table has `allowsSelection = NO`.

## Decisions

- **Where the audio comes from:** the downloaded sura file when it exists (`Reciter.localURL(sura:)`), otherwise the
  remote sura URL, streamed. Decision for "offline only if downloaded": streaming is the fallback, and the sheet
  says so ("Streams from the internet until this surah's audio is downloaded."); a failed stream shows "The recording
  could not be played. Check your internet connection." and the row can try again. Rejected: hiding the row when not
  downloaded (most readers have not downloaded the 1001 reciter, so the feature would be invisible).
- **A separate `AVPlayer` (`WordRecitationPlayer`)** seeks with zero tolerance to the word's start and pauses at a
  boundary observer on its end. It does not touch the main `QueuePlayer`'s queue, Now Playing, remote commands or the
  audio session (the reader's `QueuePlayer` already set `.playback`). No precise-timing asset key, like the main
  player (`Domain/QueuePlayer/Sources/PlayerAsset.swift:17`): the word timings are read against the same estimate.
- **The main recitation is paused, not replaced,** before a word plays (`AudioBannerViewModel.pauseIfPlaying()`),
  so the two never sound together; the listener resumes it from the banner. Assumption, not asked.
- **Which word timing:** the first recitation of the word (a reciter who goes back repeats words); a word without its
  own timing has no Hear row. **Which reciter:** the first with a bundled timing database
  (`WordRecitationRetriever.wordTimingReciter(in:)`), today only 1001.
- **Label:** "Recited by %@: cut from the recitation of the whole ayah, so it can blend into the words around it."
  The reciter name is its localized name ("Mishary Al-Afasy (word by word)").
- **One player per sheet:** a study that disappears (another pushed over it, or the sheet closed) stops its word.
- **Mushaf entry, designed as "release to keep":** dragging the pointer works as before; when the drag ends over a
  word, its popover stays for 4 s with the word study symbol and the word stays highlighted; tapping it opens the word
  study sheet for that word (canonical numbering, through the new `WordTextService.pointedWord(atImageGlyph:reading:)`).
  Any new drag, hiding the pointer, or the timeout removes it. Rejected: opening the sheet on every release (readers
  drag to read meanings; a sheet each time would be intrusive); an ayah-menu row (the menu knows the ayah, not the
  word, so it would need a word picker).
- **How the popover takes the tap:** a transparent `UIButton` over the popover, made touchable through a new
  `ByPassTouchesView.secondaryCatchTouchesView`. A first attempt with a tap recognizer on the popover lost to the
  reader's own tap recognizer (it toggled the bars); a control's tap takes precedence over an ancestor's tap
  recognizer. The release spring animation now allows interaction, so a quick tap is not dropped (seen in the
  simulator before that change).
- **Not done (optional item):** the 45% landing of a navigated verse in the translation view stays a follow-up.

## Trade-offs

- **Complexity added:** ~600 lines of source and ~330 of tests. New: `WordRecitationRetriever` 81 and
  `WordRecitationPlayer` 124 (`Domain/QuranAudioKit/Sources/WordRecitation/`); `WordStudyViewModel` +66,
  `WordStudyView` +68, `WordStudyBuilder` +23; `WordPointerViewController` +68, `WordPointerViewModel` +40;
  `WordTextService` +19; `AudioBannerViewModel` +10; `ByPassTouchesView` +8; 5 localization keys × 16 catalogs; one
  SF Symbol case. `WordStudyFeature` now depends on `QuranAudioKit` and `ReciterService`, `WordPointerFeature` on
  `Localization`. No new package, permission, entitlement, persisted state or background work. New failure modes: a
  stream that cannot load (shown, retryable); a second `AVPlayer` alive only while a word plays.
- **Who benefits / how often:** readers studying a word's sound; one tap in a sheet that is itself a minority path,
  so likely rarely used (UNVERIFIED, no analytics). The Mushaf entry serves pointer users only; the pointer is already
  noted as niche in the cost register.
- **Rejected cheaper options:** routing the excerpt through the main `QuranAudioPlayer` (it would replace the
  listener's queue and Now Playing); downloading the whole sura before playing a word (up to ~100 MB for one word);
  bundling per-word clips (77,432 files, large).
- **Ongoing cost:** small; the pointer's tap path depends on `Popover_OC` laying out its view in the pointer's
  container (checked in its source, not a public contract).

## Changes

- `Domain/QuranAudioKit/Sources/WordRecitation/WordRecitationRetriever.swift` (new): `WordRecitation`,
  `WordRecitationRetriever` (reciter choice, first timing, local or remote URL).
- `Domain/QuranAudioKit/Sources/WordRecitation/WordRecitationPlayer.swift` (new): plays one excerpt, `Outcome`.
- `Domain/WordTextService/Sources/WordTextService.swift`: `PointedWord`, `pointedWord(atImageGlyph:reading:)`;
  `textForWord` now delegates to it.
- `Features/WordStudyFeature/Sources/WordStudyViewModel.swift`, `WordStudyView.swift`, `WordStudyBuilder.swift`:
  `Hearing` state, `toggleHearing()`, `didDisappear()`, the Hear section; `build(word:readerFollower:pauseRecitation:)`.
- `Features/WordPointerFeature/Sources/WordPointerViewModel.swift`: `viewPanEnded()`, `openReleasedWordStudy()`,
  `WordPointerListener.presentWordStudy(_:)` (the interactor's existing method satisfies it).
- `Features/WordPointerFeature/Sources/WordPointerViewController.swift`: released-word popover, button, timeout.
- `Features/AudioBannerFeature/Sources/AudioBannerViewModel.swift`: `pauseIfPlaying()`.
- `Features/QuranViewFeature/Sources/QuranInteractor.swift`: passes `pauseIfPlaying` to the word study builder.
- `UI/UIx/Sources/UIKit/Views/ByPassTouchesView.swift`: `secondaryCatchTouchesView`.
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: `hearWord` (`speaker.wave.2`).
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: `word_study.hear`, `.stop_hearing`,
  `.hear_excerpt`, `.hear_streams`, `.hear_failed` (agent translations in 15 languages, native review UNVERIFIED).
- `Package.swift`: the dependencies above.
- Platforms: iPhone and iPad (one universal target); no platform-specific code.

## Tests

- `QuranAudioKitTests/WordRecitationRetrieverTests` (6): 1:2 word 1 is 5.684–7.230 s of the streamed sura when not
  downloaded; a downloaded sura plays from its file; a repeated word (2:14 word 7) is its first recitation; a word
  without its own timing (2:27 word 18) has none; no reciter, none; the reciter choice.
- `WordStudyFeatureTests/WordStudyHearingTests` (6), with a real `WordRecitationPlayer` on generated silent local
  files: a word with a timing can be heard; without a timing or without a player it cannot; hearing pauses the
  recitation once and stops at the excerpt's end (0.8 s of a 2 s file, under 1.9 s); a missing file fails and can be
  tried again; leaving the study stops the word.
- `WordPointerFeatureTests/WordPointerViewModelTests` (+5): releasing over a word keeps it and a tap opens its study;
  the study opens the canonical word (2:2 glyph 6 → word 5); releasing over no word, or before the last lookup
  finished, keeps nothing; an unhighlighted word cannot be opened.
- `WordTextServiceTests` (+2): the pointed word is numbered as in the ayah's text; a mark glyph is no pointed word.
- `UIxTests/ByPassTouchesViewTests` (2): only the catch view takes touches; a secondary catch view only while it is a
  subview.
- `AudioBannerViewModel.pauseIfPlaying()` has no direct test: the banner's playing state is private and reaching it
  needs the queue player fake that lives in `QuranAudioKit`'s tests; the word study tests assert the closure is called.

## Validation

- **Verified:**
  - Focused: `make test-no-sync TARGET=WordStudyFeatureTests`: `Executed 26 tests, with 0 failures`;
    `TARGET=WordPointerFeatureTests`: `Executed 8 tests, with 0 failures`; `TARGET=WordTextServiceTests`:
    `Executed 40 tests, with 0 failures`; `TARGET=QuranAudioKitTests`: `Executed 72 tests, with 0 failures`.
  - Simulator (iPhone 18 Pro Max), no-sync build: translation view 1:1 ٱلرَّحْمَٰنِ → the sheet shows "Hear the word",
    the excerpt note and the streaming note; tapping it shows Stop with a spinner, then returns to ready with no error
    (streamed from the CDN). Mushaf Hafs 1405, page 50, pointer on: dragging over 3:2 and releasing keeps "the
    Sustainer of all that exists" with the word study symbol and the word highlighted; it disappears after 4 s; a tap
    on a kept ٱلْحَيُّ opened Word Study for "Āli-'Imrān, Ayah 2, word 6" (log: `WordPointer: open word study for
    3:2 word 6`), and Hear streamed it (`WordRecitationPlayer: playing 3:2 word 6, downloaded: false`).
  - Full suites after the last source change (xcresult summaries, run one after the other): `make test-no-sync`
    `Passed 1565/1565` (1,544 at C2 c1); `make test-sync` `Passed 2044/2044` (2,023); `make test-arabican`
    `Passed 117/117`; `make test-tools`: `46 passed, 0 failed`, `12 passed, 0 failed`, `31 passed, 0 failed`,
    `5 passed, 0 failed`.
  - `make format-lint`: `0/1183 files require formatting`. `make build-example-no-sync`, `make build-example-sync`,
    `make build-arabican`: `Build Succeeded` each.
- **Not verified:**
  - By ear: whether the excerpt starts and ends on the word (simulator audio was not listened to); the seek precision
    of a streamed MP3 without precise timing.
  - Pausing the main recitation before a word plays, in the app (unit-tested as a closure call only).
  - A downloaded sura playing offline in the app (unit-tested with a local file).
  - VoiceOver on the Hear row and the kept popover's button; Dark mode and large text on the new row; landscape;
    iPad split view (no iPad simulator allowed); the sync build in the simulator (compiled and tested only).

## Release

- **Commit:** `9047de22ce2879dad99754c31910f312630d4535`
- **Pushed:** origin/main at `9047de22` (`aeb1c872..9047de22  HEAD -> main`)
- **TestFlight:** Quran build 999 (1.20.3): `Uploaded Quran iOS 1.20.3 (999) for commit
  9047de22ce2879dad99754c31910f312630d4535 to App Store Connect app MemQuran.` Arabican build 999 (0.1.0): `Uploaded
  Arabican iOS 0.1.0 (999) for commit 9047de22ce2879dad99754c31910f312630d4535 to App Store Connect app Arabican.`
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Scroll a navigated verse to its anchor in the translation view (lands at ~45%, under a medium sheet).
- The reciter name in the excerpt note reads "Mishary Al-Afasy (word by word)"; a plain name would read better.
- C2 is complete; next is V0 (roadmap §6 V0).
