# Arabican L3: letter audio, joining forms, find-in-word and tracing

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [Arabican L2](2026-11-25-arabican-l2-engine-profiles-practice.md),
  [Arabican L1](2026-11-25-arabican-l1-content-compiler.md); spec `Documentation/ArabicLearning/03-spec-roadmap-risks.md`
  §5 (L3 row)

App: **Arabican** only (`ArabicLearning/`, `Tools/learning/`). No QuranEngine path changed.

## Context

The owner asked to continue from the handoff, to confirm that Antura was the best source for letter recordings,
and then "go ahead and just do it" (approval to download). L3 scope (spec §5.2): letters, forms, contrast
pairs, tracing (Noorine strokes), Antura audio audition and import, and tracing and find-in-word renderers.
Exit gate: an audio audition log (per file: accept/reject/reason), every letter and form covered, and the
tracing check unit-tested on stroke fixtures.

## Decisions

- **Antura is still the best letter-audio source.** Checked 2026-11-26 with GitHub searches (`qaida`,
  `arabic letters audio`) and the web. Alternatives: `TarishAhmed/qaida` ships placeholder `.opus` files
  (`app/src/debug/assets/audio/placeholder_*`); `awash-dev/qaida-noorania-flutter` has 23 lesson-length
  `.m4a` tracks (would need segmenting); `Christopher-LDC/arabic-letters-audio` has 29 letter-name mp3s
  with an empty README and no provenance; `ibr7h/al-qaida-nooraniyya` (web result) returns 404; Wikimedia
  Commons has single phoneme clips, not a set. Antura (`vgwb/Antura` at `838704bcb1ee`) is the only source
  with human recordings of **every letter's name and the letter with fatha, kasra, damma and sukun**
  (189 files, CC-BY-4.0). Its weakness (children's-game MSA narration, not a reciter) stays risk 2.
- **Audition is automated and technical; articulation is UNVERIFIED.** I cannot listen. `Tools/learning/audio.py`
  measures every file (voiced length, peak, clipping, duplicates), maps it to a clip, and writes
  `Documentation/ArabicLearning/04-audio-audition.md`: 140 accept, 0 reject, 49 defer (tanwin, shaddah,
  lam-alif, diphthongs, mark names, alif with a vowel). A qualified listener must still review the
  accepted clips (spec risk 2, still a release blocker).
- **Hamza's vowels come from hamza on an alif seat** (`alef_hamza_hi_fathah` etc.): same sound, and Antura has
  no other hamza-vowel recordings. **Alif's own vowel files are deferred**: alif carries no vowel, so the labels
  are ambiguous.
- **CAF, not M4A.** `afconvert` stamps `.m4a` files with the time, so re-running the import changed every byte;
  AAC in `.caf` is byte-for-byte reproducible (checked twice), so the compiler's sha256s stay stable.
- **Clips are trimmed and peak-normalized to -3 dBFS** so letters play at the same loudness.
- **Find-in-word uses compiler-selected words.** The compiler records, per compiled word, which letters it
  writes plainly (`exact`) and which it only implies through a spelling variant or small letter
  (ٱ أ إ آ ؤ ئ ة ى ۥ ۦ, dagger alif, small high letters: `IMPLIED_LETTERS` in `Tools/learning/compile.py`).
  An implied letter is never the answer and never a distractor. `LetterMediaContentTests` checks the
  Python result against `ArabicScript.graphemes` for every word.
- **Suras extended to 1, 94, 97, 103, 108, 110–114** (210 words): the shortest set that plainly writes all
  29 letters (94 adds ظ, 97 adds ز). L5's Quran bridge suras are among them.
- **Tracing covers isolated forms only** (`letter.write.<letter>`, 29 skills); the stroke table stores every
  form (207 strokes), so tracing forms later is a curriculum change. The checker (`TraceChecker`) is
  deterministic: same number of paths and taps, each path covers and stays within 0.15 of the guide, drawn
  from its start (skipped for closed shapes), each dot tapped. No handwriting recognition (spec §2).
- **Listening replaces transliteration where a recording exists.** `letter.sound.*` and `sound.discriminate.*`
  now play the fatha syllable and ask for the letter; alif keeps the text prompt. Recognition plays the
  letter's name. This moves away from transliteration in assessments (spec L4 gate) early.
- **No new SF Symbol.** "Play again" reuses `NoorSystemImage.play`; a speaker symbol would be a QuranEngine
  change that requires both Quran suites and a Quran release for one glyph.
- **Fixed in passing (L2 bug):** after grading, choice and match buttons used `.disabled`, which greys out
  the green tint that marks the right answer (seen in the simulator). They now use `.allowsHitTesting(false)`.
- **Untracked `Tools/learning/__pycache__`** (two `.pyc` files committed in L1) and ignored `__pycache__/`.

## Trade-offs

- **Complexity added:** Swift 30 source files / 2,715 lines (L2: 26 / 2,146); new `TraceChecker` (139),
  `LetterMedia` (model), `ClipPlayer`, `TracingCanvas`; content schema v2 (`audio_clip`, `stroke`,
  `word_letter` tables). Tools: `audio.py`, `strokes.py` + tests; `Tools/learning/*.py` now 1,487 lines.
  New failure mode: a missing or unplayable clip (validated at compile time; at run time `ClipPlayer`
  silently does nothing).
- **Binary size:** +1.7 MB of audio (140 clips, AAC 64 kbps) and the content DB grows 140 KB → 296 KB.
- **Who benefits / how often:** every learner in U2–U3. Tracing is the most likely to be **rarely used**
  (a phone with a finger is a rough writing surface, and VoiceOver users must skip it); it costs
  `TraceChecker` + `TracingCanvas` (~280 lines) and 3 lessons.
- **Rejected cheaper options:** porting Noorine's `StrokeGuideOverlay` (it animates with timers and its own
  colors; a static numbered guide is simpler); `QueuePlayer`/`QuranAudioKit` for clips (built for ayah queues,
  heavier than one `AVAudioPlayer`); loading clips off the main actor (they are 7–20 KB; reading them is
  far below a frame).
- **Ongoing cost:** re-run `audio.py` / `strokes.py` only when a source changes; a reviewer must listen to
  140 clips and check 29 stroke guides (Noorine's are coarse: ش is drawn as a V, not a bowl).

## Changes

- `Tools/learning/audio.py` (+ `audio.test.py`): audition, trim, normalize, AAC/CAF import; writes
  `Tools/learning/content/audio.toml` and `Documentation/ArabicLearning/04-audio-audition.md`.
- `Tools/learning/strokes.py` (+ `strokes.test.py`): Noorine `Core/course_content.json` at `984064234a8a`
  → `Tools/learning/content/strokes.json` (29 letters, every form).
- `Tools/learning/compile.py`: schema 2; tables `audio_clip`, `stroke`, `word_letter`; skills
  `letter.inword.*`, `letter.write.*`; sources `letter_audio`, `strokes`. `validate.py`: `validate_coverage`
  (every letter/sound skill taught), `validate_audio`, `validate_strokes`, `validate_word_letters`.
- `Tools/learning/content/curriculum.toml`: unit U3 with 13 lessons (7 joining, 3 find-in-word, 3 tracing),
  orientations `joining` and `non-joiners`, suras list.
- `ArabicLearning/Sources/LearningContent/Resources/Audio/*.caf` (140), regenerated `learning-content.sqlite`
  and manifest; `Package.swift` copies `Resources/Audio`.
- `LearningModel/LetterMedia.swift`: `AudioClip`, `CanvasPoint`, `GuideStroke`, `WordLetters`.
- `LearningContentStore`: `schemaVersion` 2, `audioClips()`, `strokeGuides()`, `wordLetters()`.
- `ExerciseKit`: prompts `listenForLetter`, `letterInWord`, `traceLetter`; kind `trace`; response `trace`;
  `Exercise.audio`; `TraceChecker`; generator inputs `clips`, `strokes`, `words`.
- `LearningUI`: `ClipPlayer` (AVAudioPlayer, `.playback` session), `TracingCanvas`, new prompts in
  `ExerciseView`, `PracticeViewModel` loads the new content; 6 strings in `Localizable.xcstrings`.
- iPhone and iPad share every change (one universal target).

## Tests

- `TraceCheckerTests` (9): exact trace passes for every form of every letter (real Noorine fixtures); wobble
  passes; off-path, half stroke, reversed, missing/extra dot, misplaced tap fail; dots in any order; grading;
  resampling.
- `LetterMediaExerciseTests` (7): listening exercises use the fatha clip and family distractors; alif keeps
  text; contrasts play the target; recognition plays the name; find-in-word answers are plainly written and
  distractors absent in any spelling (all 29 letters × 5 seeds); writing traces the isolated form; every
  taught skill has an exercise for two seeds (replaces the old ExerciseKitTests test, whose generator had no
  words or strokes).
- `LetterMediaContentTests` (3): every clip is a bundled file and every letter has name + vowels; every form
  has an on-canvas guide; compiled word letters agree with `ArabicScript.graphemes` and cover all 29 letters.
- `PracticeViewModelTests` answers trace exercises with the guide; `LearningContentStoreTests` expects U3.
- Tools: `audio.test.py` (8), `strokes.test.py` (3), `compile.test.py` 19 → 26 (coverage, missing audio, missing
  fatha, bad strokes, uncovered letter, word letters).
- The tint fix (`.allowsHitTesting`) is presentation only; no unit test can observe it. Seen in the simulator
  before the fix (green tint greyed out); not re-checked after it (UNVERIFIED).

## Validation

- **Verified:**
  - `make test-arabican`: all 7 bundles passed, `Executed 22 tests, with 0 failures` (ExerciseKitTests),
    `Executed 10` (LearningUITests), `Executed 8` (LearningContentTests), `Executed 10` (LearningEngineTests),
    `Executed 9` (ArabicScriptTests), `Executed 4` (LearningModelTests), `Executed 4` (LearningPersistenceTests):
    67 tests.
  - `make build-arabican`: `Build Succeeded`.
  - `make test-tools`: exit 0; `audio.test.py` `Ran 8 tests ... OK`, `compile.test.py` `Ran 26 tests ... OK`,
    `strokes.test.py` `Ran 3 tests ... OK`, package pins `5 passed, 0 failed`.
  - `make format-lint`: `0/1116 files require formatting`.
  - `python3 -I Tools/learning/compile.py --check`: matches a fresh build.
  - Simulator (iPhone 18 Pro, light): Learn lists U3; Practice shows "Which letter is alif?" with "Play
    again". `TracingCanvas` rendered with `ImageRenderer` in light and dark (throwaway test, deleted).
- **Not verified:**
  - Audio is audible and plays at a sensible level (no audio output from the simulator session).
  - Articulation of every accepted clip (needs a qualified listener; risk 2).
  - Tracing by finger on a device; listen and find-in-word screens in the running app (reached only through
    many lessons); iPad split view, landscape, large Dynamic Type, VoiceOver (canvas is one labeled element;
    tracing must be skipped with VoiceOver).

## Release

- **Commit:** `0d3e4d48` (`feat(arabican): L3 letter audio, joining forms, find-in-word, tracing`)
- **Pushed:** origin/main at `0d3e4d48`
- **TestFlight:** Arabican build 971 (0.1.0): `Uploaded Arabican iOS 0.1.0 (971) for commit
  0d3e4d48cb0754d72390cb9edb428be00220b1e0 to App Store Connect app Arabican.`
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- A qualified listener reviews the 140 clips and the 29 isolated stroke guides; reject a clip by editing the
  rules in `audio.py` or replacing the source file, then re-run it (spec risk 2).
- Form identification inside unseen Quran words (U3 assessment idea in spec §4) is not built; L4 can add it
  on top of `word_letter` and `ArabicScript.graphemes`.
- Tracing joined forms (data is already compiled).
- VoiceOver/Dynamic Type smoke check (open from L2) now also covers the listen, find-in-word and tracing screens.
