# Quran roadmap progress and session handoff

The live status of [quran-prioritized-roadmap.md](quran-prioritized-roadmap.md). Every session that
works on the roadmap updates this file in the same commit as its code. A new session starts here:
read **Handoff** first, then the trail entries it names.

Statuses: `not started`, `in progress`, `blocked`, `verified` (tests pass locally, not yet
released), `shipped` (pushed to `origin/main` and uploaded to TestFlight). A milestone is `shipped`
only when every work item is, and its exit criteria are met; device checks the owner must do are
listed under **Owner checklist**, not counted as done.

## Handoff

- **Last updated:** 2026-11-25, Claude Code / claude-opus-5-5.
- **Current slice:** M3.1 (no-sync data audit and local verse collections store). Trail:
  [2026-11-25-m3-1-local-verse-collections-store.md](../trail/2026-11-25-m3-1-local-verse-collections-store.md).
  The audit (which stores and features exist without sync) is in its **Context**.
- **State of the tree:** M3.1 shipped at `88b60523` (TestFlight build 961); tree clean, nothing in
  progress. Tests at that commit: no-sync 1,422 passed, sync 1,916 passed.
- **Owner decisions so far:** M2 skipped for now (2026-11-25). Local collections go in Core Data, not
  MobileSync, and the TestFlight build stays no-sync (2026-11-25).
- **M1 overall:** every work item is shipped except dual-language meanings (owner decision) and
  the device checks in the **Owner checklist**.
- **To resume in a new session:** "Continue the roadmap from
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
- **Next steps, in order:**
  1. **M3.2: collection screens in the no-sync build.** Goal: in TestFlight, the ayah menu's Bookmark
     action opens the collection editor (`BookmarkAyahsBuilder`), and the Bookmarks tab lists Favorites
     and user collections (`BookmarkCollections*`, `AyahSet*`), all stored by the M3.1 service. Steps:
     (a) add `collectionPersistence` to `AppDependencies` (`Features/AppDependencies/Sources/AppDependencies.swift`),
     `Container` and `AppDependenciesFake`, and an `ayahBookmarkCollectionService()` for no-sync next to
     the sync one (`AppDependencies.swift:109`); register a `MO_Collection` uniquifier only if needed;
     (b) a no-sync highlight service with `MobileSyncAyahHighlightService`'s API (`setHighlight`,
     `removeHighlight`, `highlightsSequence`, `removeAllHighlights`) over `NoteService`, keeping a note's
     text when its highlight is removed (read `NoteService.swift` first); (c) un-gate the collection
     screens and gate off only reading bookmarks, `syncNow` and `SyncSignInNudge`; (d) decide with the
     owner what the no-sync Bookmarks tab shows: page bookmarks stay, so the likely shape is the sync
     build's collections list plus a page-bookmarks section (ask; do not guess). Run both sync modes:
     the sync build must not change.
  2. M3.3: versioned records for memorization/practice (only what M4–M6 need), then M3.4 JSON backup.
  3. Owner decisions pending (ask, do not guess): dual-language meanings; whether word meanings
     follow the app's translation font size instead of system Dynamic Type; M2 when the owner is ready
     to download QUL recitations.
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
| M3.2 | Collection screens and Bookmark action in the no-sync build | not started | needs a no-sync highlight service over `NoteService` with `MobileSyncAyahHighlightService`'s API; reading bookmarks and sync parts gated off | |
| M3.3 | Versioned local records for memorization, goals, sessions (minimal schema for M4–M6) | not started | | |
| M3.4 | JSON backup export/import with preview and merge/replace | not started | | |
| M4–M15 | | not started | | |

## Blocked

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