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

- **Last updated:** 2026-11-26 (third session), Claude Code / claude-opus-5-5.
- **Roadmap v2 (2026-11-26):** [quran-prioritized-roadmap.md](quran-prioritized-roadmap.md) now
  reconciles v1 (M1–M15) with Codex's Tarteel research (stored at
  [research/2026-11-26-tarteel-competitive-research.html](research/2026-11-26-tarteel-competitive-research.html)).
  New area-based IDs (F, R, C, H, V, P); §8 maps old M and Q ids. Trail:
  [2026-11-26-quran-roadmap-v2.md](../trail/2026-11-26-quran-roadmap-v2.md).
- **State of the tree:** C1 (Arabic tafsir sheet) at `2688bda9`: Quran TestFlight build 988 (1.20.3); Arabican
  build 988 (shared NoorUI change). Tests at that commit: no-sync 1,475 (1,474 passed; one intermittent crash in
  `CoreDataLastPageUniquifierTests/test_merge_removingOverflow`, which passes alone and on the parent commit),
  sync 1,954 passed, Arabican 117 passed. Trail:
  [2026-11-26-c1-tafsir-sheet.md](../trail/2026-11-26-c1-tafsir-sheet.md).
- **Owner decisions so far:** M2 skipped for now (2026-11-25). Local collections go in Core Data, not
  MobileSync, and the TestFlight build stays no-sync (2026-11-25). Licensing does not restrict reuse
  (2026-11-25). Roadmap v2 order: reader and comprehension before Hifz, Hifz before AI (agent
  decision under the owner's 2026-11-26 brief "be opinionated and reorder").
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
  - The simulator's Quran app has Sahih International and Arabic Muyassar downloaded and selected (C1 check),
    is in Translation/Tafseer mode, and was left on Mushaf "Madani 1441" (R1 check); switch back to Hafs 1405
    in Settings > Choose Mushaf if a check needs the default edition.
  - To inspect a remote zip without downloading it, list it with HTTP range reads (Python `zipfile` over a
    seekable ranged-GET file object; the R1 trail, Research, describes it).
  - Only the iPhone 18 Pro Max simulator (AGENTS.md "Simulator"); never run two package test runs
    at once (no-sync, then sync, then Arabican if a shared module changed).
- **Next steps, in order** (roadmap v2 §5):
  1. **F2 backup and restore** (roadmap v2 §6 F2): versioned JSON of notes, highlights, page bookmarks,
     collections and recent pages (all Core Data in no-sync; `Data/CoreDataPersistence`, the M3.1 and F1
     trails list the stores), export through the share sheet, import through the document picker with a
     preview, merge or replace. Start by reading the M3.1 audit in
     [2026-11-25-m3-1-local-verse-collections-store.md](../trail/2026-11-25-m3-1-local-verse-collections-store.md).
  2. Then C2 word study (roadmap v2 §6).
  3. C1 remainder: English and Bengali tafsir wait on owner **D6** (sources listed in the C1 trail's
     Follow-ups: Quran.com API v4 ids 169, 165, 166, ...). Optional: keep tafsirs out of the translation picker.
  4. Before H1/H2, ask the owner D1 (minimum iOS 17) and D2 (swift-fsrs in the root package).
  5. Open from R1: IndoPak has no verified pack (blocked); optional carry-over of the reading position by
     ayah when switching editions.
- **Inputs a rebuild needs** (none are in git; `Tools/build-qul-word-data.py` docstring has usage):
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
| C1 | Tafsir sheet and Arabic tafsir packs | shipped (Arabic; English/Bengali blocked on D6) | ayah menu "Tafsir" (page and translation modes) opens a sheet: tafsir picker, passage range and Quran text, next/previous skipping the passage; 11 feed tafsirs (`Translation.tafsirIDs`). Tests: `QuranTextDataServiceTafsirTests` (5), `TafsirViewModelTests` (6), `TafsirPreferencesTests` (3), `AyahMenuStudyRowsTests` (2), `versesReferencing` (1), ayah menu (+2); simulator: 2:1 → 2:2 with Muyassar | 2688bda9, build 988 |
| F2 (M3.4) | JSON backup export/import with preview and merge/replace | verified | Settings > Backup & Restore (no-sync): JSON schema 1, preview counts, merge (idempotent by natural key) or replace (one save). Tests: `CoreDataBackupPersistenceTests` (13), `BackupServiceTests` (10), `BackupViewModelTests` (6); simulator: export → Files → restore preview → merge | |
| C2 | Word study: full-Quran morphology, occurrences, tap-to-hear word | not started | Arabican L5 pipeline covers Juz Amma only | |
| H1 (M3.3) | Learning store (`Quran 4`) and `MemorizationService`, with H2a | not started | owner D1, D2 | |
| H2 | Practice mode: page masking, hints, grading, listen-and-repeat, cumulative | not started | | |
| H3 | Memorization map and passage review queue | not started | | |
| H4 | Spot tests with strict and granular scores | not started | | |
| H5 | Similar verses and confusion drills | not started | | |
| P1 | Private iCloud sync over the existing `NSPersistentCloudKitContainer` path | not started | owner D3 | |
| H6 | Goals, Khatmah, activity time, today's plan, reminders | not started | owner D5 for reminders | |
| H7 | Mistake history heatmap and repair queue | not started | | |
| V0 | Voice feasibility spike | not started | owner D4 | |
| V1–V3 | Voice search, live follow, mistake detection | not started | gated on V0 | |
| C3 | Translation compare, formatted share, search filters | not started | | |
| P2 | Widgets, App Intents, Spotlight | not started | | |

## Blocked

- **English and Bengali tafsir (C1):** not in the Quran.app feed. Owner decision **D6**: which source
  (Quran.com API v4 lists English Ibn Kathir Abridged 169, Ma'arif 168; Bengali Ahsanul Bayaan 165, Abu Bakr
  Zakaria 166, Ibn Kathir 164) and where packs are hosted.
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
