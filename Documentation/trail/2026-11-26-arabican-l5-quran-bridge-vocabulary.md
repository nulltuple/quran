# Arabican L5: Quran bridge reader, record and compare, morphology and top-300 vocabulary

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped (TestFlight build 975)
- **Related:** [L4](2026-11-26-arabican-l4-reading-and-placement.md),
  [word-by-word recitation (Quran app)](2026-11-24-word-by-word-recitation.md), spec
  `Documentation/ArabicLearning/03-spec-roadmap-risks.md` §5.2 L5

App: **Arabican** only. No QuranEngine path changed (no `Core/`…`Features/`, `Package.swift` or
`Package.resolved` edits), so the Quran app's suites, builds and release are not required.

## Context

The owner asked to "continue with the remaining work" from `Documentation/ArabicLearning/HANDOFF.md`,
whose next milestone is L5: "learning-mode reader for Al-Fatihah + first short surahs (reuse the
reader's audio + `qul_afasy.db` timings), record & compare, QUL morphology ingest, top-300 lemma
ordering, word sheet", shipped as the foundational beta.

Two owner decisions were needed and asked in chat (2026-11-26):

- **Microphone permission** for record and compare: "Yes, add microphone".
- **Downloads**: "Yes, all three": the Afasy surah MP3s of the bridge suras, QAC morphology
  (`quran-morphology.txt`) and QuranicWords `dataset/words.json`.

Sources (downloaded 2026-11-26, untrusted-data directories in the session scratchpad, not in git):

| Source | Pin | SHA-256 |
|---|---|---|
| `https://audio-cdn.tarteel.ai/quran/surah/alafasy/murattal/mp3/{001,103,108,110,111,112,113,114}.mp3` | as served 2026-11-26 | listed per file in `Tools/learning/content/recitation.toml` |
| `github.com/mustafa0x/quran-morphology` `quran-morphology.txt` (QAC v0.4) | commit `8f38b39016824284f9ed16ae15069ff9102c4acf` | `742bfac59941b2cb09736d5b7aae694af50792261fb8450cbf6afafcc340645f` |
| `github.com/rmrashahriar/QuranicWords` `dataset/words.json` | commit `4fd80e1eeed1e9afc2072eaf99cee59251961186` | `7dc8a39be0810cbb759fbcefd66b1037787df622f05f624b02f2dfe578cc93f5` |

Facts verified before building:

- The bundled `Example/QuranEngineApp/Resources/qul_afasy.db` (`timings`, `word_timings`) was measured on
  exactly these MP3s (trail `2026-11-24-word-by-word-recitation.md`: QUL recitation 411; the audio URL
  is reciter 1001's `url` in `Example/QuranEngineApp/Resources/reciters.plist`). `afinfo`: all eight files
  are 128 kbit/s MP3; 001.mp3 lasts 46.50 s, its timing sura end is 46.347 s.
- QAC numbers words like `word_by_word.db` on 6,233 of 6,236 ayahs; the three exceptions are the ayahs
  `Tools/build-qul-word-data.py` realigned (2:181, 8:6, 13:37), none in Al-Fatihah or Juz Amma.
- 77,429 QAC words over 130,030 segments; 4,776 lemmas.

## Decisions

- **QAC morphology (mustafa0x/quran-morphology), not QUL's morphology downloads.** QUL needs a signed-in
  browser session; QAC is public, is what QuranicWords is derived from (so the diff is meaningful), and its
  word numbering matches ours (above). The spec's inventory rows 17 and 18 now say so.
- **Lemma glosses from QuranicWords**, matched by word class and root (or, for rootless particles, by
  normalized text) and accepted only within a factor of two of our count: QuranicWords spells some lemmas
  differently (ءَامَنَ vs QAC آمَنَ) and splits others by sense (ما "what" 1,592 and "not" 973 vs QAC 2,565),
  so a text-only match picked wrong senses (آمَنَ → "are secure", رَأَى → "immature in opinion") in a first
  attempt. 13 of the top 300 have authored glosses in `Tools/learning/content/glosses.toml` (ال, ذا, ما, أ,
  ه, ي, لَم, ن, س, أَمّا, إِذْن, قاتَلَ, خَشِيَ); they need teacher review like every lesson.
- **Counts are QAC segment occurrences** (و 9,594, ال 8,377, رَبّ 975), ranked by count then lemma text.
  The definite article stays in the list (QuranicWords drops it). Diff (`lemmas.tsv` column
  `qw_occurrences`): of the top 300, 290 match a QuranicWords entry, 7 with a different count (ل 4,380 vs
  3,847; ما; عَلَى 1,445 vs 1,444; إِذا 423 vs 383; لَمّا 165 vs 154; لٰكِن and لٰكِنّ 65 each vs 130 merged),
  10 absent (the authored ones).
- **Bridge suras: 1, 112, 113, 114, 108, 103, 110, 111** (lesson order, short and familiar first), all
  practice suras, none a check sura, so check words stay unseen (L4 constraint). Sura 94 and 97 stay
  practice-only (they exist for ظ and ز).
- **Recordings bundled byte for byte** (3.3 MB of MP3). Transcoding to AAC would add encoder priming and
  risk shifting the measured word timings; the compiler checks each file's SHA-256 against
  `recitation.toml`, so a different recording is rejected rather than mistimed.
- **Two compiler-made units**, like the unit checks: U8 Quran bridge (one lesson per sura teaching
  `bridge.listen.<sura>`, a recited word to pick by ear, and `bridge.meaning.<sura>`, a word's meaning in
  its ayah) and U9 vocabulary (`lemma.meaning.<lemma>`, 30 lessons of 10 lemmas). Both require `check.U7`
  and follow it in lesson order. Interleaving vocabulary with U4–U7 (spec §4 "introduced alongside U4
  onward") was not done: lesson order is linear (`SkillGraph.nextLesson`), and interleaving needs a
  planner change; recorded as a follow-up.
- **Word sheet** shows meaning in context (EN and BN from `word_by_word.db`), transliteration, and each QAC
  segment's part of speech, lemma gloss, dictionary form, root letters and Quran-wide count ("975 times in
  the Quran"), never a percentage (risk 8). Exercises use English only: Arabican's UI is English-only.
- **Record and compare**: one temporary file (`tmp/arabican-recording.m4a`, AAC 22 kHz mono), replaced by
  each new recording and deleted when the reader closes (`AyahRecorder.discard()`); no score; no network
  code anywhere in the recorder. The audio session switches to `.playAndRecord` only while recording.
- **No new `NoorSystemImage` case.** "Record yourself" is a text button and Stop/Play reuse `.stop`/`.play`,
  so no QuranEngine module changed and no Quran release is needed.
- **`UIx.WrappingHStack`** (QuranEngine) lays out words; under `.rightToLeft` it flows right to left
  (checked in the simulator).

## Trade-offs

- **Complexity added:** ~1,050 Swift lines in 9 new and 10 changed source files (models, store queries,
  three exercise generators, reader, word sheet, players, recorder), ~420 Python lines (`morphology.py`
  and compiler/validator additions) and ~330 test lines. Content schema 4 adds six tables
  (`lemma`, `word_segment`, `bridge`, `ayah_timing`, `word_timing`, three `quran_word_ref` columns).
  **New permission:** microphone (`NSMicrophoneUsageDescription`), owner-approved. No new dependency, no
  persisted learner state, no background work.
- **Who benefits / how often:** the reader and vocabulary are the core of the beta. **Record and compare is
  likely to be rarely used** (it needs a quiet room and a willing learner); it costs ~110 lines, a
  permission prompt and one string in Settings.
- **Rejected cheaper options:** per-word Quran.com audio (`audio.qurancdn.com/wbw`, inventory row 21) would
  need 153 more files and terms checks while the surah recordings plus QUL timings already give every word;
  a downloaded audio pack (`BatchDownloader`) would add download UI and failure states for 3.3 MB.
- **Ongoing cost:** binary +3.3 MB (recitations) and +330 KB (content DB 750 KB). Re-running
  `morphology.py` needs the two downloads (URLs and hashes above). Glosses and bridge lessons need teacher
  review.

## Changes

- Tools: `Tools/learning/morphology.py` (QAC + QuranicWords → `content/lemmas.tsv`, `content/word_segments.tsv`
  for Al-Fatihah and Juz Amma), `content/glosses.toml`, `content/recitation.toml`;
  `compile.py` (schema 4, `bridge_and_vocabulary`, `load_recitations`, `recitation_timings`, word meanings);
  `validate.py` (`validate_morphology`, `validate_timings`); `content/curriculum.toml` (`[[bridge]]`,
  `[vocabulary]`, units U8 and U9).
- Content: `ArabicLearning/Sources/LearningContent/Resources/Recitation/*.mp3`, regenerated
  `learning-content.sqlite` and manifest.
- `LearningModel/QuranBridge.swift`: `RecitationSegment`, `WordMeaning`, `BridgeWord`, `BridgeAyah`,
  `WordTiming`, `BridgeSura` (`word(at:)`, segments), `Lemma`, `WordSegment`.
- `LearningContentStore`: schema "4", `bridgeSuras()`, `lemmas()`, `wordSegments(sura:)`,
  `bundledRecitationDirectory`.
- ExerciseKit: `ExercisePrompt.listenForWord`, `.meaningInAyah`, `.meaningOfLemma`; `Exercise.recitation`;
  `BridgeExercises.swift` (generators); `ExerciseGenerator(bridges:lemmas:)`.
- LearningUI: `QuranBridgeView.swift` (sura list, `BridgeReaderView`, word sheet), `BridgeViewModel.swift`,
  `RecitationPlayer.swift`, `AyahRecorder.swift`, `ClipPlayer` plays recitation segments, `PracticeView`
  renders the new prompts, the Quran tab replaces its placeholder (and the `tab.placeholder` string).
- `ArabicLearning/Package.swift`: `Resources/Recitation`; LearningUI imports `QuranKit` and `UIx`;
  LearningModelTests imports `QuranKit` and `QuranText`.
- `Apps/Arabican/Arabican.xcodeproj/project.pbxproj`: `INFOPLIST_KEY_NSMicrophoneUsageDescription`.
- Platforms: iPhone and iPad (one universal target); no platform-specific code.

## Tests

- New: `BridgeSuraTests` (recited word through pauses and repeats, segments),
  `BridgeContentTests` (bridge order, recordings exist, every word timed inside its ayah and recited at its
  midpoint, EN/BN meanings, Fatihah end 46.347 s; lemma ranks and glosses; segments of بِسۡمِ and ٱهۡدِنَا),
  `BridgeExerciseTests` (listening answers match the played segment, meaning options distinct and unrelated,
  every top-300 lemma builds a 4-option exercise), `BridgeViewModelTests`.
- Changed: `LearningContentStoreTests` (units U1–U9), `LetterMediaExerciseTests.test_everyTaughtSkillHasAnExercise`
  (generator gets bridges and lemmas), `PracticeViewModelTests` (placement past every check now leads to the
  bridge lesson instead of nothing new).
- Tools: `morphology.test.py` (7 tests: parsing, alignment, labels, ranks/roles/glosses, sense-split rejection,
  missing gloss error); `compile.test.py` +6 (bridge/vocabulary lessons, every bridge word timed/glossed/segmented,
  rejects a non-practice bridge sura, a different recording, a word without morphology, an unglossed top lemma).

## Validation

- **Verified:**
  - `python3 -I Tools/learning/morphology.py --qac … --quranic-words …`: `130030 segments over 6236 ayahs;
    wrote 934 lemmas, 3834 segments` and `top 300: 290 found in QuranicWords, 7 with a different count,
    10 absent; 13 authored glosses`.
  - `python3 -I Tools/learning/compile.py`: `{'letters': 29, 'skills': 549, 'lessons': 78, 'quran_words': 714,
    'check_words': 504, 'lemmas': 508, 'word_segments': 1164, 'bridge_suras': 8, 'word_timings': 153, …}`.
  - `make test-arabican`: exit 0; the xcresult summary reads `result: Passed, totalTestCount: 100, passedTests: 100,
    failedTests: 0` (90 before L5). The first run failed 2 tests as expected from the new units
    (`test_everyTaughtSkillHasAnExercise` without bridge data; placement expecting nothing new after U7); both
    were updated to the new curriculum, not weakened (the placement test now asserts the bridge lesson comes next).
  - `make test-tools`: exit 0; `compile.test.py` `Ran 36 tests … OK`, `morphology.test.py` `Ran 7 tests … OK`,
    `audio.test.py` 8 OK, `strokes.test.py` 3 OK, shell suites `22/36/16/46/5 passed, 0 failed`.
  - `make build-arabican`: `Build Succeeded`. `make format-lint`: exit 0. `make guardrails`: `guardrail: ok (staged)`.
  - Simulator (iPhone 18 Pro, iOS simulator): Quran tab lists the 8 suras; Al-Fatihah and Al-Ikhlas render
    right to left with meanings; Play highlights the recited word; tapping رَبِّ plays it and opens the sheet
    (meaning EN/BN, noun, Lord, dictionary form, 975 times, root ر ب ب); Record shows the system prompt with
    the usage text; Don't Allow shows the Settings hint. I chose Don't Allow because allowing would record
    from the Mac's microphone.
- **Not verified:** recording and playback of a real recording (needs a device or an allowed mic); audio on a
  device and exact highlight sync (it looked within a few hundred ms in the simulator, not measured);
  practice screens for the three new prompts (reached only after U7; covered by generator tests, not seen);
  VoiceOver, Dynamic Type, iPad split view, landscape, Dark Mode for the reader and sheet; teacher review of
  glosses, bridge lessons and the lemma labels.

## Release

- **Commit:** `b60940de7e67d8911269fd3b713fe761a3bad41d`
- **Pushed:** origin/main at `b60940de` (`14264cdc..b60940de  HEAD -> main`)
- **TestFlight:** build 975 (0.1.0): `Uploaded Arabican iOS 0.1.0 (975) for commit
  b60940de7e67d8911269fd3b713fe761a3bad41d to App Store Connect app Arabican.`
- **iCloud / CloudKit schema:** unchanged. New permission: microphone (owner-approved 2026-11-26); no
  entitlement or capability change.

## Follow-ups

- Interleave vocabulary lessons with U4–U7 (spec §4) once the planner can offer two next lessons.
- A meaning-language preference (Bengali exercises); the data is already compiled.
- Whole-word decoding by ear for unseen check words needs recitation of check suras (keep them out of the
  reader) — deferred; U8 covers words by ear for the bridge suras.
- Accessibility pass for the reader (VoiceOver order of word buttons, Dynamic Type at XXL).
- L6 tajweed: the bridge suras now have recordings and timings to drill rules by ear.
