# C2 (Quran): word study occurrence list that moves the reader and returns

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped (C2 slice c1; tap-to-hear and the word pointer entry are slice c2, a follow-up)
- **Related:** [C2 word study sheet](2026-11-26-c2-word-study-sheet.md) (slices a and b, whose Follow-ups this
  starts), [roadmap v2](2026-11-26-quran-roadmap-v2.md) §6 C2

App: **Quran**. Shared QuranEngine module touched: `Localization` (one key in 16 catalogs), which Arabican also
compiles, so both apps' suites and builds ran and both are released. The rest is in Quran-only feature modules
(`WordStudyFeature`, `QuranContentFeature`, `QuranViewFeature`).

## Context

The owner asked to "continue the Quran roadmap from Documentation/agents/quran-roadmap-progress.md, starting with
the first item under Next steps", which was C2 slice (c): occurrence list over `WordStudyService.occurrences`
(paged, cancellable) that "jumps to the ayah and returns", the main-actor measurement on the largest lists,
tap-to-hear, and a word pointer entry. Slice (c) is three independent pieces; this entry ships the occurrence list
and the measurement (c1). Tap-to-hear needs the audio pipeline to play a sub-ayah time range without disturbing the
main player, and the word pointer entry needs an interaction designed first; both stay open (Follow-ups).

## Decisions

- **Root and Dictionary form rows open the list.** Each is a button row with a disclosure chevron and a VoiceOver
  hint (`word_study.occurrences_hint`); the list is pushed inside the sheet's navigation controller, titled with the
  existing "Root" / "Dictionary form" strings and headed by the Arabic term and its QAC count.
- **A row opens that word's study** (pushed), so the reader can chain root → word → its lemma → … with Back.
- **"Jumps to the ayah and returns" as a reader that follows the sheet.** `WordStudyReaderFollower` (new, 50 lines)
  keeps the reader behind the sheet on the ayah of the word whose study is on top: a study appearing (pushed, or
  revealed by Back) moves the reader there; dismissing the sheet returns the reader to the ayah the study started
  from. Moves go through a new `ContentViewModel.navigate(to:)` (page change + `NavigationHighlighter.navigate`), the
  path the reader already uses to open at a verse, so the target briefly highlights and a drag cancels it. Rejected:
  a separate "Go to ayah" button per row (two actions per row, and the reader would not come back); moving the reader
  permanently (the owner's roadmap says "returns"). Assumption, not asked: a reader who wants to stay at an
  occurrence opens it from the ayah menu or search afterwards.
- **The sheet drops to the medium detent** when an occurrence is opened, so the reader behind it is visible.
- **Pages of 50, loaded by the list's last row.** The progress row's `.task(id: occurrences.count)` loads the next
  page while it is on screen and is cancelled when it scrolls away; a cancelled page adds nothing and is not a
  failure (persistence wraps cancellation in `PersistenceError`, so the view model checks `Task.isCancelled`). A
  failed page stops the list (logged; an empty failed list shows the existing "not available" view).
- **Main-actor measurement.** The reads run in GRDB's reader (`DatabaseConnection.read`, async), never on the main
  actor; the main actor only appends 50 rows. SQLite timing of the occurrence query on the largest lemma, و (9,594
  segments), with `.timer on`: first page 0.85 ms, a page after 100:0:0 0.45 ms (`SEARCH segments USING COVERING
  INDEX segments_lemma`). `test_theLargestListPagesQuickly` pages the whole و list (more than 9,000 distinct words,
  ~190 pages) through the view model and asserts the slowest page under 250 ms; the six occurrence tests together
  took 0.187 s. No Instruments run (see Not verified).
- **Colors inside button rows are explicit** (`secondaryLabel`, `tertiaryLabel`): with `.secondary` the button label
  took the app tint (seen in the simulator before the fix).
- **The prefix-only lists (ال 8,377, و 9,594) are not reachable from the sheet**: only the head segment's root and
  lemma rows open lists. The largest reachable lists are مِن (3,226), أله (2,851) and اللَّه (2,699).

## Trade-offs

- **Complexity added:** ~470 lines: 3 new files in `WordStudyFeature` (`WordStudyReaderFollower` 50,
  `WordOccurrencesViewModel` 87, `WordOccurrencesView` 102), `WordStudyBuilder` +95 (a private navigator),
  `WordStudyView` and view model +40, `ContentViewModel.navigate(to:)` 8, `QuranInteractor` +6; tests 211 lines;
  one localization key × 16 catalogs. No dependency, permission, entitlement, persisted state or background work.
  New failure mode: none persistent; a failed page only stops the list.
- **Who benefits / how often:** readers studying a word's root; one tap further than the sheet itself, so likely a
  minority of a minority (UNVERIFIED, no analytics). Kept because it is the core of "word study" in roadmap v2 and
  the data and service already existed.
- **Rejected cheaper options:** a static count only (what slice b shipped; the roadmap asks for the list); loading
  the whole list at once (و would be 9,000+ rows and meanings in one read, though measured fast; paging keeps memory
  bounded); a SwiftUI `NavigationLink` (needs `NavigationStack` iOS 16+ or the deprecated `NavigationView`; the sheet
  is already a `UINavigationController`).
- **Ongoing cost:** small; the follower couples word study to `ContentViewModel.navigate(to:)`, one public method.

## Changes

- `Features/WordStudyFeature/Sources/WordStudyReaderFollower.swift` (new): origin, `show(_:)`, `returnToOrigin()`.
- `Features/WordStudyFeature/Sources/WordOccurrencesViewModel.swift`, `WordOccurrencesView.swift` (new).
- `Features/WordStudyFeature/Sources/WordStudyBuilder.swift`: `build(word:readerFollower:)`; private
  `WordStudyNavigator` pushes lists and studies and sets the medium detent.
- `Features/WordStudyFeature/Sources/WordStudyViewModel.swift`, `WordStudyView.swift`: `showOccurrences` and
  `showVerse` closures, `didAppear()`, `select(_:)`; tappable term rows.
- `Features/QuranContentFeature/Sources/ContentViewModel.swift`: `navigate(to:)`.
- `Features/QuranViewFeature/Sources/QuranInteractor.swift`: `presentWordStudy` creates the follower and returns the
  reader on dismissal.
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: `word_study.occurrences_hint` (agent
  translations in 15 languages, native review UNVERIFIED).
- Platforms: iPhone and iPad (one universal target); no platform-specific code.

## Tests

- `WordStudyFeatureTests/WordOccurrencesViewModelTests` (6): pages ح م د in Quran order 30/60/68 until complete; a
  complete list loads nothing more (حَمْد 43); selecting opens the word (2:30 word 20); a missing database fails and
  stops; a cancelled page is not a failure and loads again; the whole و list pages under 250 ms per page.
- `WordStudyFeatureTests/WordStudyReaderFollowerTests` (4): the origin does not move the reader; another word moves
  it once; dismissal returns it; Back to the first study returns it and dismissal then does nothing.
- `WordStudyFeatureTests/WordStudyViewModelTests` (+2): appearing moves the reader to the word's ayah; selecting a
  root opens its occurrences.
- `QuranContentFeatureTests/ContentViewModelTests` (+1): `navigate(to:)` on another page sets the visible page, the
  navigation target and the highlight.

## Validation

- **Verified:**
  - `make test-no-sync TARGET=WordStudyFeatureTests`: `Executed 20 tests, with 0 failures`;
    `TARGET=QuranContentFeatureTests`: `Executed 26 tests, with 0 failures`.
  - Simulator (iPhone 18 Pro Max), no-sync build, Translation/Tafseer mode with word-by-word English: tap
    ٱلرَّحْمَٰنِ in 1:1 → Root ر ح م (339) → list from 1:1 word 3; scrolled past the first page into Al-An'ām (second
    page loaded); tap 2:64 "and His Mercy" → its study pushed, the sheet dropped to medium, the reader moved to page
    10 at 2:64; Back twice → the reader returned to 1:1. Dictionary form رَحْمٰن (57) → 19:18 → the reader moved to
    Maryam; swiping the sheet away returned the reader to 1:1 with the brief highlight. Dark mode and the
    accessibility-extra-large text size: rows wrap, colors neutral.
  - Full suites after the last source change (xcresult summaries, run one after the other): `make test-no-sync`
    `Passed 1544/1544` (1,531 at C2 a/b); `make test-sync` `Passed 2023/2023`; `make test-arabican` `Passed 117/117`.
  - `make format-lint`: `0/1178 files require formatting`. `make build-example-no-sync`, `make build-example-sync`,
    `make build-arabican`: `Build Succeeded` each.
- **Not verified:**
  - **The jumped-to ayah can land under the medium sheet.** The translation list scrolled 2:64 and 19:18 to about
    45% of the screen, not the 20% anchor `quranScrolling` asks for (`UI/NoorUI/Sources/Features/Quran/
    QuranScrollingViewModifier.swift:103`), so the ayah sat just under the sheet; dragging the sheet down shows it.
    Pre-existing scroll precision of the lazily sized translation `List` (the same path as opening the reader at a
    verse); not changed here (Follow-ups).
  - The Mushaf page mode (word study opens only from the translation view today, so a jump is always in it).
  - VoiceOver on the new rows on a device; landscape; iPad split view (no iPad simulator allowed); the sync build in
    the simulator (compiled and tested only); an Instruments trace of the list on a device.

## Release

- **Commit:** `657f338538c618dbad7cda11377beaee3b0e380b`
- **Pushed:** origin/main at `657f3385` (`ea7c9145..657f3385  HEAD -> main`)
- **TestFlight:** Quran build 996 (1.20.3): `Uploaded Quran iOS 1.20.3 (996) for commit
  657f338538c618dbad7cda11377beaee3b0e380b to App Store Connect app MemQuran.` Arabican build 996 (0.1.0):
  `Uploaded Arabican iOS 0.1.0 (996) for commit 657f338538c618dbad7cda11377beaee3b0e380b to App Store Connect app
  Arabican.` This Arabican build also carries the shared-module changes of C2 a/b (`f03021d8`), whose Arabican upload
  had failed on the Xcode account.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- C2 slice c2: tap-to-hear a word from the Afasy word timings (`qul_afasy.db`, reciter 1001), labeled as an excerpt
  of connected recitation; a word pointer entry (`Features/WordPointerFeature`, design the interaction first).
- Scroll a navigated verse to its anchor in the translation view (the 45% landing above), or keep it above a medium
  sheet.
