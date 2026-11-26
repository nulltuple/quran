# Arabican L4: vowels, marks, unseen-word checks and placement

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [Arabican L3](2026-11-26-arabican-l3-literacy-audio-tracing.md),
  [Arabican L2](2026-11-25-arabican-l2-engine-profiles-practice.md); spec
  `Documentation/ArabicLearning/03-spec-roadmap-risks.md` §5 (L4 row)

App: **Arabican** only (`ArabicLearning/`, `Tools/learning/`). No QuranEngine path changed.

## Context

The owner asked to "continue with the remaining work" from the handoff and to mark each milestone done in the spec.
L4 scope (spec §5.2): literacy U4–U7 (short vowels, long vowels, marks, decoding) and a placement test. Exit gate:
unseen-item assessments for each unit, no transliteration on assessments, placement unlocks by evidence → internal alpha.

## Decisions

- **Unit checks are skills, made by the compiler.** A unit with `check = true` gets a lesson `u<N>.check` after its last
  lesson that teaches `check.<unit>` and requires every skill the unit teaches except explanations and tracing
  (`with_unit_checks` in `Tools/learning/compile.py`). The next unit's first lesson requires the check, so checks gate
  progress with the existing planner and mastery code. A check exercise is the exercise of a random required skill,
  built in check mode, and scores only the check skill (`Exercise.scoring`). The planner asks a new check 5 times
  (`SessionPlanner.checkItems`), enough to master it in one session.
- **"Unseen" means check words are never shown in practice.** `[quran] check_suras` (93, 95, 96, 98–102, 104–107, 109:
  504 words) are a pool only checks use; practice keeps suras 1, 94, 97, 103, 108, 110–114 (210 words). The
  generator also drops a check word whose text a practice word writes (common words such as هُوَ appear in both).
  Caveat: if L5's Quran bridge teaches one of the check suras, its words stop being unseen; pick bridge suras from
  the practice list or move them.
- **No transliteration in checks.** Check mode plays a letter's name instead of showing `findLetterNamed`'s
  transliterated name, skips alif's text sound prompt, tracing and explanations
  (`ReadingExerciseTests.test_everyUnitCheckAsksUnseenItemsWithoutTransliteration`).
- **Decoding without word audio.** No offline recording of whole Quran words exists yet (L5), and I cannot listen to
  concatenated letter clips to judge them, so I did not splice syllables into words. Decoding exercises test the
  sound of a real word's first syllable both ways (hear it → pick the word; see the word → pick the recording) with
  the existing Antura letter × vowel clips, and marks are tested by eye ("Which letter has a shaddah?").
  Whole-word decoding by ear is a follow-up for L5's recitation audio.
- **Word reading stages are computed in Swift, once.** `ArabicScript.ReadableWord` labels each grapheme with the
  features a reader needs (short/long vowel, sukun, shaddah, tanwin, the alif after fathatan, alif wasla, sun lam,
  silent letter, hamzah seat, ta marbutah) and rejects words with anything U4–U6 don't teach (pause signs, iqlab
  meem, small waw/ya). `ReadingStage` (ExerciseKit) admits words per unit. Of the 714 compiled words, stage counts
  (prototype count, before the silent-letter fix): short 13 practice / 14 check, long 22 / 71, marks 147 / 334.
- **Two encoding facts of the KFGQPC Hafs text, found while building this** (both fixed in `ArabicMark`, regression
  tests in `ReadableWordTests`):
  - U+0656, U+0657 and U+065E are the **staggered tanwin** (kasratan, fathatan, dammatan), not long-vowel or
    recitation marks: 95:4 `تَقۡوِيمٖ`, 94:6 `يُسۡرٗا`, 93:4 `خَيۡرٞ`. Classified `.tanwin` now.
  - U+0652 (ARABIC SUKUN) is **not a sukun** here: it appears only on ا/و/ي (3,722 / 255 / 11 times) and is drawn as the
    small rounded zero of a letter that is written but never read (103:3 `ءَامَنُواْ`). The sukun is U+06E1 (37,147).
    Seen in the simulator: `وَعَمِلُواْ` was offered as a sukun word with its silent alif as the answer. U+0652 is now
    `.recitation`, and ReadableWord marks those letters `silentLetter`.
- **Silent-letter spotting covers every unread letter.** `mark.spot.silentLetter` asks "Which letter is written but not
  read?" and uses a word only when exactly one letter is unread when the word is read alone: a sun lam, a letter
  under the rounded zero, or alif wasla after a prefix (`ReadableWord.isSilent(at:)`). Word-initial alif wasla and
  the alif after fathatan are read when the word stands alone, so they don't count.
- **Placement is the unit checks in order.** `PlacementTest` asks `check.U2`, `check.U3`, ... up to 4 items each,
  passes a unit at 3 right answers (early), stops when 3 are out of reach; a skip is not right. Passing a unit
  places the learner past it and every unit before it. A `placement` table (progress migration `v2 placement`) keeps
  unit → date. `PlacementMastery` treats every skill of a placed unit as mastered unless the learner practiced it
  after the placement. Placement answers are real attempts on the check skills (evidence and FSRS cards). The entry
  point is a secondary button on the Practice start screen; it can be retaken (later placements only add).
- **Sight → sound needs a new exercise kind.** `Exercise.Kind.audioChoice` shows numbered play buttons; a tap plays and
  selects, Check submits (answered with `.choice`). Reuses `NoorSystemImage.play`; no new SF Symbol.
- **Owner preference "cut scope":** no syllable-blending audio, no word building, no new audio import (the 49 deferred
  Antura clips stay deferred), no form identification inside words (find-in-word on unseen words is U3's check).

## Trade-offs

- **Complexity added:** Swift sources 30 → 33 files, 2,715 → 3,485 lines: `ReadableWord` (176), `ReadingExercises`
  (232), `Placement` (103); tests 14 → 17 files (+`ReadableWordTests`, `ReadingExerciseTests`, `PlacementTests`).
  Tools: `compile.py`/`validate.py` +69/−18 lines. Content: 4 units, 13 authored lessons + 6 generated checks (40 lessons,
  233 skills), 12 orientation texts, schema 3 (`quran_word_ref.pool`). DB 296 KB → 420 KB (+504 check words).
  New persisted state: the `placement` table (user data; migration + test). 15 new strings.
- **New failure modes:** a check skill with no generator for its required skills (covered by a test over 60 seeds
  per check); a learner stuck behind a check they keep failing (checks are ordinary skills: weak-skill practice
  brings them back, and their required skills are reviewed by FSRS).
- **Who benefits / how often:** every learner from U4 on. **Likely rarely used:** placement (once per learner, only
  readers who can already decode); it costs `PlacementTest` + overlay (~100 lines), one table and one button.
  The silent-letter and tanwin-alif rules matter on almost every Quran page.
- **Rejected:** per-unit authored assessment content (more TOML to review, same machinery); synthetic evidence for
  placed skills (would fabricate attempts); a separate check-word table (one column does it); concatenating letter
  clips into words (unverifiable by me, likely wrong for sukun clips); highlighting a letter inside a word
  (colouring part of a joined Arabic word risks breaking its shaping, UNVERIFIED).
- **Ongoing cost:** a teacher must review 13 lessons, 12 explanations and the stage rules; check suras must stay out
  of practice.

## Changes

- `ArabicScript`: `ReadableWord` + `ReadingFeature` (new); `ArabicMark` kinds for staggered tanwin and U+0652.
- `Tools/learning/compile.py`: schema 3, `READING_SKILLS` (`vowel.listen/read.*`, `mark.spot.*`, `decode.words.*`),
  `with_unit_checks`, `check_suras` and the `pool` column; `validate.py`: check lesson ids, coverage of reading skills.
- `Tools/learning/content/curriculum.toml`: units U4–U7 (`check = true` on U2–U7), 13 lessons, 12 orientation topics;
  u3.l01 now requires `check.U2`.
- `LearningModel`: `WordLetters.pool`, `Curriculum.checkRequirements`. `LearningContentStore`: schema 3, reads `pool`.
- `ExerciseKit`: prompts `listenForSyllable`, `readSyllable`, `wordStartingWithSound`, `firstSoundOfWord`,
  `markInWord`; kind `audioChoice`; check mode; `ReadingExercises.swift`.
- `LearningEngine`: `PlacementTest`, `PlacementMastery`; `SessionPlanner.plan(placements:)`, `checkItems`.
- `LearningPersistence`: migration `v2 placement`, `placements()`, `recordPlacement(units:at:)`.
- `LearningUI`: `PracticeViewModel.startPlacement()`, placement summary, new prompts and `audioChoice` in
  `ExerciseView`, Progress uses the placement overlay; strings in `Localizable.xcstrings`.
- iPhone and iPad share every change (one universal target); no `#if` or idiom checks.

## Tests

- `ReadableWordTests` (9): stages on real words, sun vs moon lam, staggered tanwin and the alif after it, hamzah seats,
  ta marbutah, rejected marks, silent letters (regression: `test_theRoundedZeroMarksASilentLetterNotASukun` fails on the
  old code, where `ArabicMark.sukun.kind == .sukun` and no `silentLetter` existed; established by reading the diff).
- `ReadingExerciseTests` (5): syllable listening/reading, mark spotting (exactly one right grapheme, practice words,
  stage), decoding (one right answer, both directions), every unit check (60 seeds each: check words only, never a
  text seen in practice, no transliterated prompt or option).
- `PlacementTests` (5): pass/fail rules, early exits, every unit, overlay vs later practice, planner skips placed units
  and asks a check 5 times.
- `PracticeViewModelTests` +2: a reader who passes every check places past U1–U7 (18 items) and has nothing new; a
  beginner who skips is not placed and starts at U1.
- `LearningPersistenceTests` +2: placements per unit; a v1 progress file migrates and keeps its evidence and log.
- Tools: `compile.test.py` 26 → 30 (check lessons, check pools, untaught reading skill, overlapping suras).

## Validation

- **Verified:**
  - `make test-arabican`: all 7 bundles passed: ArabicScriptTests `Executed 18 tests, with 0 failures`,
    ExerciseKitTests `Executed 27 tests, with 0 failures`, LearningContentTests `Executed 8 tests, with 0 failures`,
    LearningEngineTests `Executed 15 tests, with 0 failures`, LearningModelTests `Executed 4 tests, with 0 failures`,
    LearningPersistenceTests `Executed 6 tests, with 0 failures`, LearningUITests `Executed 12 tests, with 0 failures`:
    90 tests.
  - `make build-arabican`: `Build Succeeded`.
  - `make test-tools`: exit 0; `compile.test.py` `Ran 30 tests ... OK`, `audio.test.py` `Ran 8 tests ... OK`,
    `strokes.test.py` `Ran 3 tests ... OK`, package pins `5 passed, 0 failed`.
  - `make format-lint`: `0/1122 files require formatting`.
  - Simulator (iPhone 18 Pro, iOS 27.2): Learn lists the check lessons; Practice shows the placement button; placement
    opens on a listening U2 check; with placement rows for U1–U5 seeded into the app's progress file, a session went
    to U6 (sukun explanation, syllable choice with the sukun option, numbered recording choice with Check and
    feedback tint, sukun spotting in a Quran word); Progress (dark) shows U1–U5 mastered.
- **Not verified:**
  - Audio audible on a device; the order and loudness of recordings in `audioChoice`.
  - Articulation of the clips (risk 2) and the correctness of 12 explanations and the stage rules (needs a teacher).
  - iPad split view, landscape, large Dynamic Type, VoiceOver on the new screens (the recording buttons have labels
    "Sound 1"… and a selected trait; not heard with VoiceOver).
  - A real placement passed by ear end to end in the app (unit-tested through `PracticeViewModel` only).

## Release

- **Commit:** pending
- **Pushed:** pending
- **TestFlight:** pending
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Whole-word decoding by ear with recitation audio and word timings (L5), and revisit check suras vs bridge suras.
- Tracing lessons (u3.l11–13) still block u3.check through the linear next-lesson rule; a VoiceOver learner cannot
  trace (skips are unscorable), so they cannot reach U4 except by placement. Make tracing optional (L7 accessibility).
- The Quran font draws isolated ya (ي) without dots, as Uthmani script does; next to ى-like shapes it may confuse
  beginners in letter choices (seen in the simulator). Consider the teaching font for isolated letters.
- U+06E0 (silent at continuation, read at a pause: `أَنَا۠`) and the remaining marks stay unsupported until T1.
- VoiceOver/Dynamic Type smoke check (open since L2) now includes the audio-choice, mark and placement screens.
