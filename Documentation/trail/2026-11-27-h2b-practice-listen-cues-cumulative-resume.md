# Quran H2 slice b: listen and repeat, mistaken words, cue levels, cumulative steps, resume after kill

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-27-h1-h2a-learning-store-and-practice.md](2026-11-27-h1-h2a-learning-store-and-practice.md)
  (slice a, whose Follow-ups this slice works through), roadmap §6 H2
  ([quran-prioritized-roadmap.md](../agents/quran-prioritized-roadmap.md))

## Context

App: **Quran**. Shared NoorUI (`NoorSystemImage` aliases) and Localization changed, so **Arabican** builds, tests and
ships too (it imports both). The owner asked to "continue the Quran roadmap" after H1 and H2 slice a. Roadmap §6 H2 slice b is
"listen-and-repeat over the existing audio pipeline (reference play, pause scaled to ayah length, repeat), cumulative
steps (A, B, A+B, C, A+B+C) as presets; session resume after kill". Slice a's trail also deferred to b: "mark a word as a
mistake (word-level evidence exists in the store, `VerseRecall.mistakenWords`); progressive masking levels". This change
builds all five on the image page; slice c (translation view, line pages, page turns) is still open.

## Decisions

- **Listen and repeat goes through the audio banner, not a second player.** `AudioBannerViewModel.listenAndRepeat(_:repetitions:)`
  plays the current ayah `verseRuns: .finite(3)`, `verseDelay: .full` (a pause as long as the ayah after each run, the
  existing `VerseDelay` multiplier), `listRuns: .finite(1)`, with the selected reciter, speed, download or streaming and
  error handling the banner already has. The person's audio repeat and delay preferences are not changed.
  `stopIfActive()` stops playing, paused or downloading audio. A second `QuranAudioPlayer` would fight the first over
  Now Playing and remote commands. The repetition count is a constant (`HifzPracticeViewModel.listenRepetitions = 3`):
  no setting until someone asks for one.
- **Playback end comes from `highlightReadingAyah(nil)`**, which the banner already sends when it stops. The interactor
  forwards it to `HifzPracticeViewModel.audioStopped()`. Starting playback first stops any earlier audio, which sends that
  same nil right away, so the view model calls `listen` *before* setting `isListening` (the order matters, and the comment
  says so).
- **Listening counts as help** (`assistance += 1`), so "Correct" after listening is recorded as `.hint`: hearing the ayah
  and then reciting it is not unaided recall.
- **Mistaken words are picked in the bar, not on the page.** Mistakes → the bar lists the checked ayah's words (the
  Uthmani units from `ExpectedWordsReader`, right to left, in the Quran font); taps toggle them (red, `isSelected` for
  VoiceOver); Done records the ayah as `.mistake` with those word numbers (possibly none). Page taps belong to the
  bar-toggling recognizer and the long press (slice a gotchas). The ayah is shown whole while grading, so listing its
  words reveals nothing. Words written joined form one choice and mark all their numbers.
- **Cue levels are deterministic, not random:** No Cues (default, slice a behavior), First Word of Each Ayah, Every Other
  Word (1st, 3rd, 5th …). The same page looks the same every session, which a hafiz expects; a seeded random sampler would
  need a seed to be stored and explained. `PracticeMask.cueWords` (text numbering) keeps them visible;
  `ContentImageViewModel.maskedImageWords` maps each through `imageWords`, as revealed words already were.
- **Cumulative steps:** `PracticePlan.steps` makes A, B, A+B, C, A+B+C …: 2n − 1 steps that recite 1 + (n − 1)(n + 4) / 2
  ayahs, so a 15-ayah page is 29 steps and 134 recitations. It suits a few new ayahs; nothing caps it (the person picks the
  range). Every ayah is still checked and graded one by one, so a cumulative session records several evidence records per
  ayah; `EvidenceReducer.grade` groups by ayah, so the session grade is unchanged in kind. While reciting, ayahs after the
  current one are hidden and earlier ones shown, in both orders (a review step hides the later ayahs again).
- **The order can change only before the first grade** (changing it starts over); the cue level any time. Both are kept in
  user defaults (`hifzPractice.order`, `hifzPractice.cueLevel`).
- **Resume after kill: a draft in user defaults, saved after every grade.** `PracticeStateStore` keeps `hifzPractice.draft`
  (JSON, `version: 1`: passage, order, position, start date, graded ayahs). Starting Practice on the **same passage** picks it
  up ("Picked up where you left off."); a draft of **another passage** is saved as its own session first, so no graded ayah
  is lost. A saved session clears it. The draft is device-local and transient, so it is not in backups and needs no Core
  Data migration; an unreadable or newer draft is ignored. Product assumption: resuming happens when the person opens
  Practice on that passage again, not automatically at launch (the reader reopens at the same page, so it is one long press).
- **Starting practice while one runs** now waits for the running one to save (and clear its draft) before the new one reads
  the draft (`QuranInteractor.practice`), so the same graded ayahs are never saved twice.
- No `#if os` or idiom checks; iPhone and iPad share every file.

## Trade-offs

- **Complexity added:** `Domain/MemorizationService`: `PracticePlan.swift` (~75 lines), `PracticeStateStore.swift` (~150).
  `HifzPracticeViewModel` +~230, `HifzPracticeView` +~110, `AudioBannerViewModel` +29, interactor +18, mask +10, image
  mapping +10, 3 symbol aliases. Tests: 2 new files (~200 lines), +~190 in 3 files. New persisted state: three user-defaults
  keys (a versioned JSON draft and two choices). No dependency, permission, entitlement or background work. New failure
  modes: a draft that cannot be saved is logged and practice goes on (only a kill would lose the ayahs since the last save);
  a reciter that cannot play leaves the Listen button in its stop state until tapped.
- **Who benefits / how often:** people memorizing. Listen and repeat and mistaken words are likely used every session by
  learners; cumulative order mostly when learning new ayahs; resume only after a kill or crash mid-session (rare, but a lost
  half-page session is exactly what makes people stop trusting a tool). Every Other Word is likely the least used level
  (UNVERIFIED).
- **Rejected cheaper options:** a dedicated player for practice (conflicts with the banner's Now Playing); storing the draft
  in Core Data (a `Quran 5` migration and backup code for transient state); tapping words on the page to mark mistakes
  (conflicts with the page's recognizers, no VoiceOver path); random masking (not reproducible).
- **Ongoing cost:** the draft's JSON field names are a persisted format (`testStoredFormatIsStable`); 14 more strings in 16
  catalogs (agent translations, native review UNVERIFIED); the banner's "Playing … Modify" toast also shows for listen and
  repeat (it is the banner's normal toast; Modify opens the audio options).

## Changes

- `Domain/MemorizationService/Sources/PracticePlan.swift` (new): `PracticeOrder`, `PracticeCueLevel`, `PracticeStep`,
  `PracticePlan.steps(for:order:)`.
- `Domain/MemorizationService/Sources/PracticeStateStore.swift` (new): `PracticeDraft`, `PracticeStateStore` (cue level,
  order, draft; `StoredDraft` version 1).
- `Model/QuranAnnotations/Sources/PracticeMask.swift`: `cueWords`, kept in `restricted(to:)`.
- `Features/QuranImageFeature/Sources/ContentImageViewModel.swift`: `maskedImageWords` leaves cue words' glyphs visible.
- `Features/HifzPracticeFeature/Sources/HifzPracticeViewModel.swift`: steps and positions, cue level, order, listening,
  `markingMistakes` phase with `WordChoice`s, draft restore and save.
- `Features/HifzPracticeFeature/Sources/HifzPracticeView.swift`: options menu (Cues, Order), Listen/Stop button, step
  progress, word choices (`WrappingHStack`, right to left), resumed prompt.
- `Features/HifzPracticeFeature/Sources/HifzPracticeBuilder.swift`: `listen`, `stopListening`, `PracticeStateStore()`.
- `Features/AudioBannerFeature/Sources/AudioBannerViewModel.swift`: `listenAndRepeat(_:repetitions:)`, `stopIfActive()`.
- `Features/QuranViewFeature/Sources/QuranInteractor.swift`: wiring, `audioStopped()` on `highlightReadingAyah(nil)`,
  `startPractice` after the running practice saves.
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: aliases `listenAndRepeat` (`speaker.wave.2`), `stopListening`
  (`stop.fill`), `practiceOptions` (`slider.horizontal.3`).
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: 14 `hifz_practice.*` keys in all 16 languages.

## Tests

- `MemorizationServiceTests/PracticePlanTests` (4): straight order; cumulative A, B, A+B, C, A+B+C; one and zero ayahs; cue
  words per level.
- `MemorizationServiceTests/PracticeStateStoreTests` (5): defaults; choices kept; draft round trip and clear; newer version,
  garbage and impossible verse ignored; the version-1 stored format decodes (persisted-format regression).
- `HifzPracticeFeatureTests/HifzPracticeViewModelTests` (+7): cue level in the mask and remembered; cumulative order
  recites 1, 2, 1, 2, 3 … (13 recitations for 112:1–4) and hides later ayahs on a review step; order changes only before
  the first grade; mistaken words recorded with the ayah (`[0, 3]`); listening plays the ayah, stops on Check and counts as
  help; **resume after kill** (a second view model on the same store continues at 112:3 and saves one session with three
  ayahs, no draft left); another passage's draft saved as its own session.
- `QuranImageFeatureTests/ContentRecitedWordTests` (+1): cue words stay visible through the glyph mapping (2:7's 7th text
  word is glyph 8). `QuranAnnotationsTests/VerseOverlaysTests` (extended): cue words restricted to the page.
- No bug fix in this change, so no regression test was required to fail first.

## Validation

- **Verified:** focused runs: `make test-no-sync TARGET=HifzPracticeFeatureTests` `Executed 11 tests, with 0 failures`;
  `MemorizationServiceTests` `Executed 23 tests, with 0 failures`; `QuranImageFeatureTests`, `QuranAnnotationsTests`,
  `LocalizationTests`, `AudioBannerFeatureTests` all exit 0 with 0 failures. Full suites, one after another (xcresult
  summaries): `make test-no-sync` 1,736 passed, 0 failed; `make test-sync` 2,217 passed, 0 failed; `make test-arabican` 117
  passed, 0 failed; `make test-tools` `22 passed, 0 failed`. Builds: `make build-example-no-sync`, `make build-example-sync`
  (Package.resolved restored after it), `make build-arabican`, all exit 0. `make format-lint`: `0/1257 files require
  formatting`.
  Hands-on on the iPhone 18 Pro Max simulator (`make run-example-no-sync`, Hafs 1405, page 604, reciter Husary): options
  menu shows Order and Cues; First Word of Each Ayah shows قُلۡ, ٱللَّهُ, لَمۡ, وَلَمۡ and each later ayah's first word with
  the rest still covered; Listen played 112:1 (banner toast "Playing Al-Ikhlāṣ 112:1"), the playing-ayah highlight stayed
  under the masks, the button showed Stop and went back to Listen by itself when the three runs ended; Check → Mistakes
  listed قُلۡ هُوَ ٱللَّهُ أَحَدٌ right to left, هُوَ turned red, Done moved to 112:2; after `simctl terminate` the draft was in
  the app's preferences (224 bytes), and Practice on 112:1 reopened at 112:2 with "Picked up where you left off."; × saved
  the session: the store holds 112:1 word 0 and word 2 as mistakes, and the draft key is gone.
- **Not verified:** cumulative order and Every Other Word tapped through in the app (covered by view-model tests only);
  landscape, Dark mode and a large Dynamic Type size for the new controls (the word choices wrap with `WrappingHStack` and
  scale with `@ScaledMetric`; the options menu and an extra icon button may crowd the bar at accessibility sizes);
  VoiceOver on the word choices (labels are the Arabic words, marked ones say selected); compact iPhone and iPad split view
  (no other simulator allowed); a reciter that is not downloaded with streaming off (the banner downloads first, the Listen
  button shows Stop meanwhile); the "Modify" action of the toast while practicing.

## Release

- **Commit:** recorded in the follow-up `docs(trail)` commit.
- **Pushed:** recorded in the follow-up commit.
- **TestFlight:** Quran and Arabican builds recorded in the follow-up commit.
- **iCloud / CloudKit schema:** unchanged (user defaults only; no Core Data change).

## Follow-ups

- H2 slice c: translation-view practice (hide Arabic, optional meaning cue), line-page readings, turning the page when the
  current ayah is on the next page.
- A resume prompt at launch (today the draft resumes when Practice is opened on the same passage).
- Keep ayah end markers visible between hidden ayahs (from slice a).
- V2b: reveal and advance from live recitation; it can reuse `toggleListening`'s audio hand-off and the word choices.
