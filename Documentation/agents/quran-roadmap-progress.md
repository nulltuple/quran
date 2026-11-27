# Quran roadmap progress and session handoff

The live status of [quran-prioritized-roadmap.md](quran-prioritized-roadmap.md). Every session that
works on the roadmap updates this file in the same commit as its code. A new session starts here:
read **Handoff** first, then the trail entries it names.

Milestone ids follow roadmap v2 (2026-11-26); §8 of the roadmap maps the old M ids.

Statuses: `not started`, `in progress`, `blocked`, `verified` (tests pass locally, not yet
released), `shipped` (pushed to `origin/main` and uploaded to TestFlight). A milestone is `shipped`
only when every work item is, and its exit criteria are met; device checks the owner must do are
listed under **Owner checklist**, not counted as done.

## Handoff

- **Last updated:** 2026-11-27 (ninth session), Claude Code / claude-opus-5-5. This session did **V0 slice (b)**: recited
  words aligned to canonical `Word`s with frame timing (trail
  [2026-11-27-v0-word-alignment.md](../trail/2026-11-27-v0-word-alignment.md)). The eighth session shipped V0 slice (a),
  the on-device recitation engine (trail [2026-11-26-v0-recitation-engine.md](../trail/2026-11-26-v0-recitation-engine.md):
  research table, runtime findings, benchmarks, per-use recommendation; read it before V0 work). The seventh session
  completed C2 (trail [2026-11-26-c2-tap-to-hear-and-pointer-entry.md](../trail/2026-11-26-c2-tap-to-hear-and-pointer-entry.md));
  earlier C2, F2 and C1 trails are linked from the milestone table.
- **Roadmap v2 (2026-11-26):** [quran-prioritized-roadmap.md](quran-prioritized-roadmap.md) now
  reconciles v1 (M1–M15) with Codex's Tarteel research (stored at
  [research/2026-11-26-tarteel-competitive-research.html](research/2026-11-26-tarteel-competitive-research.html)).
  New area-based IDs (F, R, C, H, V, P); §8 maps old M and Q ids. Trail:
  [2026-11-26-quran-roadmap-v2.md](../trail/2026-11-26-quran-roadmap-v2.md).
- **Roadmap v3 order (owner, 2026-11-26):** C2 → V0 Quran AI Engine → V1 voice search → H1+H2 → V2 → H3–H5 →
  H7 foundation + V3 → remaining (P1, H6, H7 completion, C3, P2, M2). V1–V3 are committed objectives; V0 is not a
  go/no-go spike. Roadmap §5 and §6 V0; trail
  [2026-11-26-quran-roadmap-v3-order.md](../trail/2026-11-26-quran-roadmap-v3-order.md).
- **State of the tree:** V0 (a) at `c061ba9b` (Quran and Arabican TestFlight build 1001; tests there: no-sync 1,591/1,591, sync 2,070/2,070, Arabican 117/117, all passed). The
  model is not in git: `make recitation-model` builds `.cache/recitation-model/TilawiFastConformerInt8.mlpackage`
  (Python 3.12 via `uv`, ~1 GB); without it `CoreMLRecitationModelTests` skip. Then **minimum iOS 27.2** for both apps
  at `3a955eea` (Quran and Arabican build 1003; no-sync 1,591/1,591, sync 2,070/2,070, Arabican 117/117). Before V0,
  C2 c2 at `9047de22` (build 999).
- **Owner decisions so far:** M2 skipped for now (2026-11-25). Local collections go in Core Data, not
  MobileSync, and the TestFlight build stays no-sync (2026-11-25). Licensing does not restrict reuse
  (2026-11-25). Roadmap v3 order (owner, 2026-11-26; replaces v2's "Hifz before AI"). **D1 decided (2026-11-27):
  minimum iOS 27.2 for both apps** (trail [2026-11-27-minimum-ios-27-2.md](../trail/2026-11-27-minimum-ios-27-2.md));
  no availability checks or fallbacks for 27.2 or earlier (AGENTS.md, Identity and branding). **Open: D7** (roadmap §7), where
  the 125 MB Core ML recitation model is downloaded from (proposal: a `recitation-model-1` GitHub release asset of
  `nulltuple/quran`); V0 (c) on a device and V1 need it. **D4 approved (2026-11-26):**
  microphone permission, evaluating and integrating local inference dependencies, downloading publicly available
  models and evaluation datasets; family recordings optional, never blocking. D6 (2026-11-26): English Ibn
  Kathir (169) and Bengali Ahsanul Bayaan (165), hosted as the `tafsir-packs-1` GitHub release of
  `nulltuple/quran`; publishing further release assets for new packs follows the same approval.
- **To resume in a new session:** "Continue the Quran roadmap from
  Documentation/agents/quran-roadmap-progress.md, starting with the first item under Next steps."
  Read AGENTS.md (this repo's CLAUDE.md), then this Handoff, then the trails it names.
- **Gotchas:**
  - `make build-example-sync` rewrites `Package.resolved` with the MobileSync pins; main keeps
    the no-sync form. Run `git checkout -- Package.resolved` after it and stage paths explicitly
    (never `git add -A`), or the release script refuses to upload.
  - `make preview` needs the `build-ios-apps` Codex plugin, which is not installed. To look at a
    SwiftUI view, render it with `ImageRenderer` from a temporary test that writes PNGs to the
    scratchpad, then delete the test (M1.4 trail, Validation).
  - Test counts: `make test-*` prints one `Executed N tests` line per target; read the total with
    `xcrun xcresulttool get test-results summary --path <the .xcresult the log names>`.
  - Every new `Localizable.strings` key must be in all 16 catalogs: `LocalizationCatalogTests` fails otherwise
    (F2's first full run did).
  - `make release-testflight-*` refuses a dirty tree: commit, or set in-progress files aside, before releasing.
    Package test runs compile at their start, so don't edit Swift while a `make test-*` chain runs.
  - The simulator's Quran app also has English Ibn Kathir downloaded and selected in the reader (C1 EN/BN check),
    and a `Quran Backup 2026-11-26.json` in Files (F2 check).
  - The simulator's Quran app has Sahih International and Arabic Muyassar downloaded and selected (C1 check),
    is in Translation/Tafseer mode, and was left on Mushaf "Madani 1441" (R1 check); switch back to Hafs 1405
    in Settings > Choose Mushaf if a check needs the default edition.
  - To inspect a remote zip without downloading it, list it with HTTP range reads (Python `zipfile` over a
    seekable ranged-GET file object; the R1 trail, Research, describes it).
  - Taps inside the reader's content must not block the page's UIKit long press (ayah menu): use
    `simultaneousGesture(TapGesture())`, not `onTapGesture` (C2 trail, Decisions).
  - The simulator's Quran app has word-by-word meaning set to English (C2 check). After the C2 c2 check it is on
    Mushaf Hafs 1405 with the word pointer on, in Arabic (page) mode.
  - `make build-example-no-sync` builds for a device (`Debug-iphoneos`); to try a change in the simulator use
    `make run-example-no-sync`, which builds for the simulator and installs it. To read the app's logs (swift-log to
    stderr), relaunch it with `xcrun simctl launch --console-pty <udid> com.nulltup.memquran > <file>` in the background.
  - A simulated tap within ~0.5 s of a pointer release used to be dropped (the spring animation blocked touches); the
    release animation now allows interaction. Taps on the reader's page also go to `QuranView`'s bar-toggling tap
    recognizer: overlays that need a tap should be `UIControl`s (a button wins over an ancestor's tap recognizer).
  - V0: ONNX Runtime's GitHub repos and iOS pod host are gone or broken (since about 2026-11-17); Core ML float16 compute
    gives `<unk>` on the CPU (the simulator's only Core ML device), so the model computes in float32. The Python env for
    `Tools/recitation-model.py` must be 3.12 with the pinned `torch==2.7.0` (coremltools 9 is untested with newer torch).
    `VerseMatcherRecitationTests` takes ~50 s in a debug build (350 identifications; allowance 300 s); don't run model
    benchmarks while a test suite runs (CPU contention trips the 60 s per-test limit).
  - Only the iPhone 18 Pro Max simulator (AGENTS.md "Simulator"); never run two package test runs
    at once (no-sync, then sync, then Arabican if a shared module changed).
- **Next steps, in order** (roadmap v3 §5):
  1. **V0 slice (c)** (roadmap §6 V0; slice (b) trail Follow-ups). Dev-only microphone screen behind a debug setting
     (`AVAudioEngine` → 16 kHz → `RecitationRecognizer.identifyVerses` and `alignWords`), microphone usage string (D4
     approved), device benchmarks (latency, memory, energy) by the owner; the model on a phone needs D7. Also: the Whisper
     comparison (stopped after 15 min on 350 clips; rerun `eval --backend whisper --n 20`), find the CPU float16 fault so
     the Neural Engine can run float16, overlapping windows, phoneme model (`obadx/muaalem-model-v3_2`).
  2. **V1 — offline voice search** as soon as V0's baseline engine works (roadmap §6 V1–V3).
  3. Before H1/H2, ask the owner D2 (swift-fsrs in the root package; D1 is decided: iOS 27.2). H1 must add its
     learning records to F2's backup (schema 2, `Data/BackupPersistence`, cost-register row) and carry evidence
     provenance (manual or model) from V0's findings.
  4. Open from R1: IndoPak has no verified pack (blocked); optional carry-over of the reading position by ayah when
     switching editions.
  5. Small optional follow-ups: native review of agent translations (F2's 24 `backup.*` keys, C2's 17
     `word_study.*` keys); the C2 translation-view landing of a navigated verse at ~45% (under a medium sheet,
     `UI/NoorUI/Sources/Features/Quran/QuranScrollingViewModifier.swift:103`); teacher review of `Grammar.strings`; keep tafsirs out of the reader's translation picker;
     more tafsir packs (Bengali 166/164, English 168) with `Tools/build-tafsir-pack.py`; Arabican's
     `Tools/learning/morphology.py` could read the shared `quran_morphology.db`.
- **Inputs a rebuild needs** (none are in git; `Tools/build-qul-word-data.py` docstring has usage):
  - Word study morphology: QAC v0.4 `quran-morphology.txt` from
    `https://raw.githubusercontent.com/mustafa0x/quran-morphology/8f38b39016824284f9ed16ae15069ff9102c4acf/quran-morphology.txt`,
    sha256 `742bfac59941b2cb09736d5b7aae694af50792261fb8450cbf6afafcc340645f`; then
    `python3 -I Tools/build-quran-morphology.py <it> Example/QuranEngineApp/Resources/quran_morphology.db` and copy the
    result to `Domain/TestResources/Sources/test_data/` (the two copies must match; the output is reproducible, sha256
    `691564dc80a202b8daf8ec71b07435ff5de33d3ff1416262cc2201afed97a99b`).
  - Tafsir packs: `python3 -I Tools/build-tafsir-pack.py download 169 169.json` (and 165), then `build` and
    `zip` (docstring); the 2026-11-26 downloads' sha256 are in the C1 English/Bengali trail.
  - QUL recitation 411 SQLite, sha256 `3167adb2290dc137cfa594381a4051f5480bf3dfe646efd81d5e35cac86eb79b`
    (owner's `~/Downloads/surah-recitation-mishari-al-afasy.db.zip`).
  - QUL English wbw (translation 92), sha256 `7eb453613a199760a5c8e7b607999ac198ba7babb7c94fed47acecd2aba4b1ed`
    (`~/Downloads/english-wbw-translation.db.zip`).
  - QUL Bengali wbw (translation 94), sha256 `c7b46f28464ba80053f4e7c228f242897eddc45ce9a605ef73efb478fde85b4f`.
    The downloaded copy is gone (it lived in a cleared scratchpad); re-download it signed in to QUL
    and check the hash before rebuilding.
  - Quran.com words: `python3 -I Tools/fetch-quran-com-words.py download raw.json` then
    `normalize raw.json words.json`; the 2026-11-24 output had sha256
    `6eed196dd28585a8a734d42f0886e317a28c686c19548efa9082d0492fc4c13d` (6,236 ayahs, 77,429 words).

## Milestones

| ID | Work item | Status | Evidence | Commit / build |
|---|---|---|---|---|
| M1.1 | Canonical word identity and exact page-image mapping | shipped | 6,236/6,236 ayahs mapped from Quran.com KFGQPC v1 glyph codes (was 6,233 by width heuristic); heuristic agreed on all 6,230 ayahs both covered; QUL vs Quran.com English agree on 77,257/77,429 words, all 172 differences are wording of the same word (`those who(believe)`/`who`) plus one (`Mighty`/`Grave`, 18:5). `make test-tools` checks | 68a7fe6e, build 955 |
| M1.1 | Resolve the 6 translation-view and 3 image exceptions | shipped | 15:7, 27:20, 36:22, 37:130, 37:164, 41:47 regrouped by letter-level alignment (`uthmani_tokens`); 13:37, 37:130, 38:26 now mapped; 11:13 differs by one spelling (`ٱفۡتَرَىٰهُ`/`افْتَرَاهُ`), boundaries unchanged | 68a7fe6e, build 955 |
| M1.1 | Every word has English, Bengali, transliteration | shipped | 77,432/77,432/77,432/77,432; 2:181, 8:6, 13:37 realigned (QUL translations skip a word that QUL's recitation and Quran.com have) | 68a7fe6e, build 955 |
| M1.1 | Recitation segment cleaning | shipped | 451 out-of-order trailing segments, 32 outside the ayah, 15 stray leading, 3 inverted dropped; 21 late ayah starts corrected (e.g. 6:80 started 18 s late); 372 words have no segment of their own and keep the previous word highlighted | 68a7fe6e, build 955 |
| M1.2 | Word pointer on the unified data, legacy `words.db` retired | shipped | equivalent on all 8,454 glyphs `words.db` translated (24 wording differences, no identity differences); pointer now covers 6,236 ayahs (was 857) and follows the Bengali/English choice; preferences unchanged | 68a7fe6e, build 955 |
| M1.3 | No stale word after seeks (repeats, stepping) | shipped | `Player` drops times until its seek completes (`PlayerTests`) | 68a7fe6e, build 955 |
| M1.3 | Time observer only for reciters with word timings | shipped | `AudioRequest.reportsPlaybackTime` (`QuranAudioPlayerWordTests`) | 68a7fe6e, build 955 |
| M1.3 | Pause, speed, verse/range repeat, delays, stop, page change | shipped (unit-verified) | existing `QuranAudioPlayerWordTests`, `AudioPlayer` delay tests, `ContentRecitedWordTests`; by-ear timing UNVERIFIED (owner checklist) | 6597d965, build 951 |
| M1.3 | Manual scroll stops word-following until next ayah | shipped (unit-verified) | `ContentRecitedWordTests`; device feel UNVERIFIED | 6597d965 |
| M1.4 | Localization of the 14 remaining languages | shipped | `menu.word_by_word` in 14 catalogs and the reciter name in 12 `Readers.strings` (`tr`/`zh` have none); `testWordByWordStringsAreTranslatedInEveryLocalization`. Agent translations, native review UNVERIFIED | b664d566, build 957 |
| M1.4 | VoiceOver, Dynamic Type, RTL, iPad split view checks | shipped (view-verified) | fixed: at AX sizes a long meaning widened the ayah to 747 pt in a 320 pt column, now wraps (`QuranWordByWordTextTests`); word cells read Arabic then meaning, recited word reads as selected; RTL/Dark/AX5 checked by rendering the view. On-device VoiceOver and the app in split view UNVERIFIED (owner checklist 8–9) | b664d566, build 957 |
| M1.5 | Transliteration line in the translation view | shipped | off-by-default toggle (More menu, translation mode, meanings on); Arabic, italic transliteration, meaning; `ContentTranslationWordByWordTests`, `MoreMenuWordByWordTests`, `QuranWordByWordTextTests`, `WordByWordServiceTests` | cc0e776d, build 959 |
| M1.5 | Dual-language meanings (English and Bengali together) | blocked | owner decision: not built unless asked; doubles rows per word | |
| M2 | More synchronized reciters and resource packs | blocked | needs owner QUL downloads (**Blocked**) | |
| M3.1 | Audit of no-sync stores and sync-gated features | shipped | audit in the M3.1 trail entry: no-sync has notes, 5-color highlights, page bookmarks, recent pages (Core Data); verse collections, Favorites and named reading bookmarks are sync-only (MobileSync) | 88b60523 |
| M3.1 | Local verse collections store (Favorites + user collections), no login | shipped (no UI yet) | Core Data model `Quran 3` (lightweight migration from `Quran 2` tested), `CoreDataCollectionPersistenceTests` (11), `PersistenceAyahBookmarkCollectionServiceTests` (12); same API as the sync `AyahBookmarkCollectionService` | 88b60523, build 961 |
| F1 (M3.2) | Collection screens, Favorites and Bookmark action in the no-sync build | shipped | Bookmarks tab: My Collections + Page Bookmarks; ayah menu Bookmark row opens the collection editor; highlights stay note-based without sync (decision in the F1 trail). Tests: `LocalBookmarkCollectionsTests` (5), `AyahMenuLegacyViewModelTests` (+2), `LocalQuranAnnotationsObserverTests` (2). Page marks for collected ayahs not yet (follow-up) | c6406c8c, build 983 |
| F1 follow-up | Collection and note marks in the no-sync translation view | shipped | the ayah-number capsule shows ★ and note icons without sync, as in sync (the mushaf page marks only reading bookmarks, in both builds); a highlight alone gets no note icon. Tests: `VerseOverlaysCollectionIndicatorTests` (3), `AyahIndicatorTests` (2), `LocalQuranAnnotationsObserverTests` (+2), `NoteTests` (+1 no-sync), 3 translation tests un-gated; simulator: `2:2 \| ★` | 2fa15c38, build 986 |
| R1 | Mushaf editions via verified `ReadingRemoteResources` | shipped (IndoPak blocked) | Hafs 1421, 1439, 1440, 1441 and Tajweed from `files.quran.app` (paths, sizes, sha256, contents in the R1 trail); `QuranAppReadingRemoteResourcesTests` (4); simulator: 1441 downloaded and rendered. IndoPak: no verified pack | f1c4aa6b, build 986 |
| C1 | Tafsir sheet and Arabic tafsir packs | shipped (Arabic) | ayah menu "Tafsir" (page and translation modes) opens a sheet: tafsir picker, passage range and Quran text, next/previous skipping the passage; 11 feed tafsirs (`Translation.tafsirIDs`). Tests: `QuranTextDataServiceTafsirTests` (5), `TafsirViewModelTests` (6), `TafsirPreferencesTests` (3), `AyahMenuStudyRowsTests` (2), `versesReferencing` (1), ayah menu (+2); simulator: 2:1 → 2:2 with Muyassar | 2688bda9, build 988 |
| C1 (EN/BN) | English Ibn Kathir and Bengali Ahsanul Bayaan tafsir packs | shipped | owner D6: GitHub release `tafsir-packs-1` (packs built by `Tools/build-tafsir-pack.py` from Quran.com API v4 ids 169, 165); `Translation.supplementaryTafsirs` appended to the feed. Tests: `build-tafsir-pack.test.sh` (12), `TranslationsRepositoryTests` (+3); simulator: Ibn Kathir downloaded, 2:8–9 passage in the sheet | d4d1bd55, build 992 |
| F2 (M3.4) | JSON backup export/import with preview and merge/replace | shipped | Settings > Backup & Restore (no-sync): JSON schema 1, preview counts, merge (idempotent by natural key) or replace (one save). Tests: `CoreDataBackupPersistenceTests` (13), `BackupServiceTests` (10), `BackupViewModelTests` (6); simulator: export → Files → restore preview → merge | 34ce5a47, build 990 |
| C2 (a, b) | Full-Quran morphology database and word study sheet | shipped | `Tools/build-quran-morphology.py`: all 77,432 canonical words, 130,030 segments, 1,651 roots, 4,783 lemmas (2:181, 8:6, 13:37 `بَعْدَ مَا` split); ح م د 68, حَمْد 43 as QAC. Translation view word tap → sheet: segments, grammar in plain words, root and lemma counts. Tests: `build-quran-morphology.test.sh` (31), `WordStudyServiceTests` (8), `WordStudyFeatureTests` (8), `QuranWordByWordTextTapTests` (4), translation and content (+4); simulator: 1:1 ٱلرَّحْمَٰنِ sheet, long press still opens the ayah menu | f03021d8, build 994 |
| C2 (c1) | Occurrence list that moves the reader and returns | shipped | Root and Dictionary form rows open a paged list (50 per page, off the main actor; whole و list of 9,594 under 250 ms per page); an occurrence opens its study and moves the reader (`WordStudyReaderFollower`, `ContentViewModel.navigate(to:)`); dismissing returns it. Tests: `WordOccurrencesViewModelTests` (6), `WordStudyReaderFollowerTests` (4), `WordStudyViewModelTests` (+2), `ContentViewModelTests` (+1); simulator: ر ح م → 2:64 → Back → 1:1, رَحْمٰن → 19:18 → dismiss → 1:1 | 657f3385, build 996 |
| C2 (c2) | Tap-to-hear word, word pointer entry | shipped | Hear row plays the word's excerpt of the Afasy (1001) sura recording with its own `AVPlayer`, streamed unless downloaded, pausing the main recitation; the Mushaf pointer keeps a released word's popover 4 s and a tap opens its study. Tests: `WordRecitationRetrieverTests` (6), `WordStudyHearingTests` (6), `WordPointerViewModelTests` (+5), `WordTextServiceTests` (+2), `ByPassTouchesViewTests` (2); simulator: 1:1 streamed, 3:2 word 6 from the pointer | 9047de22, build 999 |
| V0 (a) | Recitation engine (Core ML), verse identification, benchmarks | shipped | Tilawi FastConformer CTC → Core ML int8 (125 MB, not bundled; `make recitation-model`); `RecitationRecognition` module. 350 EveryAyah clips, 7 reciters: top-1 350/350, CER 0.67% (≤20 s clips), 26 ms p50 per clip (M4 Pro); Swift matcher 350/350, 0 confident-wrong. Tests: `RecitationRecognitionTests` (25), `GRDBVerseTextPersistenceTests` (+1), `recitation-model.test.sh` (22) | `c061ba9b`, build 1001 |
| V0 (b) | Recited words aligned to canonical words, with frame timing | verified (no build: module not linked yet; ships with (c)) | `WordAligner` + `ExpectedWordsReader` (Uthmani tokens via `WordByWordService.textLayouts`); 350 transcripts: 4,218/4,305 words matched (97.98%), each word once and in order; Husary 112:1 audio → 4 matched words with ordered frames. Tests: `WordAlignerTests` (10), `RecognizedWordTests` (4), `ExpectedWordsReaderTests` (4), `WordAlignerRecitationTests` (1), `CoreMLRecitationModelTests` (+3) | |
| V0 (c) | Dev microphone screen and device benchmarks | not started (next) | model on a phone needs D7 | |
| V1–V3 | Voice search, live follow, mistake detection | not started | committed objectives; V1 follows V0's baseline engine | |
| H1 (M3.3) | Learning store (`Quran 4`) and `MemorizationService`, with H2a | not started | owner D1, D2 | |
| H2 | Practice mode: page masking, hints, grading, listen-and-repeat, cumulative | not started | | |
| H3 | Memorization map and passage review queue | not started | | |
| H4 | Spot tests with strict and granular scores | not started | | |
| H5 | Similar verses and confusion drills | not started | | |
| P1 | Private iCloud sync over the existing `NSPersistentCloudKitContainer` path | not started | owner D3 | |
| H6 | Goals, Khatmah, activity time, today's plan, reminders | not started | owner D5 for reminders | |
| H7 | Mistake history heatmap and repair queue | not started | | |
| C3 | Translation compare, formatted share, search filters | not started | | |
| P2 | Widgets, App Intents, Spotlight | not started | | |

## Blocked

- **IndoPak Mushaf (R1):** no verified public pack on `files.quran.app` (every `naskh/`, `indopak/` guess
  404s; the Android naskh page provider is not public). Needs a source the owner trusts.
- **More synchronized reciters (M2):** QUL downloads need the owner's signed-in browser. Needed:
  QUL recitations with word segments whose audio the app can stream (QUL lists 59 "With
  segments"); which match the app's existing quranicaudio.com recordings is UNVERIFIED.

## Owner checklist (TestFlight, physical device)

Run on TestFlight build 959 or later, reciter "Mishary Al-Afasy (word by word)":

1. Play 1:1–1:7 at 1x: the highlight follows each word by ear; turn word-by-word meaning to
   English, then Bengali, in both the page and translation views.
2. Set verse repeat 3x with a 1x delay on 2:255: on each repeat the first word lights first, with
   no flash of the ayah's last word.
3. Range 37:125–37:132 repeated twice: 37:130's third word (`إِلۡ يَاسِينَ`) highlights as one
   word on the page; in the translation view it shows "Elijah" under both parts.
4. Play 6:79–6:81: 6:80's highlight starts with its recitation (it was 18 s late).
5. Speeds 0.75x and 1.5x on 2:282 (a long ayah): the page scrolls to follow the word; drag the
   page mid-ayah and it stops following until the next ayah.
6. Word pointer (page view): drag over 2:181 and 13:37 (ayahs `words.db` lacked): each word shows
   its meaning; pause marks show none; switch the pointer to transliteration.
7. Lock the phone during playback for 10 minutes with another reciter, then the word-by-word one:
   battery use looks normal in Settings > Battery.
8. VoiceOver on, translation view, word-by-word English: swipe through 1:2; each word reads its
   Arabic (in an Arabic voice) then its meaning; during playback the recited word says
   "selected".
9. Largest accessibility text size (Settings > Accessibility > Display & Text Size), word-by-word
   on, iPad in split view and an iPhone SE-size phone: every ayah stays on screen, long meanings
   wrap. Then switch the app to German, Russian and Chinese: the More menu shows a translated
   "Word-by-word meaning" title.
10. Translation view, word-by-word English, More menu: a "Transliteration" switch appears under
    "Word-by-word meaning" (not in page mode, not with meanings off); turn it on: each word shows
    an italic transliteration between the Arabic and the meaning (e.g. 2:2 `dhālika`).
11. Install build 961 over build 959 or earlier with notes, highlights and page bookmarks saved:
    after the update all of them are still there (the store migrated to model `Quran 3`).
12. F1 (build 983 or later): long-press an ayah, tap Save Ayah..., tick Favorites, close:
    the menu shows a filled star for that ayah; the Bookmarks tab shows Favorites with 1, then your page
    bookmarks under "Page Bookmarks". Create, rename and delete a collection; tap Edit with page bookmarks:
    Delete All asks about page bookmarks only. Check VoiceOver on the Bookmarks tab and the largest text size.
13. F1 follow-up (build 986 or later): save an ayah to Favorites and write a note on another; in
    Translation/Tafseer mode the first ayah's number capsule shows a star, the second a note icon; an ayah
    that is only highlighted shows neither. Check VoiceOver reads "Collections" / "Notes" after the number.
14. R1 (build 986 or later): Settings > Choose Mushaf shows Uthmani and Tajweed tabs (no IndoPak).
    Pick each of Hafs 1421, 1440, Madani 1439, Madani 1441 and Tajweed in turn: each downloads (52–144 MB)
    with a progress bar, then a page renders with ayah markers; turn on airplane mode and the chosen edition
    still opens; switch back to Hafs 1405. Try killing the app mid-download and reopening.
15. C1 (build 988 or later): with no tafsir downloaded, long-press an ayah on the Mushaf page, tap Tafsir: the
    sheet says no tafsir is downloaded; Download a Tafsir opens the translations list; download Arabic Muyassar
    Tafseer and close it: the sheet shows the ayah and its tafsir. Go to 2:45 (Muyassar explains 2:45–46
    together): the sheet says "Al-Baqarah 2:45–46" and that one explanation covers them; the next arrow goes to
    2:47. Download Ibn Kathir too: a picker appears; the choice is kept after closing. Try Dark mode, the
    largest text size and VoiceOver.
16. F2 (build 990 or later): Settings > Backup & Restore > Export Backup, Save to Files. Delete one note, then
    Restore from Backup, pick the file: the preview counts match; Merge brings the note back and nothing is
    duplicated (run Merge twice). Then try Replace on a second device or after adding a new bookmark: the new
    bookmark is gone, the backup's records are there. Try a non-backup .json file: an error, nothing changes.
17. C1 English/Bengali (build 992 or later): Settings > Translations lists "English Ibn Kathir Tafseer (Abridged)"
    under English and "Bengali Ahsanul Bayaan Tafseer" under Bengali; download both (7 and 4 MB). Long-press 2:8,
    Tafsir: pick each; Ibn Kathir shows "Al-Baqarah 2:8–9" and one explanation; Bengali shows 2:8 alone. Check the
    Bengali text at the largest text size, and with airplane mode on after downloading.
18. C2 word study (build 994 or later): open Al-Fatihah in Translation/Tafseer mode, More menu > Word-by-word
    meaning > English. Tap ٱلْحَمْدُ in 1:2: a Word Study sheet shows al-ḥamdu, its meaning, "Prefix · Definite article",
    "Noun · masculine · nominative", Root ح م د (68) and Dictionary form حَمْد (43). Long-press a word: the ayah menu
    still opens. Try 2:3's يُؤْمِنُونَ (Verb · form IV · imperfect …), Bengali meanings, Dark mode, the largest text
    size, VoiceOver (each word reads as a button with a hint), and an iPad in split view.
19. C2 occurrences (build 996 or later): in the Word Study sheet for 1:2's ٱلْحَمْدُ, tap Root ح م د: a list of 68
    words in Quran order, each with its meaning and "Sura, Ayah n, word n". Tap one in another sura: its study opens,
    the sheet drops to half height and the reader behind it moves to that ayah (it may sit just under the sheet; drag
    the sheet down). Tap Back: the reader returns to 1:2. Open Dictionary form, pick a word, then swipe the sheet away:
    the reader returns to 1:2. Scroll a long list fast (Root أ ل ه from اللَّهِ, 2,851): no stutter while pages load.
    Try VoiceOver (rows read meaning, place and Arabic; Root and Dictionary form say they list every word) and an
    iPad in split view.
20. C2 tap-to-hear and pointer entry (build 999 or later): in the Word Study sheet for 1:1's ٱلرَّحْمَٰنِ, tap "Hear the
    word": you hear that word alone (it may carry a little of the next sound), and the note says it streams. Try a long
    word (2:255 ٱلْقَيُّومُ), one word several times in a row, and airplane mode (a red "could not be played" note; tap
    again after reconnecting). Start a recitation from the banner, open a word study and tap Hear: the recitation pauses
    and resumes from the banner. Download Al-Fātiḥah for "Mishary Al-Afasy (word by word)" in Settings > Audio: the
    streaming note disappears and Hear works offline. Mushaf page (Hafs 1405), More menu > Word translation pointer on:
    drag the pointer over a word and let go: its meaning stays for about 4 seconds with a book symbol; tap it: Word
    Study opens for that word. Let go over a pause mark or blank space: nothing stays. Try VoiceOver on the Hear row.
21. V0 slice (a) (build 1001 or later): nothing to try on the device yet (no screen uses the engine). Decide D7 (roadmap
    §7): where the 125 MB recitation model is downloaded from, so slice (c) can run it on your phone.
22. Minimum iOS 27.2 (build 1003 or later): the build installs on a phone with iOS 27.2 or later (it no longer offers to
    install on older iOS). Open More menu > Word-by-word meaning and Word translation pointer: the pages sit on the
    popover's glass as before.
