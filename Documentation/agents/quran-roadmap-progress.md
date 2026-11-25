# Quran roadmap progress and session handoff

The live status of [quran-prioritized-roadmap.md](quran-prioritized-roadmap.md). Every session that
works on the roadmap updates this file in the same commit as its code. A new session starts here:
read **Handoff** first, then the trail entries it names.

Statuses: `not started`, `in progress`, `blocked`, `verified` (tests pass locally, not yet
released), `shipped` (pushed to `origin/main` and uploaded to TestFlight). A milestone is `shipped`
only when every work item is, and its exit criteria are met; device checks the owner must do are
listed under **Owner checklist**, not counted as done.

## Handoff

- **Last updated:** 2026-11-24, Claude Code / claude-opus-5-5.
- **Current slice:** M1.1–M1.3 (canonical word data, unified word pointer, media-clock fixes).
  Trail: [2026-11-24-m1-canonical-word-data.md](../trail/2026-11-24-m1-canonical-word-data.md).
- **State of the tree:** see the trail entry's **Release** section for the commit and TestFlight
  build. If it says "not committed", the work is in the working tree of the primary checkout:
  run `git status` and finish the definition of done from the trail entry's **Validation** list.
- **Next steps, in order:**
  1. M1.4: translate the "Word-by-word meaning" title for the 14 languages still showing English
     (catalog `Core/Localization`), VoiceOver labels on word cells (meaning plus Arabic), and
     check Dynamic Type/RTL of `QuranWordByWordText` with `make preview`.
  2. M1.5: optional transliteration line under meanings in the translation view (data now ships in
     `word_by_word.db` `word_meanings.transliteration`); dual-language display only if the owner
     wants it (cost: more rows per word).
  3. M2: additional synchronized reciters (needs QUL downloads by the owner, see **Blocked**).
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
| M1.1 | Canonical word identity and exact page-image mapping | verified | 6,236/6,236 ayahs mapped from Quran.com KFGQPC v1 glyph codes (was 6,233 by width heuristic); heuristic agreed on all 6,230 ayahs both covered; QUL vs Quran.com English agree on 77,257/77,429 words, all 172 differences are wording of the same word (`those who(believe)`/`who`) plus one (`Mighty`/`Grave`, 18:5). `make test-tools` checks | see trail |
| M1.1 | Resolve the 6 translation-view and 3 image exceptions | verified | 15:7, 27:20, 36:22, 37:130, 37:164, 41:47 regrouped by letter-level alignment (`uthmani_tokens`); 13:37, 37:130, 38:26 now mapped; 11:13 differs by one spelling (`ٱفۡتَرَىٰهُ`/`افْتَرَاهُ`), boundaries unchanged | see trail |
| M1.1 | Every word has English, Bengali, transliteration | verified | 77,432/77,432/77,432/77,432; 2:181, 8:6, 13:37 realigned (QUL translations skip a word that QUL's recitation and Quran.com have) | see trail |
| M1.1 | Recitation segment cleaning | verified | 451 out-of-order trailing segments, 32 outside the ayah, 15 stray leading, 3 inverted dropped; 21 late ayah starts corrected (e.g. 6:80 started 18 s late); 372 words have no segment of their own and keep the previous word highlighted | see trail |
| M1.2 | Word pointer on the unified data, legacy `words.db` retired | verified | equivalent on all 8,454 glyphs `words.db` translated (24 wording differences, no identity differences); pointer now covers 6,236 ayahs (was 857) and follows the Bengali/English choice; preferences unchanged | see trail |
| M1.3 | No stale word after seeks (repeats, stepping) | verified | `Player` drops times until its seek completes (`PlayerTests`) | see trail |
| M1.3 | Time observer only for reciters with word timings | verified | `AudioRequest.reportsPlaybackTime` (`QuranAudioPlayerWordTests`) | see trail |
| M1.3 | Pause, speed, verse/range repeat, delays, stop, page change | verified (unit) | existing `QuranAudioPlayerWordTests`, `AudioPlayer` delay tests, `ContentRecitedWordTests`; by-ear timing UNVERIFIED (owner checklist) | 6597d965, build 951 |
| M1.3 | Manual scroll stops word-following until next ayah | verified (unit) | `ContentRecitedWordTests`; device feel UNVERIFIED | 6597d965 |
| M1.4 | Localization of the 14 remaining languages | not started | | |
| M1.4 | VoiceOver, Dynamic Type, RTL, iPad split view checks | not started | | |
| M1.5 | Transliteration display, dual language | not started | data shipped in M1.1 | |
| M2–M15 | | not started | | |

## Blocked

- **More synchronized reciters (M2):** QUL downloads need the owner's signed-in browser. Needed:
  QUL recitations with word segments whose audio the app can stream (QUL lists 59 "With
  segments"); which match the app's existing quranicaudio.com recordings is UNVERIFIED.

## Owner checklist (TestFlight, physical device)

Run on the build named in the trail entry, reciter "Mishary Al-Afasy (word by word)":

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
