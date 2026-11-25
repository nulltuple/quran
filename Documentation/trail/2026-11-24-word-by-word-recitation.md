# Word-by-word recitation highlighting and word meanings from QUL

- **Date:** 2026-11-24
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-24 agent-only contract](2026-11-24-agentic-contract-rebrand-testflight.md)

## Context

The owner asked to "implement word by word highlighting during recitation if that feature does
not already exist", using word-annotated audio from <https://qul.tarteel.ai/resources/recitation>,
choosing between QUL's SQLite and JSON downloads "with your adversarially verified judgement";
to make "ayat range selection, repeat of each ayat and repeat of each range settings work with
word highlighting"; to have "the quran viewer ... automatically scroll as Ayat goes out of view";
and to add "an option to enable word by word meaning using Tarteel's dataset that shows small
word meaning under each word", in Bengali or English.

What existed before (verified by reading the code):

- **No word highlighting during recitation.** Playback reported ayahs only:
  `QuranAudioPlayerActions.playing(AyahNumber)` (`Domain/QuranAudioKit/Sources/AudioPlayer/QuranAudioPlayer.swift`),
  and the gapless timing database has one row per ayah (`timings(sura, ayah, time)`, read by
  `Data/AudioTimingPersistence/Sources/GRDBAyahTimingPersistence.swift`).
- **Ayah-level auto-scroll already existed**: a new playing ayah scrolls the page and moves to its
  page (`VerseOverlays.needsScrolling`, `ContentViewModel.verseToScrollTo`,
  `ContentImageViewModel.scrollToVerseIfNeeded`). It never followed a long ayah past the screen.
- **A word highlight already existed for the word pointer** (`VerseOverlays.pointedWord`,
  `ImageDecorations.wordHighlight`), drawn from page-image glyph frames.
- **The bundled `words.db` (word pointer translations) covers 857 of 6,236 ayahs, English only**
  (`sqlite3 Example/QuranEngineApp/Resources/words.db "select count(distinct sura||':'||ayah) from words"`).

QUL needs a signed-in account to download. The owner signed in through the built-in browser; I
downloaded:

| QUL resource | Formats | What it is |
|---|---|---|
| Recitation 411, "Mishari Rashid al-`Afasy", Surah by Surah, tagged Word segments (updated 2026-10-13) | sqlite and json | per-ayah `timestamp_from/to` and word segments `[word, start_ms, end_ms]`; audio at `https://audio-cdn.tarteel.ai/quran/surah/alafasy/murattal/mp3/NNN.mp3` |
| Translation 92, "English Word by Word Translation" | sqlite | `word_translation(surah_number, ayah_number, word_number, text)` |
| Translation 94, "Bengali wbw translation" | sqlite | same schema |

## Decisions

- **SQLite over JSON, verified adversarially.** Both recitation downloads hold identical data:
  a script compared all 6,236 ayahs and found 0 differences in segments and timestamps. SQLite
  wins because it answers per-sura queries without parsing the whole file (the JSON is 2.2 MB and
  must be decoded entirely, keyed `"sura:ayah"`), it is what the app's timing pipeline already
  reads through GRDB, and its word segments convert in one pass. The word-by-word translations
  were downloaded as SQLite for the same reasons.
- **Converted, not shipped verbatim.** `Tools/build-qul-word-data.py` turns the recitation into the
  gapless timing format the app already reads (`timings`, ayah 999 = sura end) plus a
  `word_timings` table, so `GRDBAyahTimingPersistence` and the gapless request builder work
  unchanged for ayah timing, range selection and repeats. The translations become
  `word_by_word.db` (`word_meanings` with English and Bengali columns).
- **A new reciter, "Mishary Al-Afasy (word by word)", id 1001**, whose audio and timings both come
  from QUL. Word timings are only valid for the exact audio they were measured on, and the app's
  existing reciters use other recordings (quranicaudio.com), so reusing QUL timings with them
  would highlight the wrong words. Checks: all 114 audio URLs answered HTTP 200; QUL's
  `surah_list.audio_url` matches `Reciter.remoteURL(sura:)` (`<base>/NNN.mp3`) for all 114; the
  downloaded `001.mp3` and `112.mp3` last 46.50 s and 13.35 s (`afinfo`), and their timing sura
  ends are 46.347 s and 13.198 s. Id 1001 sits far above upstream's reciter ids.
- **The timing database is bundled**, because QUL downloads need a sign-in the app can't do and
  the timings aren't on the audio server. `Reciter.bundledTimingDatabase` (from the plist key
  `timingDatabase`) makes `localDatabasePath` and `databaseRemoteURL` `nil`, so the existing
  download, unzip and update paths skip the database and the reciter downloads only audio.
- **The recited word follows the media clock.** `Player` adds an `AVPlayer` periodic time
  observer (every 0.1 s, only while time advances); `QuranAudioPlayer` maps the time to the last
  word started in the playing ayah. Because verse repeats, range repeats and range selection all
  work by seeking the same files, they replay the words correctly without word-specific repeat
  logic. A new or repeated ayah clears the word until its first word starts; a pause between words
  keeps the previous word; a reciter repeating a word (925 QUL ayahs do) highlights it again.
- **Page images number words differently.** In the Madani 1405 images, pause marks, ۞ and ۩ are
  glyphs of their own, so text word 7 of 2:7 is glyph 8. The tool maps text words to glyphs by
  dropping glyphs narrower than 30 px (in 1920-px units), a leading ۞ glyph, and a trailing ۩
  glyph, and keeps the mapping only where the counts agree: 6,233 of 6,236 ayahs. Upstream's
  `words.db` is an independent record (it leaves non-word glyphs untranslated): the mapping agrees
  with it on all 857 ayahs it covers. The mapping exists for `hafs_1405` only (the Example's only
  bundled reading); other readings highlight whole ayahs as before.
- **Auto-scroll follows the recited word only when it leaves the view** (`scrollTo(_, anchor: nil)`,
  which scrolls the minimum, or not at all when the word is visible). Ayah-level scrolling is
  unchanged. A reader's drag stops word-following until the next ayah starts, so playback doesn't
  pull them back mid-ayah.
- **Where meanings show.** The translation view shows every word of each ayah with its meaning
  underneath (a right-to-left wrapping flow; iOS 16+, since `WrappingHStack` needs it; iOS 15
  shows the plain text). The mushaf page image has no room to reflow text, so there the recited
  word's meaning shows in a small label under the highlighted word. Translation-view words come
  from the Uthmani text split on spaces, which matches QUL's word count in 6,230 of 6,236 ayahs;
  an ayah whose count differs (or a non-Uthmani script) shows plain text with no word highlight.
- **Menu option** "Word-by-word meaning: Off / English / Bengali" in the reader's more menu, in
  both modes. Language names come from `Locale` (for example "Bengali (বাংলা)"), so no new
  catalog strings are needed for them; the title and "Off" are new catalog keys.
- **The word pointer is unchanged.** It still reads the partial English `words.db`; switching it
  to `word_by_word.db` would give it full coverage and Bengali (see Follow-ups).
- Not made default: the reciter list is unchanged in order, and the user picks the new reciter.

## Trade-offs

- **Complexity added:** about 2,500 added lines (`git diff --numstat` +821/-70 in modified files,
  1,669 in new files, tests and this entry included) across 30-odd Swift files, one Python tool and its
  shell test, two bundled databases, and catalog lines in 16 languages (the title is English
  outside English and Arabic; "Off" reuses each language's existing `audio.delay.off`
  translation). No new dependency, permission, entitlement or background mode. New persisted
  state: one preference, `wordByWordLanguage`. New failure modes: a missing or unreadable word
  database logs and falls back to whole-ayah highlighting.
- **Binary size: +10.3 MB uncompressed** (`qul_afasy.db` 3.0 MB, `word_by_word.db` 7.2 MB;
  about 4.6 MB gzip-compressed, a rough guide to the App Store download). This is the largest
  cost. Shipping one language, or downloading the databases on demand from a server the owner
  controls, would cut it; neither exists today.
- **Runtime cost:** a 0.1 s periodic time observer while audio plays (a closure and a binary
  search per tick, a SwiftUI update only when the word changes, about 2 to 3 times a second); one
  indexed query per page for word positions and meanings; word timings for the played suras held
  in memory during playback (sura 2: 6,000-odd small structs). Not measured with Instruments.
- **Who benefits / how often:** listeners who choose the new reciter, and readers who turn on
  meanings. Usage is UNVERIFIED (no analytics). Word highlighting works with one reciter only;
  more reciters each need their own QUL word timings and another few MB.
- **Rejected cheaper options:** reusing QUL timings with the existing Afasy/Husary audio (different
  recordings, so wrong words); shipping the JSON (whole-file parse, larger); computing the glyph
  mapping at runtime (reading-specific heuristics in the app, and harder to verify than the
  offline check against `words.db`); drawing meanings under every word on the page image (no
  space between Madani lines without reflowing the page).
- **Licensing (UNVERIFIED):** QUL's licence tab for all three resources says "We don't have
  copyright information for this resource." The owner should confirm the terms before an App
  Store release.
- **Ongoing cost:** QUL fixes segments occasionally (the last fix, 2026-10-13, was surah 39);
  refreshing means re-downloading signed in and rerunning the tool.

## Changes

Data and tooling:
- `Tools/build-qul-word-data.py` builds both databases; `Tools/build-qul-word-data.test.sh` (in
  `make test-tools`) tests it on fixtures and checks the bundled outputs.
- `Example/QuranEngineApp/Resources/qul_afasy.db`, `word_by_word.db`, added to the Example
  target's resources; `reciters.plist` gains reciter 1001.
- `Domain/TestResources/Sources/test_data/qul_afasy.db` and `word_by_word.db`: subsets for tests.

Shared layers (all platforms):
- `Model/QuranAudio`: `WordTiming`, `AyahWordTimings` (word at a time); `Reciter.bundledTimingDatabase`,
  `timingDatabaseURL`; QuranAudio gets a test target.
- `Model/QuranText`: `WordByWordLanguage`. `Model/QuranAnnotations`: `VerseOverlays.recitedWord`.
- `Data/AudioTimingPersistence`: `getWordTimings(for:)`. `Data/WordTextPersistence`:
  `GRDBWordByWordPersistence`.
- `Domain/AudioTimingService`: `ReciterTimingRetriever.wordTimings` and bundled databases.
  `Domain/ReciterService`: plist `timingDatabase`; the gapless file list skips a bundled database.
- `Domain/QueuePlayer`: `Player.onTimeChanged`, `QueuePlayerActions.playbackTimeChanged`.
- `Domain/QuranAudioKit`: `QuranAudioPlayer` resolves the recited word;
  `QuranAudioPlayerActions.playingWord`.
- `Domain/WordTextService`: `WordByWordService`, `WordByWordPreferences`.

UI and features (iPhone and iPad):
- `UI/NoorUI`: `QuranWordByWordText`, `WordMeaningCaption`, `WordScrollTarget`; `QuranArabicText`
  highlights a word; `ImageDecorations.wordCaption/scrollWord`; `quranScrolling(anchor: nil)`.
- `Features/AudioBannerFeature`: forwards the word (`AudioBannerListener.highlightRecitedWord`).
- `Features/QuranViewFeature`, `QuranContentFeature`: pass it to the overlays.
- `Features/QuranImageFeature`: maps it to the page glyph, captions it, follows it.
- `Features/QuranTranslationFeature`, `TranslationVerseFeature`: word-by-word rows and highlight.
- `Features/MoreMenuFeature`: the Word-by-word meaning option.
- `Features/AppDependencies(+Fake)`, `Example/.../Container.swift`: `wordByWordDatabase`.

## Tests

- `QuranAudioTests.AyahWordTimingsTests` (new target): word at a time, pauses, repeated words,
  ordering.
- `QuranAudioKitTests.QuranAudioPlayerWordTests`: words by media time, new ayah, verse repeat,
  range repeat, playback end, reciter without word timings, bundled database needs no download
  (real QUL timings for Al-Fatiha).
- `ReciterServiceTests.ReciterDataRetrieverTests`: plist `timingDatabase`, missing resource.
- `WordTextServiceTests.WordByWordServiceTests`: English, Bengali, off, glyph mapping past pause
  marks and ۞, other readings, word counts.
- `QuranAnnotationsTests.VerseOverlaysTests.test_restricted_keepsTheRecitedWordOnlyOnItsPage`.
- `QuranContentFeatureTests.ContentViewModelTests.testRecitedWordFollowsPlaybackAndClearsWhenItStops`.
- `QuranImageFeatureTests.ContentRecitedWordTests`: glyph highlight, pointer wins, caption, reader
  scroll stops following, stop clears.
- `QuranTranslationFeatureTests.ContentTranslationWordByWordTests`: highlight, meanings, off,
  mismatched text, other page.
- `NoorUITests.ImageDecorationsLayoutTests` (caption, scroll word) and `QuranArabicTextWordTests`.
- `Tools/build-qul-word-data.test.sh`: 18 checks.

Two defects the first full run caught, both fixed before commit:

- `ContentRecitedWordTests.test_captionsTheRecitedWordWithItsMeaning` and three
  `ContentTranslationWordByWordTests` timed out: `WordByWordPreferences.$language` publishes changes
  only (`Core/Preferences/Sources/Preference.swift`, `projectedValue`), and Swift skips `didSet` in
  an initializer, so a page built after the reader turned meanings on never loaded them. Both view
  models now start from the preference's current value, and the image page loads meanings with
  its page.
- The existing `ContentDimOtherAyahsTests.test_imagePage_doesNotRedrawWhileAudioMovesBetweenVersesOfAnotherPage`
  failed (`("1") is not equal to ("0")`): resetting `followsRecitedWord` on every ayah change
  republished an unchanged value and redrew every page. It now writes only when the value changes.

## Validation

- **Verified:**
  - `make format-lint`: `0/1060 files require formatting`.
  - `make test-tools`: exit 0; `Tools/build-qul-word-data.test.sh` `18 passed, 0 failed`.
  - `make test-no-sync`: `Test Succeeded`; xcresult summary `Passed total 1361 passed 1361 failed 0`.
  - `make test-sync`: `Test Succeeded`; xcresult summary `Passed total 1867 passed 1867 failed 0`.
  - `make build-example-no-sync` and `make build-example-sync`: `Build Succeeded`; the built app
    contains `qul_afasy.db` (3,100,672 bytes) and `word_by_word.db` (7,548,928 bytes).
  - Data checks: JSON and SQLite recitation downloads identical (0 of 6,236 ayahs differ); all 114
    audio URLs HTTP 200; glyph mapping agrees with `words.db` on 857/857 ayahs.
- **Not verified:** nothing was checked by hand in the simulator. Simulator access needs the
  owner's approval in the desktop app, and the request went unanswered; a headless `simctl` run
  reached the home screen but could not tap. Still to check on a device or the TestFlight build:
  the highlight following the recitation by ear (timing feel at 1x and other rates), verse and
  range repeats with delays, the scroll following a long ayah (iPhone landscape, iPad split view),
  the caption's legibility over the page in Light and Dark, the word-by-word rows at large Dynamic
  Type and in RTL, VoiceOver on the word rows, background playback battery cost, and performance
  (no Instruments run).

## Release

- **Commit:** pending
- **Pushed:** pending
- **TestFlight:** pending
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Point the word pointer at `word_by_word.db` (full coverage, Bengali) and retire the partial
  `words.db`.
- Word timings for more reciters (QUL lists 59 recitations "With segments"; whether their
  segments are word-level for the app's existing recordings is UNVERIFIED).
- A glyph mapping for other readings (`tajweed`, `hafs_1421`, line-page readings).
- Translate "Word-by-word meaning" for the 14 languages that show English.
- Confirm QUL data licensing before an App Store release.
