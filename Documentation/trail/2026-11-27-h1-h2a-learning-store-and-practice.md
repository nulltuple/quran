# Quran H1 + H2 slice a: learning store, MemorizationService (FSRS) and practice on the page

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-27-d2-swift-fsrs-root-package.md](2026-11-27-d2-swift-fsrs-root-package.md) (D2),
  [2026-11-26-f2-backup-restore.md](2026-11-26-f2-backup-restore.md) (backup schema 1),
  [2026-11-27-v3a-recite-and-check.md](2026-11-27-v3a-recite-and-check.md) (ayah menu wiring, word texts),
  [2026-11-25-m3-1-local-verse-collections-store.md](2026-11-25-m3-1-local-verse-collections-store.md) (`Quran 3`),
  roadmap §4 and §6 H1/H2 ([quran-prioritized-roadmap.md](../agents/quran-prioritized-roadmap.md))

## Context

App: **Quran**, with shared NoorUI and Localization changes, so **Arabican** builds and ships too (it imports both).
The session that started this one asked to continue the roadmap at H1+H2 (roadmap v4 §5 item 10): "H1 is the
learning store (`Quran 4` Core Data model) and `MemorizationService`, scheduling review per passage with swift-fsrs
6.0.0 ... H1 must add its learning records to F2's backup (schema 2 ...) and carry evidence provenance (manual or
model). H2 is practice mode: hide and reveal on the page, hints, grading, listen-and-repeat, cumulative." The roadmap
ships H1 together with H2's first slice ("release gate is a working feature"); this change is that slice.

## Decisions

- **Two entities now, not four.** `Quran 4` adds `MO_PracticeSession` (id, first and last ayah, start and end) and
  `MO_RecallEvidence` (id, session id, sura, ayah, word (0 = whole ayah), outcome, assistance, provenance, recorded,
  retracted). The roadmap's `MemorizedRange` (declared memorization) and `Passage` (user-edited splits) are left to
  H3, whose map and "declare what I know" screens are their only writers; adding them now would ship entities
  nothing reads or writes, each needing backup code. A later `Quran 5` is a lightweight migration like this one.
- **CloudKit-compatible rules** (roadmap §4): UUID ids, every attribute optional or defaulted, no relationships
  (evidence names its session by id), no unique constraints (inserts skip stored ids), append-only: a disputed or
  mistaken record gets `retractedOn` and stays. Outcome and provenance are stored raw values
  (`RecallOutcome`: correct, mistake, hint, revealed, skipped, selfCorrected; `EvidenceProvenance`: manual, model);
  records with an unknown raw value (a newer version) are skipped when read.
- **The FSRS card is never stored.** `PassageScheduler` replays a passage's graded sessions through swift-fsrs
  (`FSRS(parameters: FSRSParameters(enableFuzz: false))`, as Arabican's `ReviewScheduler`) every time progress is
  read, so sync and backup carry only evidence and the scheduler can change without a migration. Tens of sessions
  per passage at most; cost is negligible (UNVERIFIED on device, not measured).
- **Session grade** (`EvidenceReducer.grade`, pure): again if any ayah was revealed ("Forgot") or a third or more of
  the graded ayahs had mistakes; hard if any mistake, hint, self-correction or help; good otherwise. **Easy is never
  inferred**: one clean recitation should not push a hafiz's passage to long intervals. Skipped ayahs are not graded.
  Strength: unassessed (no graded session), learning (FSRS learning or relearning), weak (review state, last grade
  hard), strong (review state, last grade good). Declared vs demonstrated waits for H3's declarations.
- **Passage = the practiced range.** One selected ayah practices from it to the end of its page (a hafiz revises a
  page or a passage, not one ayah); a multi-ayah selection practices exactly that. Product assumption, recorded;
  H3 makes passages user-editable.
- **Masks on the page image, in the text's word numbering.** `PracticeMask` (in `VerseOverlays`, QuranAnnotations)
  names hidden verses and one partial verse with its revealed word count (QUL numbering).
  `ContentImageViewModel.maskedImageWords` maps that to image glyphs through the existing `imageWords` mapping (2:7's
  pause-mark glyph shifts its numbering), and NoorUI's `QuranPracticeMask` covers them, joined per line and verse,
  with the page background plus a faint text tint, over the image: the layout never moves. While grading, the
  current ayah is shown whole, so its end marker (a glyph after its last word) shows too (first hands-on run showed it
  hidden).
- **Bar in the audio bar's place** (V2a's `presentRecitationFollow` slot) instead of taps on the page: page taps go to
  the bar-toggling recognizer and the long press (gotchas), and buttons work with VoiceOver. Reciting: First Letter,
  Next Word (both count as help), Check. Grading: Forgot (`.revealed`), Mistakes (`.mistake`), Correct (`.correct`, or
  `.hint` when help was used). Close (×) saves the ayahs graded so far; nothing graded saves nothing. Starting
  practice pauses audio and ends live follow; the reader's microphone does nothing while practicing (V2b).
- **First-letter hint without moving `ArabicScript`.** The roadmap moves `ArabicScript` from ArabicLearning for H2's
  first-letter hints; a Swift `Character` is already a grapheme (letter with its marks), so the hint is the first
  `Character` of the word's Uthmani text from V3a's `ExpectedWordsReader`. A word written joined to the one before it
  has no text of its own and shows "…". It renders in the Quran font (`FontName.uthmanicHafs`), never the system font.
- **Scope cut to image pages in the reader.** No Practice row in the translation view or for line-page readings
  (`Reading.usesLinePages`), `AyahMenuViewModel.canPractice`. No per-word mistake marking, progressive masking levels,
  listen-and-repeat, cumulative steps or resume after kill: H2 slices b and c (Follow-ups).
- **Both sync modes.** The learning store is local Core Data in sync builds too (MobileSync has no such records);
  backup stays no-sync, as F2.
- **Backup schema 2.** `BackupSnapshot` gains `practiceSessions` and `recallEvidence` (the persistence record types,
  whose field names are now part of the format), decoded with `decodeIfPresent` so schema 1 files restore with none.
  Merge: a session or evidence id already stored is kept; a retraction in the backup retracts the stored record.
  Replace deletes them like everything else. Validation: real verses, first ≤ last, word and assistance ≥ 0.
- **Package pins:** swift-fsrs 6.0.0 added to the root `Package.swift` and `Package.resolved` with the revision
  Arabican's files already pin (`74cb0297…`), so `ArabicLearning/Package.resolved` and the Arabican project's resolved
  file needed no change (`Tools/package-pins.test.sh`).

## Trade-offs

- **Complexity added:** 3 targets + 1 feature target (`MemorizationPersistence` 2 files ~290 lines,
  `MemorizationService` 4 files ~400, `HifzPracticeFeature` 3 files ~420), NoorUI `QuranPracticeMask` (~45),
  `PracticeMask` (~40), reader and menu wiring (~90), backup (~110). Tests ~520 lines in 5 files. One dependency
  (swift-fsrs, already vetted and built for Arabican). New persisted state: two Core Data entities (model `Quran 4`)
  and backup schema 2; no permission, entitlement or background work. New failure modes: a failed save shows "Couldn't
  load or save this practice" and nothing is stored.
- **Who benefits / how often:** people memorizing, daily if they adopt it; likely a minority of readers (UNVERIFIED).
  Without H3's queue the scheduled due date is only shown after a session, so the value grows with H3.
- **Rejected cheaper options:** a practice sheet with its own text (cheaper, but the roadmap's design is the real page
  so the printed layout is what is memorized); storing FSRS cards (needs migration whenever the scheduler changes,
  and sync conflicts); a fixed-interval ladder (D2 approved FSRS); moving `ArabicScript` now (one cross-app move for
  one `Character` call).
- **Ongoing cost:** every new learning entity needs a backup schema bump; FSRS pin shared by three resolved files;
  16 more strings in 16 catalogs (agent translations, native review UNVERIFIED).

## Changes

- `Package.swift`, `Package.resolved`: swift-fsrs 6.0.0; targets `MemorizationPersistence`, `MemorizationService`,
  `HifzPracticeFeature`; BackupPersistence and BackupService depend on MemorizationPersistence; QuranViewFeature on
  HifzPracticeFeature. `QuranEngine-Package.xctestplan`: the three test targets.
- `Data/CoreDataModel/Sources/Quran.xcdatamodeld/Quran 4.xcdatamodel` (new current version), `Schema.swift`.
- `Data/MemorizationPersistence/Sources/`: `MemorizationRecords.swift` (`RecallOutcome`, `EvidenceProvenance`,
  `MemorizationVerse`, `PracticeSessionRecord`, `RecallEvidenceRecord`, `MemorizationHistory`, Core Data mapping),
  `CoreDataMemorizationPersistence.swift` (`history`, `record`, `retractEvidence`).
- `Domain/MemorizationService/Sources/`: `Passage.swift` (`Passage`, `PassageStrength`, `SessionGrade`, `VerseRecall`,
  `PassageProgress`), `EvidenceReducer.swift`, `PassageScheduler.swift`, `MemorizationService.swift`.
- `Data/BackupPersistence/Sources/BackupSnapshot.swift`, `CoreDataBackupPersistence.swift`: learning records in
  snapshot, merge and replace. `Domain/BackupService/Sources/BackupService.swift`: schema 2, validation,
  `BackupSummary.practiceSessions`. `Features/SettingsFeature/Sources/Backup/BackupView.swift`: preview row.
- `Model/QuranAnnotations/Sources/PracticeMask.swift` (new), `VerseOverlays.swift`: `practiceMask`, restricted per page.
- `UI/NoorUI/Sources/Components/QuranPracticeMask.swift` (new); `Features/Quran/ImageDecorations.swift`
  (`maskedWords`), `ImageDecorationsLayout.swift` (`maskRects`), `AdaptiveImageScrollView.swift` (overlay).
- `Features/QuranImageFeature/Sources/ContentImageViewModel.swift`: `maskedImageWords`.
- `UI/NoorUI/Sources/Features/AyahMenu/AyahMenu{UI,View}.swift`: optional `practice` action and row.
  `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: `hifzPractice` (`eye.slash`), `revealWord` (`eye`),
  `firstLetterHint` (`lightbulb`).
- `Features/AyahMenuFeature/Sources/AyahMenu{ViewModel,ViewController}.swift`: `practice`, `canPractice`, listener.
- `Features/HifzPracticeFeature/Sources/HifzPractice{ViewModel,View,Builder}.swift` (new).
- `Features/QuranViewFeature/Sources/Quran{Interactor,Builder}.swift`: `practice(_:)`, `dismissHifzPractice`.
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: 15 `hifz_practice.*` keys and
  `backup.count.practice-sessions` in all 16 languages.
- iPhone and iPad share every file; no platform conditionals.

## Tests

- `MemorizationPersistenceTests/CoreDataMemorizationPersistenceTests` (5): round trip; same ids twice store nothing new;
  retraction keeps its first date; unknown outcome from a newer version skipped; **`Quran 3` → `Quran 4` upgrade keeps
  collections and notes** and then records a session.
- `MemorizationServiceTests/EvidenceReducerTests` (6): duplicates and retraction (idempotent); good, hard, again rules;
  skipped ayahs ungraded.
- `MemorizationServiceTests/MemorizationServiceTests` (8): unassessed; one manual record per ayah and per mistaken word;
  clean sessions grow the interval and become strong; a revealed ayah relearns sooner; a hard review is weak; retracted
  evidence stops counting; soonest due first; passage end order.
- `BackupPersistenceTests` (+1, sample extended): learning records in round trip, merge twice, replace; merge adds new
  ids and carries a retraction.
- `BackupServiceTests` (+1, others updated): schema 2 header; **a schema 1 file restores** without learning records and
  keeps stored ones on merge; five impossible learning records refused; summary count.
- `HifzPracticeFeatureTests/HifzPracticeViewModelTests` (4): full practice of 112:1–4 with real Uthmani and
  word-by-word databases (masks, hint قُ, next word, check shows the whole ayah, grades saved as hint, correct,
  mistake, revealed, finished grade again); ending early saves graded ayahs only; ending before grading saves nothing;
  one selected ayah practices to its page's end.
- `QuranImageFeatureTests/ContentRecitedWordTests` (+2): masks on page 3 follow the glyph mapping (2:7's 7th word is
  glyph 8); nothing revealed hides the whole verse. `QuranAnnotationsTests/VerseOverlaysTests` (+1): mask restricted
  to the page. `AyahMenuFeatureTests` (+1): Practice reports the selected verses.
- The grading-mask fix came from the hands-on run; its assertion (`partialVerse` nil while grading) was added with it
  and would fail without it (reasoned from the diff: before, the mask kept the current verse as partial).

## Validation

- **Verified:** focused runs `Executed 14 tests, with 0 failures` (MemorizationServiceTests), `Executed 5 tests`
  (MemorizationPersistenceTests), `Executed 14 tests` (BackupPersistenceTests), `Executed 11 tests` (BackupServiceTests),
  `Executed 4 tests` (HifzPracticeFeatureTests), all with 0 failures. Full suites, one after another (xcresult summaries): `make test-no-sync` 1,719 passed, 0
  failed; `make test-sync` 2,200 passed, 0 failed; `make test-arabican` 117 passed, 0 failed; `make test-tools`
  `22 passed, 0 failed` (package pins included). Builds: `make build-example-no-sync`, `make build-example-sync`
  (Package.resolved restored after it), `make build-arabican`, all exit 0. `make format-lint`: `0/1253 files require
  formatting`.
  Hands-on on the iPhone 18 Pro Max simulator (`make run-example-no-sync`, Hafs 1405, page 604): ayah menu shows
  Practice; the page's 15 ayahs hide behind masks with the layout unchanged; First Letter shows قُ in the Quran font;
  Next Word reveals قُلۡ; Check shows 112:1 with its marker; grade buttons; × restores the page and the audio bar.
  Light and Dark.
- **Not verified:** landscape and a large Dynamic Type size (the bar is a VStack with `@ScaledMetric` hint size and no
  fixed widths; three grade buttons may wrap their labels at accessibility sizes); VoiceOver (the masks are
  `accessibilityHidden` and the page image exposes no text, so hidden words are not read; the bar's labels and
  combined title were not listened to); compact iPhone and iPad split view (no other simulator allowed); the page
  scrolling when the current ayah is on the next page (practice does not turn pages); the finished state after the
  last ayah (covered by the view-model test, not tapped through 15 ayahs); device performance of replaying FSRS.

## Release

- **Commit:** see `git log` (feat(hifz): learning store, FSRS and practice on the page (H1+H2a)).
- **Pushed:** origin/main (recorded in the follow-up trail commit).
- **TestFlight:** Quran and Arabican (NoorUI and Localization changed); build numbers recorded in the follow-up commit.
- **iCloud / CloudKit schema:** unchanged (no CloudKit in either app; the entities follow CloudKit rules for P1).

## Follow-ups

- H2 slice b: listen-and-repeat over the audio pipeline, cumulative steps (A, B, A+B …), resume after kill; mark a
  word as a mistake (word-level evidence exists in the store, `VerseRecall.mistakenWords`); progressive masking levels.
- H2 slice c: translation-view and line-page practice; turn the page when the current ayah is on the next page.
- H3: `MemorizedRange` and `Passage` entities (`Quran 5`), the map and due queue reading `MemorizationService.progress()`.
- V2b: reveal and advance from live recitation; V3b: V3a's confirmed mistakes as `.model` evidence with dispute
  (`retractEvidence`).
- Keep ayah end markers visible between hidden ayahs (today they are under the mask of their ayah).
