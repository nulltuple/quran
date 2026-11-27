# Quran app roadmap (v2): reader, comprehension and memorization

**App: Quran** (App Store Connect "MemQuran", `com.nulltup.memquran`). Not Arabican's roadmap; that
one is [Documentation/ArabicLearning/](../ArabicLearning/HANDOFF.md).

- **Version 2, 2026-11-26** (Claude Code / claude-opus-5-5). Reconciles the v1 roadmap
  (2026-11-24, M1–M15; in git history at `a3f5f5ef`) with Codex's competitive research
  [research/2026-11-26-tarteel-competitive-research.html](research/2026-11-26-tarteel-competitive-research.html)
  (Q0–Q17) and with the code at `a3f5f5ef`. Trail:
  [2026-11-26-quran-roadmap-v2.md](../trail/2026-11-26-quran-roadmap-v2.md).
- **Live status** (per item, evidence, commits, builds, handoff):
  [quran-roadmap-progress.md](quran-roadmap-progress.md). This file is the spec; it does not
  claim anything is built.

## 1. Mandate

The best Quran app for the owner and their family: **reading, understanding and memorizing**,
better than Tarteel, Quran.com, GreenTech and Quranly for that household. Owner directives that
shape every milestone:

- Fastest path to a **polished** product the family uses daily. Ship vertical slices to
  TestFlight; no library-only releases.
- **Reuse before building.** Reinvent only when confident the result beats what is openly
  available (data from QUL, Quranic Arabic Corpus, Quran.com; Apple frameworks; packages already
  vetted in this repository).
- **Licensing does not restrict reuse** (personal, non-commercial; AGENTS.md "Licensing").
  Record sources and hashes for traceability only.
- English and **Bengali** are first-class study languages.
- **Keep it modular for Arabican.** Logic Arabican could use lives once in QuranEngine (AGENTS.md
  "Two apps", rule 3); every new shared module below names its future Arabican consumer. No
  Arabican feature work happens in this roadmap.
- Offline-first, no account, no paid service, no telemetry of user content.

## 2. Where we are (verified at `a3f5f5ef`, 2026-11-26)

- **M1 (word-by-word reader) is shipped** (builds 955–959): canonical word identity for all
  6,236 ayahs and 77,432 words, English/Bengali meanings, transliteration, Afasy word-timed
  highlight, localized in 16 languages. Dual-language meanings stay blocked on the owner.
- **M2 (more synchronized reciters) is blocked** on QUL downloads that need the owner's sign-in.
- **M3 is in progress:** M3.1 (local Core Data store for collections, model `Quran 3`) shipped in
  build 961 with no UI. **M3.2 is the next slice.** Confirmed: no Quran commit since `dbeb4894`;
  later commits are Arabican L0–L7 and tooling.

### Corrections to the research (adversarial review against the code)

| Research claim | Code says | Consequence |
|---|---|---|
| Tafsir is "existing infrastructure" (§11, §16) | No tafsir anywhere: `grep -ri tafsir` finds only a font name and a footnote chunk | Tafsir is the largest comprehension gap; it gets its own milestone (C1), early |
| Landscape two-page view is a gap (Tarteel's #5 request) | Already built: `Features/QuranPagesFeature/Sources/QuranPaginationView.swift`, More menu two-pages option | Not a milestone; device check only |
| More Mushaf layouts need new work | `Reading` has 7 editions incl. `.tajweed` and `.indoPak` (`Model/QuranKit/Sources/Reading.swift:11-17`); only the download source is missing: `remoteResources = nil` (`Example/QuranEngineApp/Classes/Container.swift:38`) | R1 is mostly finding verified download URLs, not code |
| Private sync is a late, large milestone (Q15) | `CoreDataStack` already builds `NSPersistentCloudKitContainer` (`Data/CoreDataPersistence/Sources/CoreDataStack.swift:123`); the app turns it off (`Container.swift:91`) | iCloud sync of notes, bookmarks, collections is mostly an entitlement plus schema rules (P1). Learning records go in the same Core Data store so they sync for free |
| Extract Arabican's scheduler (Q2) | `LearningEngine/ReviewScheduler.swift` is a 44-line wrapper over swift-fsrs | Nothing worth extracting; the decision is whether the root package may depend on swift-fsrs (owner) |
| A standalone "learning primitives" milestone (Q2) | AGENTS.md: release gate is a working feature | Primitives ship inside the first Hifz slice (H1) |
| Reader and comprehension last (Q16) | The owner asked for reading and comprehension, not only memorization | Reader and comprehension waves come first; they are cheap because the infrastructure exists |

## 3. Product shape

Quran stays a **reader first**. Memorization and study attach to the reader (ayah menu, word
tap, a Practice entry) plus one new **Practice** surface on Home, not a new app shell.

| Mode | What the user does | Milestones |
|---|---|---|
| Read | Mushaf page or translation view, choice of edition, bookmarks, notes, highlights | R1, F1, F2, P1 |
| Understand | Tafsir, word meaning, root/lemma/grammar, occurrences, translation compare | C1, C2, C3 |
| Listen | Reciters, ranges, repeats, word highlight, tap-to-hear a word | existing, C2, M2 |
| Memorize | Hide/reveal on the real page, hints, listen-and-repeat, cumulative steps | H1, H2 |
| Review | Due queue by passage, memorization map, Sabaq/Sabqi/Manzil | H3 |
| Test | Random-start exams, strict and granular scores | H4 |
| Repair | Similar verses, confusion sets, mistake history | H5, H7 |
| Plan | Goals, Khatmah, today's plan, gentle streaks | H6 |
| Recite (AI) | Voice search, live follow, mistake detection | V0–V3 |

## 4. Architecture for both apps

Layer rules are `Package.swift`'s (`TargetType.validDependencies`). New modules are added only
when a slice needs them, through the package's target helpers.

| New or extended unit | Layer | Owns | Quran slice | Future Arabican consumer |
|---|---|---|---|---|
| `QuranKit` range algebra (extend) | Model | union, difference, contains over `AyahNumber` ranges; canonical, edition-free | H1 | lesson ranges in the bridge reader |
| `ArabicScript` (**move** from `ArabicLearning/` to QuranEngine `Model/`) | Model | graphemes, letters, marks | H2 (first-letter hints), H5 (normalization) | Arabican imports it from QuranEngine instead of its own copy; one move, both apps tested |
| Morphology data + `WordStudyService` | Data + Domain | full-Quran QAC segments, root, lemma, POS, features, occurrence indexes in a bundled read-only SQLite | C2 | replaces Arabican's Juz-Amma-only `lemmas.tsv`/`word_segments.tsv` (Arabican follow-up, not here) |
| Tafsir packs | Data + Domain | downloadable per-pack read-only SQLite, ayah-range keyed | C1 | tafsir in the bridge reader word sheet |
| `MemorizationService` | Domain | evidence events, evidence reducer, passage scheduler (FSRS), Sabaq/Sabqi/Manzil buckets, seeded sampling, scoring; clock injected, no UI | H1–H7 | vocabulary and recitation review if Arabican ever wants Quran-passage review |
| Learning entities in the Core Data model (`Quran 4`+) | Data | sessions, evidence (append-only), declared ranges, goals; CloudKit-compatible | H1 | none (app data stays per app; AGENTS.md) |
| `RecitationRecognition` | Domain | microphone session boundary, recognizer protocol, alignment to canonical words, confidence | V0–V3 | Arabican R1 recognition research uses the same adapter |

**Persistence decision (opinionated).** Learning records go in the existing Core Data stack, not
a new GRDB file like Arabican's: the stack already supports `NSPersistentCloudKitContainer`, so
P1 sync covers them without a second sync engine. Rules that keep the model CloudKit-compatible:
UUID identities, every attribute optional or defaulted, no unique constraints (dedupe on read by
id), append-only evidence with tombstones instead of deletes, derived state (review queue,
heatmap) recomputed from evidence and never synced. Aggregation stays small: tens of thousands of
events at most for one learner.

**Scheduler decision (opinionated).** Review is scheduled per **passage** (an ayah range a person
recites in one go: default one ruku or half a page, user-editable), never per word: a hafiz
does not revise isolated words. Word-level mistakes stay as evidence and drive repair (H7).
FSRS (swift-fsrs, already pinned for Arabican) schedules passages if the owner approves it in the
root package (decision D2); otherwise a transparent fixed-interval ladder with the same protocol.

## 5. Milestones in execution order

IDs are by area so reordering never renumbers: **F** data foundation, **R** reader, **C**
comprehension, **H** memorization (Hifz), **V** voice, **P** platform. Each milestone is one or
more shippable slices; each slice runs AGENTS.md's full definition of done and, when the binary
changes, a TestFlight upload.

| # | ID | Milestone | Why here | Size | Blockers / owner decisions |
|---|---|---|---|---|---|
| 1 | **F1** (=M3.2) | Collections, Favorites, highlights in the shipping build | finishes M3; every competitor has it; store already shipped | S | none (Bookmarks-tab shape decided below) |
| 2 | **R1** | Mushaf editions: Tajweed-colored Madani, IndoPak, 1421/1441 | code exists; IndoPak matters for a Bengali household; Tajweed Mushaf gives static tajweed for free | S if URLs exist | verified public download URLs (research step); else blocked |
| 3 | **C1** | Tafsir, offline packs (Arabic, English, Bengali) | biggest comprehension gap | M | source and format verified in the slice |
| 4 | **F2** (=M3.4) | JSON backup and restore (preview, merge or replace) | protects family data before the learning schema lands | S–M | none |
| 5 | **C2** | Word study: morphology sheet, occurrences, tap-to-hear word | beats Tarteel on comprehension; data pipeline proven in Arabican L5 | M | none |
| 6 | **H1** (=M3.3 + Q2) | Learning store and `MemorizationService`, shipped with H2's first slice | prerequisite for every Hifz feature | M | **D1** minimum iOS, **D2** swift-fsrs |
| 7 | **H2** | Practice mode: hide/reveal on the real page, hints, grading, listen-and-repeat, cumulative | the core memorization loop, no AI needed | L (2–3 slices) | none |
| 8 | **H3** | Memorization map and passage review queue (Sabaq/Sabqi/Manzil) | turns practice into retention | M | D2 |
| 9 | **H4** | Spot tests: random start, strict and granular scores, temporary tests | Tarteel's newest flagship, deterministic | M | none |
| 10 | **H5** | Similar verses (mutashabihat) and confusion drills | high value for huffaz, deterministic | M | none |
| 11 | **P1** | Private iCloud sync (notes, bookmarks, collections, learning records) | iPhone + iPad per person; infrastructure exists | S–M | **D3** iCloud entitlement and schema deployment |
| 12 | **H6** | Goals, Khatmah, reading/listening time, today's plan, gentle streaks, reminders | habit and planning | M | **D5** notification permission (reminders only) |
| 13 | **H7** | Mistake history heatmap and repair queue (manual evidence first) | makes H2–H5 evidence useful | M | none |
| R | **V0** | Voice feasibility spike (bounded; may run any time after H2's first slice) | decides whether V1–V3 happen | M | **D4** microphone permission, recognizer dependency, consented family recordings |
| 14 | **V1** | Offline voice search | first, bounded AI feature | M | V0 pass |
| 15 | **V2** | Live recitation follow and automatic reveal in Practice | hands-free memorization | L | V1 |
| 16 | **V3** | Word mistake detection feeding H7 | Tarteel's paid core | L | V2 pass |
| 17 | **C3** | Translation compare, formatted share, search filters and history | polish; independent slices may move earlier | S each | none |
| 18 | **P2** | Widgets, App Intents/Shortcuts, Spotlight | convenience after core flows | M | capability approvals if any |
| — | **M2** | More synchronized reciters, word/phrase loop | slot in whenever unblocked | M | owner QUL downloads |

### Excluded or parked (and why)

- **Excluded:** Tarteel history import (no fixture, little value for a household); multiple
  riwayat (no verified resources); teacher/family backend, leaderboards, achievements;
  LLM-generated tafsir or explanations (fabrication risk on scripture; Apple Foundation Models
  included); generated Quran audio; Apple Pencil annotation; desktop, watch, TV ports; prayer
  times (Fajrly).
- **Parked (P3):** vowel, phoneme and tajweed-rule assessment of the user's recitation (research
  only after V3, needs qualified reviewers); recording retention and replay (opt-in, after V3);
  static tajweed coloring in the translation view (the Tajweed Mushaf in R1 covers page reading;
  Arabican L6 learned that the Quran font's ligatures drop per-letter color); local multi-profile
  (family members use their own devices; revisit if a shared iPad appears); dual-language
  meanings (owner decision).

## 6. Milestone specifications

Every slice: inspect current main first, cite `path:line`, add tests in the owning module, keep
both sync modes green, update the cost register row, trail entry and progress file, release.

### F1 — Collections, Favorites and highlights in the shipping build (was M3.2)

Goal: in TestFlight, the ayah menu's Bookmark action opens the collection editor, and the
Bookmarks tab lists Favorites and user collections, all stored by M3.1's
`PersistenceAyahBookmarkCollectionService`.

- Add `collectionPersistence` and a no-sync `ayahBookmarkCollectionService()` to
  `AppDependencies`, `Container`, `AppDependenciesFake`.
- A no-sync highlight service with `MobileSyncAyahHighlightService`'s API over `NoteService`;
  removing a highlight keeps a note's text.
- Un-gate the collection screens; gate off only reading bookmarks, `syncNow` and
  `SyncSignInNudge`.
- **Decision (reversible UI, made here per AGENTS.md):** the no-sync Bookmarks tab shows the sync
  build's collections list (Favorites first, then user collections) followed by the existing
  page-bookmarks section. The sync build does not change.
- Accept: collection create/rename/delete, add/remove ayah, Favorites toggle, highlight colors,
  all offline; restart keeps them; sync build behavior unchanged (both suites).

### R1 — Mushaf editions

- **Status (2026-11-26):** done for Hafs 1421, 1439, 1440, 1441 and Tajweed from verified
  `files.quran.app` packs (`QuranAppReadingRemoteResources`); **IndoPak blocked**: no verified public
  pack. Trail: [2026-11-26-r1-mushaf-editions.md](../trail/2026-11-26-r1-mushaf-editions.md).
- Research step (time-boxed): find the public download source for each `Reading` the upstream
  app uses (the `files.quran.app` host is already used for audio,
  `Container.swift:132`; image zips per reading are UNVERIFIED). Verify each zip: page count,
  ayah-info database, checksum, size. Do not guess URLs.
- Implement `ReadingRemoteResources` in `Example` with the verified entries; keep `hafs_1405`
  bundled as the fallback. Reading position moves between editions by canonical ayah, never by
  page number (check `ReadingSelectorFeature` already does; test it).
- Word-frame coverage per edition decides which editions get the word pointer, word highlight
  and H2 masking; editions without word frames show ayah-level only, labeled.
- Accept: each enabled edition downloads, resumes after interruption, survives a corrupt zip,
  works offline, and is removable; no option shown whose resource is unavailable.
- Blocked if no verified source: record it and move on.

### C1 — Tafsir

- **Status (2026-11-26): Arabic slice shipped** (trail
  [2026-11-26-c1-tafsir-sheet.md](../trail/2026-11-26-c1-tafsir-sheet.md)). Arabic tafsirs download through
  Settings > Translations as before; the ayah menu's "Tafsir" row (page and translation modes) opens a sheet
  with a tafsir picker, the passage's range and Quran text, and next/previous ayah. English Ibn Kathir (Abridged)
  and Bengali Ahsanul Bayaan shipped next (trail
  [2026-11-26-c1-english-bengali-tafsir.md](../trail/2026-11-26-c1-english-bengali-tafsir.md)): packs on the
  `tafsir-packs-1` GitHub release, listed after the feed's entries (D6 decided); the per-ayah tafsir link in the translation view was not built (the ayah menu reaches the sheet there).
- **Research result (2026-11-26):** `https://quran.app/data/translations.php?v=5` lists 79 entries,
  11 of them Arabic tafsirs as ordinary translation entries (Muyassar id 64, Ibn Kathir 58, Sa'di 59,
  Jalalayn 92, Mukhtasar 113, Baghawi 60, Qurtubi 61, Tabari 62, Tanweer 63, Waseet 95, I'rab 99), so
  `TranslationsParser` keeps every entry, so Arabic tafsir should already download and show through
  Translations and the "Translation/Tafseer" mode (verified in the simulator 2026-11-26: it shows inline).
  There is no English or Bengali tafsir in the feed (English and Bengali entries are translations only),
  so those need a `Tools/` pack pipeline and a place to host the packs (owner decision D6, §7).
- Research step: whether `/data/translations.php` (`Domain/TranslationService/Sources/TranslationNetworkManager.swift:12`)
  already lists tafsir databases (the Android client's endpoint is shared; UNVERIFIED for iOS).
  If yes, reuse `TranslationService`'s download and storage path with a tafsir type. If not,
  build packs with a `Tools/` script from QUL or Quran.com API v4 into the same SQLite shape,
  with source ids and hashes.
- Starting set (verify availability, then pick): Arabic Al-Muyassar; English Ibn Kathir
  (abridged); Bengali Ahsanul Bayaan or Abu Bakr Zakaria. Tafsir entries cover ayah ranges;
  show the whole range and say so.
- UI: ayah menu "Tafsir" opens a native sheet (pack picker, Dynamic Type, RTL for Arabic,
  next/previous ayah); translation view shows a tafsir link per ayah. No new reader engine.
- Accept: download, offline read, delete, range-keyed lookup tests, large-text layout, VoiceOver.

### F2 — Backup and restore (was M3.4)

- **Status (2026-11-26): shipped** (trail [2026-11-26-f2-backup-restore.md](../trail/2026-11-26-f2-backup-restore.md)).
  Settings > Backup & Restore in the no-sync build; JSON `com.nulltup.memquran.backup` schema 1; records are
  identified by natural keys (notes by verse set, pages by mushaf and page, collections by ID then name),
  since only collections have IDs. Preferences and downloads are not backed up.

- Versioned JSON of every user-authored record (notes, highlights, page bookmarks, collections,
  last pages; later H-records as they ship), with schema version and app version.
- Import: validate fully before writing, preview counts, explicit merge or replace, merge is
  idempotent by record id, replace is atomic, unknown newer schema refused, corrupt input
  refused without touching data. Export via the share sheet; import via the document picker.
- Accept: round trip on real-shaped fixtures, repeated import does not duplicate, interrupted
  import leaves data unchanged, no network.

### C2 — Word study

- **Status (2026-11-26): slices (a) and (b) shipped** (trail
  [2026-11-26-c2-word-study-sheet.md](../trail/2026-11-26-c2-word-study-sheet.md)): `Tools/build-quran-morphology.py`
  maps all 77,432 canonical words (2:181, 8:6 and 13:37's `بَعْدَ مَا` split into two words) into a bundled 5.9 MB
  `quran_morphology.db` (no surface-form index: nothing reads one yet); `WordStudyService`; a word sheet from a tap on
  a word in the translation view's word-by-word Arabic. **Slice c1 shipped** (trail
  [2026-11-26-c2-word-occurrences.md](../trail/2026-11-26-c2-word-occurrences.md)): Root and Dictionary form rows
  open a paged occurrence list; an occurrence opens its study and moves the reader behind the sheet, and dismissing
  returns it; the whole و list (9,594) pages under 250 ms per page off the main actor. **Slice c2 is next:**
  tap-to-hear and a word pointer entry.
- Shared tool `Tools/build-quran-morphology.py` (promote Arabican L5's `Tools/learning/morphology.py`
  approach to all 114 suras: QAC v0.4 `quran-morphology.txt` at `8f38b39`, mapped onto M1's
  canonical word ids) → bundled read-only `quran_morphology.db`: segments, root, lemma, POS,
  person/gender/number, verb form, case, mood; indexes by root, lemma, surface form. Every word
  maps or is listed as an exception; no guessed grammar.
- `WordStudyService` (Domain) reads it; word sheet from a word tap in the translation view and
  the page word pointer: Arabic, meaning (EN/BN), transliteration, segments, grammar in plain
  words, root and lemma with Quran-wide counts, occurrence list (paged, cancellable) that jumps
  to the ayah and returns.
- Tap-to-hear a word: plays the Afasy recording between the word's timings, labeled as an
  excerpt of a recitation (connected speech).
- Accept: known examples (e.g. 1:2 `ٱلۡحَمۡدُ`, root ح م د counts match QAC), coverage report,
  no main-thread hitch on common roots (measure).

### H1 — Learning store and MemorizationService (with H2's first slice)

- Core Data model `Quran 4` (lightweight migration, tested from `Quran 3`): `PracticeSession`,
  `RecallEvidence` (word or ayah id, outcome: correct / mistake / hint / revealed / skipped /
  self-corrected; assistance level; provenance manual or model; session id; tombstone),
  `MemorizedRange` (declared, with date), `Passage` (user-editable split of memorized ranges).
- `MemorizationService`: evidence reducer (idempotent, dispute-aware), passage state
  (unassessed, learning, weak, strong; declared vs demonstrated kept apart), scheduler protocol
  with FSRS or ladder implementation, seeded sampler, clock injected. Pure tests for every rule.
- D1 matters here: new SwiftUI screens are far simpler on iOS 17 (Observation). Ask before H2.

### H2 — Practice mode (2–3 slices)

- Slice a: ayah menu and range selection → "Practice"; page view masks words using the existing
  word frames (`WordFrameService`) so the printed layout never moves; tap a word or ayah to
  reveal; next-word / next-ayah peek; first-letter cue (ArabicScript graphemes); progressive
  masking levels; per-ayah self-grade; mark a word as a mistake; exit restores the reader.
  VoiceOver never reads hidden words.
- Slice b: listen-and-repeat over the existing audio pipeline (reference play, pause scaled to
  ayah length, repeat), cumulative steps (A, B, A+B, C, A+B+C) as presets; session resume
  after kill.
- Slice c: translation-view practice (hide Arabic, optional meaning cue: "understand while
  memorizing"), line and page practice by canonical boundaries.

### H3 — Memorization map and review queue

- Declare what is already memorized quickly (by surah, juz, page range); juz → surah → ayah map
  with state colors plus text labels; due queue of passages with reason ("weak 3 sessions",
  "due 2 days"); Sabaq/Sabqi/Manzil buckets with daily budgets; skip, reschedule, reset with
  confirmation. Review opens H2 on the passage.

### H4 — Spot tests

- Sources: memorized ranges, custom ranges, presets (Warm up, Weakest, Due, Recent, Old).
  Random start with seeded sampler, question length in ayahs or lines, count or timer,
  start cue, hidden location option. Manual reveal and grade; hint and skip recorded.
- Scores: strict (error-free unassisted questions), word recall, coverage, assistance; no score
  when the denominator is zero. Temporary tests never change history.

### H5 — Similar verses

- Data: QUL's similar-ayah and mutashabihat datasets (verify) cross-checked with our own n-gram
  index over normalized canonical tokens; disagreements reviewed and recorded, like Arabican L6's
  tajweed cross-check. Bundled read-only.
- Compare sheet: side-by-side RTL with differing words marked by underline and color, jump and
  return, play each; optional inline marker on the page. Drills: choose the right continuation,
  complete the ending; confusions saved as evidence for H3/H7.

### P1 — Private iCloud sync

- Turn on the existing `NSPersistentCloudKitContainer` path for the Core Data store in the
  shipping build; audit the model against CloudKit rules (the M3.1 follow-up's `MO_Collection`
  uniquifier lands here); dedupe on read. Downloads, caches and derived state never sync.
- Owner steps (D3): iCloud capability and container, then production schema deployment after
  the first build (release-testflight.md#icloud-and-cloudkit-schema). Verify on two devices.

### H6 — Goals and planning

- Goals by activity (read, listen, memorize, review) with fixed or flexible workload, deadline
  or none, weekday schedule; Khatmah plans with replanning that keeps history; presets (Friday
  Al-Kahf, Ramadan Khatmah, 7-part week). Activity time counts only visible, active reading and
  actual playback, with idle cutoff. Home shows Today: continue reading, due review, goal
  progress. Local reminders only after D5.

### H7 — Mistake history and repair

- Word and ayah heatmap overlay from evidence across sessions (explicit, tested decay policy;
  one count per word per session); detail sheet (history, confirm, dispute, remove, note);
  repair queue that drills the weak passage, not isolated words. Overlay never mixes with
  tajweed or similar-verse markers.

### V0 — Voice feasibility spike

- Candidates in order of reuse: Apple `SpeechTranscriber` (iOS 26 `Speech` framework; present in
  the iOS 27.2 SDK, Arabic on-device support UNVERIFIED, check `supportedLocales` on the
  device); Tarteel's published Quran Whisper models through a Core ML runtime (WhisperKit or
  equivalent; new dependency, D4). Reuse Arabican L5's `AyahRecorder` learnings.
- Benchmark from consented family recordings (owner provides): voice-search top-1/top-k,
  word error rate, latency p50/p95, memory, battery; correct and deliberately wrong recitations.
  Output: go/no-go per V milestone, numbers in the trail.

### V1–V3 — Voice search, live follow, mistakes

- V1: Search tab mic button, top-k ayah candidates with context, disambiguation, cancel; no
  recording kept.
- V2: streaming alignment with the practice range as a soft prior; reveal and advance in H2;
  manual override; mic indicator always visible.
- V3: omission, substitution, insertion, skipped ayah, with grace for self-correction; strict,
  guided, forgiving, silent policies; confirmed events feed H7 with model provenance; dispute
  recomputes. Ship only if V0's gates pass on held-out recordings.

### C3, P2, M2

- C3: per-ayah translation comparison; formatted share (Arabic, translation, reference);
  search scoped by surah or juz, recent searches.
- P2: widgets (continue reading, today's review), App Intents (open ayah, resume, start review),
  Spotlight; no mistake details on the lock screen.
- M2: as specified in v1 (resource packs with manifests, never reuse timings across recordings).

## 7. Owner decisions

| ID | Question | Needed by | Recommendation |
|---|---|---|---|
| D1 | Raise the Quran app's minimum iOS from 15 to 17 (Arabican's) | H2 | Yes: new practice UI on Observation, fewer fallbacks; only devices older than iPhone XS lose updates |
| D2 | Allow swift-fsrs (already pinned for Arabican) in the root package | H1 | Yes: same vetted pin, shared by both apps |
| D3 | iCloud capability and CloudKit schema deployment | P1 | Yes when H1's schema is in |
| D4 | Microphone permission; recognizer runtime dependency; consented family recordings | V0 | Decide after H4 ships |
| D5 | Notification permission for goal reminders | H6 | Optional |
| D6 | Where English and Bengali tafsir packs live: bundled in the app, a GitHub release of this repo, or fetched per ayah from Quran.com API v4 | C1 (English, Bengali) | **Decided 2026-11-26:** GitHub release asset `tafsir-packs-1` (owner chose it; Ibn Kathir 169, Ahsanul Bayaan 165) |
| — | Dual-language meanings; word meanings follow the app font size; M2 downloads | open since v1 | unchanged |

## 8. Old IDs to new IDs

| v1 (2026-11-24) | Research (Q) | v2 |
|---|---|---|
| M1 | — | M1 (shipped) |
| M2 | Q16 part | M2 (blocked) |
| M3.1 | Q1 part | M3.1 (shipped) |
| M3.2 | Q1 | F1 |
| M3.3 | Q1, Q2 | H1 |
| M3.4 | Q1, Q15 part | F2 |
| M4 | Q3, Q4 | H2, H3 |
| — | Q5 | H4 |
| M5 | Q16 part | C2 (+ C1 tafsir, new) |
| M6 | Q6 | H5 |
| M7 | Q7, Q8 part | H6 |
| M8 | Q16 part | R1, C3 |
| M9 | Q9, Q10 | V0, V1 |
| M10 | Q11 | V2 |
| M11 | Q12, Q13 | V3, H7 |
| M12 | Q15 | P1 |
| M13 | Q16 part | parked (vocabulary review after H3 if asked) |
| M14 | Q16 part | P2 |
| M15 | Q14, Q17 | parked (P3) |
| — | Q8 | H7 |
| — | Q0 | this document |

## 9. Cross-cutting rules (unchanged from v1, condensed)

- Canonical Quran text is immutable; identities are riwayah + surah + ayah + word, independent
  of edition page numbers. Fail closed on uncertain mappings.
- No fabricated data: every meaning, grammar label, tafsir and similarity comes from a recorded
  source. No mastery from listening, page dwell or unstable recognition. Assisted and unaided
  recall are different evidence.
- IO, decoding and inference off the main actor; bounded caches; no full-corpus loads at launch.
  Measure launch and page turns when touching them.
- Native UI from NoorUI; Dynamic Type, VoiceOver (hidden text never leaks), RTL, Dark, Reduce
  Motion, iPad size classes; color never the only signal.
- Both sync modes compile and pass; TestFlight stays no-sync until P1 decides otherwise
  (P1 uses iCloud, not Quran.com sync).
