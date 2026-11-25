# M1: verified canonical word data, unified word pointer, media-clock fixes

- **Date:** 2026-11-24
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** in-progress
- **Related:** [roadmap](2026-11-24-prioritized-quran-roadmap.md), [word-by-word recitation](2026-11-24-word-by-word-recitation.md), progress in [quran-roadmap-progress.md](../agents/quran-roadmap-progress.md)

## Context

The owner asked to implement [the roadmap](../agents/quran-prioritized-roadmap.md) starting with
M1: "Unify the old incomplete word pointer database with the new comprehensive English/Bengali
word-by-word database", "Adversarially verify canonical word mappings rather than relying only
on matching word counts or glyph-width heuristics", "Resolve the remaining unmapped ayahs", and
"Ensure correct word highlighting across seeking, playback speed changes, pausing, individual
ayah repeats, range repeats and repetition delays". Licensing is out of scope by the owner's
instruction; sources and hashes are recorded for reproducibility.

What main had (verified by reading code and data at `4e22ab9f`):

- The word pointer read upstream's `words.db` (857 ayahs, English, 8,454 translated glyphs)
  through `GRDBWordTextPersistence`; the reader's meanings and highlights read `word_by_word.db`.
- `word_by_word.db`'s page-image mapping was inferred from glyph widths (narrower than 30 px =
  mark) and kept only where counts agreed: 6,233/6,236 ayahs (13:37, 37:130, 38:26 missing).
- The translation view split the Uthmani text on spaces and showed words only where the count
  matched QUL's: 6,230/6,236 (15:7, 27:20, 36:22, 37:130, 37:164, 41:47 missing).
- QUL's word translations skip one word in 2:181, 8:6, 13:37 (`بَعْدَ مَا` is one Quran.com word,
  two QUL words), so `word_by_word.db` shifted every later meaning in those ayahs by one word:
  2:181 word 5 showed word 4's meaning. **This was a shipped wrong mapping.**
- QUL's recitation segments were stored as given; 393 ayahs had out-of-order segments (a word's
  segment trailing the ayah) and 36 ayahs began with stray or misattributed segments (6:80's
  first words sat 18 s before its ayah start, so its highlight began 18 s late).

## Decisions

- **Exact glyph mapping from Quran.com glyph codes, not widths.** Quran.com API v4 gives every
  word's KFGQPC v1 `code_v1`, one code point per glyph of the font the Madani 1405 images were
  drawn with (a word with a pause mark has two). The sum of codes equals the `ayahinfo` glyph count
  in 6,236/6,236 ayahs, so positions follow exactly. The new mapping agrees with the width
  heuristic on all 6,230 ayahs both cover, and with `words.db` on all 8,454 glyphs it translates.
  `Tools/fetch-quran-com-words.py` downloads the data (public, no key; nothing about the user
  is sent); the output is a build input, not bundled.
- **Independent identity check.** QUL's and Quran.com's English word meanings come from the same
  source; with my alignment they agree on 77,257 of 77,429 words. All 172 differences are editorial
  (`those who(believe)` vs `who` in يَٰٓأَيُّهَا ٱلَّذِينَ ءَامَنُوٓاْ, 171 of them) plus 18:5
  word 8 (`Mighty (is)` vs `Grave (is)`), same word. No word is offset.
- **Canonical word = QUL word number** (the recitation segments and both translations use it).
  Where QUL splits a Quran.com word (`بَعْدَ مَا` = words 3 and 4 of 2:181), both words map to the
  shared glyph and the second shows the first's meaning, as `words.db` did; where QUL joins two
  Quran.com tokens (`إِلْ يَاسِينَ` in 37:130), the word maps to both glyphs and the page highlights
  both (`ImageDecorations.wordHighlightEnd`).
- **Bundled-text alignment by letters.** For the six ayahs whose Uthmani text tokenizes differently,
  the tool aligns letter skeletons (diacritics and spelling variants folded) and writes
  `uthmani_tokens`; the app joins tokens into units (`UthmaniWordLayout`). The tool fails the build
  if any other ayah's letters don't line up; 11:13 differs in one word's spelling only and keeps
  one token per word. A text that splits otherwise (another script) still shows plain text.
- **Segment cleaning rules** are written in the tool's docstring with counts printed on every run:
  invalid 3, outside 32, leading 15, backward 451, late-start 21. A genuine repetition (the reciter
  goes back and recites on, 925-odd ayahs) is kept. 372 words end up without a segment of their own;
  during them the previous word stays highlighted (no word is guessed).
- **Retire `words.db`.** After the equivalence check above, the word pointer reads
  `word_by_word.db` through `WordTextService` → `WordByWordService` (one code path for meanings).
  It covers all 6,236 ayahs, shows Bengali when the reader picked Bengali (English otherwise, its
  previous behavior), shows nothing for mark glyphs, and nothing for readings without a verified
  mapping (`Reading.supportsWordPositions` already limits it to `hafs_1405`). Preferences
  (`wordTranslationType`, `isWordPointerActive`) are unchanged.
- **Media clock.** `Player.seek` now drops periodic times until the seek completes, then reports
  the landed time: AVPlayer seeks are asynchronous, so a verse or range repeat could report the end
  of the ayah first and flash its last word. Bounded by a seek generation so a superseded seek
  can't end a newer one. The time observer is now added only when the request asks for it
  (`AudioRequest.reportsPlaybackTime`), which `QuranAudioPlayer` sets only for reciters with word
  timings; other reciters no longer wake the app ten times a second.
- **Not changed (reviewed):** pause keeps the word (no ticks while paused); speed changes keep
  media-time lookups correct (the observer interval is media time, so at 0.5x a tick is 0.2 s
  wall-clock); verse delays already suppress ticks; a late tick can't leak a word across ayahs
  because lookups use the playing ayah's own timings (new test). The gapless frame-end timer can
  move to the next ayah up to 0.2 s early, clearing the word slightly early; left as is.

## Trade-offs

- **Complexity added:** `git diff --numstat` +1,179/−370 before this entry (tool rewrite, tests,
  fixture subsets); new `Tools/fetch-quran-com-words.py` (134 lines), `UthmaniWordLayout` (69).
  Removed `GRDBWordTextPersistence`, `WordTextPersistence` protocol and `words.db`. No dependency,
  permission or entitlement. No persisted user state change.
- **Binary size:** `word_by_word.db` 7.55 → 8.39 MB (transliterations, multi-glyph rows,
  `uthmani_tokens`), `qul_afasy.db` 3.10 → 3.08 MB, `words.db` −0.46 MB: net about +0.36 MB.
- **Runtime:** pointer lookups are two indexed point queries per new word under the finger;
  meanings and layouts are one range query per page, as before. One fewer periodic observer for
  every non-word reciter (battery win for most listeners, not measured).
- **Who benefits:** pointer users get 7x coverage and Bengali; every reader of the six regrouped
  and three mis-shifted ayahs now sees correct meanings. The word pointer remains a niche feature
  (UNVERIFIED usage).
- **Rejected:** keeping the width heuristic plus a hand list of exceptions (unverifiable);
  realigning QUL translations by count alone (would hide the 2:181 shift); dropping out-of-order
  segments without the recite-on rule (would delete real repetitions); a runtime alignment in the
  app (moves verification out of the build tool).
- **Ongoing cost:** rebuilding needs the three QUL downloads (owner sign-in) plus the Quran.com
  fetch; hashes are in the progress doc.

## Changes

- `Tools/build-qul-word-data.py`: segment cleaning; exact glyph mapping; QUL alignment;
  transliterations; `uthmani_tokens`; consistency failures. `Tools/fetch-quran-com-words.py`: new.
  `Tools/build-qul-word-data.test.sh`: 46 checks.
- `Example/QuranEngineApp/Resources/word_by_word.db`, `qul_afasy.db` rebuilt; `words.db` removed
  (and from the Xcode project); `Domain/TestResources/.../word_by_word.db`, `qul_afasy.db`
  regenerated as row-exact subsets (checked by the tool test); test `words.db` removed.
- `Data/WordTextPersistence`: `GRDBWordByWordPersistence` (text by column, word at glyph, glyph
  ranges, token layout); legacy persistence removed.
- `Domain/WordTextService`: `WordByWordService.text`, `word(atImageGlyph:)`, `textLayouts`,
  `ImageWordGlyphs`; `UthmaniWordLayout`; `WordTextService` delegates to it.
- `Domain/QueuePlayer`: `Player` seek suppression and opt-in observer; `AudioRequest.reportsPlaybackTime`.
  `Domain/QuranAudioKit`: sets it.
- `UI/NoorUI`: `QuranArabicText(highlightedWords:)` (token range); `ImageDecorations.wordHighlightEnd`.
- `Features/QuranTranslationFeature`: units from `UthmaniWordLayout`; `Features/QuranImageFeature`:
  glyph spans; `Features/WordPointerFeature`: unified service and current reading.
- `Features/AppDependencies(+Fake)`, `Example/.../Container.swift`: `wordsDatabase` removed.
- iPhone and iPad alike; no platform-specific code.

## Tests

- `WordTextServiceTests`: `WordByWordServiceTests` (multi-glyph, shared glyph, word at glyph,
  marks, other reading, 2:181 realignment, text types, layouts), `UthmaniWordLayoutTests` (new),
  `WordTextServiceTests` (Bengali, 2:181 coverage, marks, other reading).
- `QueuePlayerTests.PlayerTests`: times during a seek dropped, superseded seek.
- `QuranAudioKitTests.QuranAudioPlayerWordTests`: observer opt-in, no cross-ayah leak.
- `QuranTranslationFeatureTests.ContentTranslationWordByWordTests`: 15:7 and 37:130 units.
- `NoorUITests.QuranArabicTextWordTests`: two-token highlight.
- `WordPointerFeatureTests`: on the unified database.
- Regression evidence for the 2:181 shift: `test_everyWordHasMeaningsEvenWhereTheHeuristicFailed`
  asserts word 5 = "he (has) heard [it]"; the old database gives word 4's meaning there (shown by
  query before the rebuild, see Context). The seek test was reasoned from the diff (the previous
  `Player` forwarded every tick).

## Validation

- **Verified:**
  - `bash Tools/build-qul-word-data.test.sh`: `46 passed, 0 failed`.
  - `make format-lint`: `0/1060 files require formatting`.
  - Focused `make test-no-sync TARGET=…`: `Test Succeeded` for WordTextServiceTests,
    QueuePlayerTests, QuranAudioKitTests, WordPointerFeatureTests, NoorUITests,
    QuranTranslationFeatureTests, QuranImageFeatureTests.
  - `make test-tools`: `14 passed`, `19 passed`, `16 passed`, `46 passed`, each `0 failed`.
  - `make test-no-sync`: `Test Succeeded`; xcresult summary `Passed 1385 passed, 0 failed`
    (1,361 before).
  - `make test-sync`: `Test Succeeded`; xcresult summary `Passed 1891 passed, 0 failed`
    (1,867 before).
  - `make build-example-no-sync` and `make build-example-sync`: `Build Succeeded`; both apps
    contain `word_by_word.db` (8,392,704 bytes) and `qul_afasy.db` (3,080,192 bytes), no `words.db`.
- **Not verified:** nothing was checked by hand in the simulator this session (context budget
  went to the data audit); by-ear highlight timing, VoiceOver, Dynamic Type, iPad split view and
  battery (no Instruments run) are on the owner checklist. See the owner checklist in the progress doc.

## Release

- **Commit:** `f958f5e4` feat(reader): verify canonical word data and unify the word pointer;
  then a fix commit restoring `Package.resolved`, which `f958f5e4` changed by accident (it took
  the MobileSync pins `make build-example-sync` writes; main keeps the no-sync resolution). The
  first `make release-testflight` (build 954) stopped with `HEAD or the working tree changed during
  the build ... Not uploading.` because the archive rewrote it back. Lesson: stage paths
  explicitly, never `git add -A` after a sync build.
- **Pushed:** origin/main at `f958f5e4` (`4e22ab9f..f958f5e4  HEAD -> main`), then the fix commit.
- **TestFlight:** pending
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- M1.4 localization and accessibility, M1.5 transliteration display (see progress doc).
- Rebuild the data on QUL's next segment fix (re-download the Bengali file; hash in progress doc).
