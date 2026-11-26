# Arabican L6: tajweed foundations from two cross-checked sources

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped (TestFlight build 977)
- **Related:** [L5](2026-11-26-arabican-l5-quran-bridge-vocabulary.md), spec
  `Documentation/ArabicLearning/03-spec-roadmap-risks.md` §5.2 L6, cross-check log
  `Documentation/ArabicLearning/05-tajweed-crosscheck.md`

App: **Arabican** only. No QuranEngine path changed (no `Core/`…`Features/`, `Package.swift` or
`Package.resolved` edits), so the Quran app's suites, builds and release are not required.

## Context

The owner asked to "continue with the remaining work" from `Documentation/ArabicLearning/HANDOFF.md`, whose
next milestone is L6: tajweed spans for the bridge suras from quran-transcript, cross-checked against
Quran.com's `uthmani_tajweed`, and T1 lessons (noon/meem sakinah, qalqalah, madd, waqf basics) with an
explanation, verified examples and a listening drill. The handoff said both sources need the owner's OK;
asked in chat (2026-11-26), the answer was "Approve both": pip-install quran-transcript at `e30c100` into a
scratch virtualenv and run it at build time only, and fetch Quran.com's tajweed text for the 8 bridge suras.
Pins and hashes: `05-tajweed-crosscheck.md` §Sources.

## Decisions

- **Spans are a committed TSV made by a tool**, like L5's morphology: `Tools/learning/tajweed.py` (run in the
  virtualenv) writes `content/tajweed.tsv`; `compile.py` reads it with the system Python. No Python ships.
- **Hafs defaults recorded:** murattal, four counts for the separated, joined and stop madds (the
  quran-transcript README's choice); every other `MoshafAttributes` field is the library default. Each ayah is
  phonetized alone, so its last word is read with a stop, as a learner stops at each ayah.
- **Cross-check rules** (`05-tajweed-crosscheck.md` §Method): Quran.com never colors izhar, the stop alif after
  tanwin fath, or a natural madd on a full letter, so those are taught from the phonetizer alone (agreement
  `phonetizer`), not reviewed one by one. Three real disagreements remain; each has a decision and reason in
  `content/tajweed_review.toml` (all three "teach"), and the tool refuses an unreviewed or stale one.
- **Noon rules and ghunnah anchored on letters**, not on the phonetizer's span extents: its position mapping
  merges spans in 111:5 and 114:6 (seen in its raw output). The noon or tanwin and the next read letter (the
  silent alif after tanwin fath skipped), or the doubled noon or meem, are what the exercise colors.
- **Rules taught: the 13 with an example in the bridge suras.** Iqlab, meem idgham, meem ikhfa and the soft
  madd have none there, so they are not taught (a rule without an example fails the compiler). Adding them
  needs a sura with recitation and timings that has them; a check sura would spend unseen words.
- **Waqf basics = two rules**: madd before a stop (ʿāriḍ) and stopping on tanwin fath (ʿiwaḍ), lesson
  "Stopping at the end of an ayah"; qalqalah at a stop is in the qalqalah explanation.
- **Unit order:** tajweed is unit U9, right after the bridge (its examples are the bridge suras), and
  vocabulary moves from U9 to U10 (lesson ids `u9.lNN` → `u10.lNN`). Lesson ids are not persisted (evidence
  is keyed by skill id; checked `LearningPersistence`), so no learner data moves. Lesson order is linear
  (`SkillGraph.nextLesson`), so tajweed now comes before the 30 vocabulary lessons.
- **Two skills per rule:** `tajweed.spot.<rule>` (the ayah with the rule's letters colored, then recited) and
  `tajweed.listen.<rule>` (the rule's words recited, text hidden until the answer). Options are rule names,
  the same group first; a rule that also applies to the shown letters (spot) or played words (listen) is
  never a distractor. The explanation shows after every answer.
- **No T1 unit check.** The exit gate does not require one, and several rules have one or two examples in
  total (necessary madd, joined madd, merging without ghunnah), so there are no unseen items to hold out.
- **Color is not the only cue.** The Quran font draws some letter pairs as one ligature (حَمَّ), and a color
  change inside a ligature is dropped (seen in a render). The ayah underlines the rule's words and repeats
  the rule's letters on their own line below (`TajweedAyahText`).
- **Explanations are English only**, so no Arabic is set in the system font; examples are shown in the Quran
  font by the exercise.
- **`phonetic_plan` table not built.** Its first consumer is R1 (recognition); L1 moved it to L6 for the
  same reason. It moves to R1.

## Trade-offs

- **Complexity added:** ~260 Swift source lines (4,505 → 4,761) in 2 new and 6 changed files (`Tajweed.swift`,
  `TajweedExercises.swift`, store loader, generator, `TajweedAyahText`, two prompts), ~230 test lines; Python
  `tajweed.py` (481 lines) with tests (141), compiler and validator additions (~110 lines), authored
  `tajweed.toml` (13 rules, 6 lessons) and `tajweed_review.toml`. Content schema 5 adds `tajweed_rule` and
  `tajweed_span`. No dependency in the app, no permission, no persisted learner state, no background work.
- **Who benefits / how often:** every learner who reaches the bridge; 6 short lessons.
- **Rejected cheaper options:** one source only (the owner's spec asks for a cross-check, and the
  phonetizer's merged spans would have gone unnoticed); hand-authored spans (the spec forbids agent-authored
  tajweed labels); coloring tajweed in the Quran tab reader (more UI and a toggle; exercises cover rule
  identification; a follow-up if wanted).
- **Ongoing cost:** content DB 750 → 768 KB. Re-running `tajweed.py` needs the virtualenv and the saved
  Quran.com files (pins in `05-tajweed-crosscheck.md`). Explanations and the three decisions need teacher
  review (risk 6).

## Changes

- Tools: `Tools/learning/tajweed.py` (alignment, Quran.com parser, rule classification, cross-check, review),
  `content/tajweed.toml`, `content/tajweed_review.toml`, `content/tajweed.tsv`; `compile.py` (schema 5,
  `tajweed_lessons`, two tables, two sources, U9 between U8 and U10); `validate.py` (`validate_tajweed`);
  `content/curriculum.toml` (unit U9 Tajweed foundations, vocabulary U10).
- Content: regenerated `learning-content.sqlite` and manifest.
- `LearningModel/Tajweed.swift`: `TajweedRule`, `TajweedExample` (`words`, `overlaps`, `sharesWords`).
- `LearningContentStore`: schema "5", `tajweedExamples(bridges:)`.
- ExerciseKit: `ExercisePrompt.tajweedSpot`, `.tajweedListen`; `TajweedExercises.swift`;
  `ExerciseGenerator(tajweed:)`.
- LearningUI: `PracticeView` renders both prompts, `TajweedAyahText`, explanation `GroupBox`;
  `PracticeViewModel` loads the examples; two strings.
- Platforms: iPhone and iPad (one universal target); no platform-specific code.

## Tests

- New Swift: `TajweedContentTests` (13 rules and 26 taught skills; every colored grapheme range fits
  ArabicScript's own split and holds the rule's letter: a madd letter or mark, noon or tanwin then the next
  letter, meem, a qalqalah letter, a doubled noon or meem; recitation covers the rule's words; known examples
  يَكُن لَّهُۥ and ٱلضَّآلِّينَ; all three agreements present), `TajweedExerciseTests` (for every rule, both
  abilities and 20 seeds: four distinct rule-name options, the answer is the rule, no distractor applies to
  the shown or played letters; same-group distractors; no exercise for an unknown rule).
- Changed: `LearningContentStoreTests` (units U1–U10), `LetterMediaExerciseTests.test_everyTaughtSkillHasAnExercise`
  (generator gets tajweed examples, so every taught tajweed skill must build).
- Tools: `tajweed.test.py` (14 tests: graphemes, tatweel and ٲ alignment, Quran.com parsing, classification
  including the 111:5 and 114:6 merged spans and the article exclusion, agreement per rule, review required,
  review decides, stale review fails); `compile.test.py` +4 (U8 → U9 → U10 order and skills, rules and
  examples in the DB, rejects a rule without an example, a span outside its word, a rule no lesson teaches).

## Validation

- **Verified:**
  - `<venv>/bin/python -I Tools/learning/tajweed.py --qurancom <dir>`: `36 ayahs; 3 disagreements reviewed;
    wrote 159 rows`.
  - `python3 -I Tools/learning/compile.py`: `{'letters': 29, 'skills': 575, 'lessons': 84, …,
    'tajweed_spans': 138, …}`.
  - `make format-lint`: `0/1136 files require formatting`.
  - `make test-arabican`: exit 0; the xcresult summary reads `result: Passed, totalTestCount: 107,
    passedTests: 107, failedTests: 0` (100 before L6). A first run failed nothing; earlier iterations of the
    new tests caught wrong expectations in the tests themselves (grapheme index of يَكُن), not the code.
  - `make test-tools`: exit 0 (`compile.test.py` `Ran 40 tests … OK`, `tajweed.test.py` `Ran 14 tests … OK`,
    shell suites `22 passed, 0 failed` etc.).
  - `make build-arabican`: `Build Succeeded`.
  - Rendering: `TajweedAyahText` drawn with `ImageRenderer` for eight rules (a temporary test, not committed):
    Arabic keeps its joining across colored letters; ghunnah in حَمَّالَةَ lost its color inside the font's
    ligature, which led to the underline and the letters line.
- **Not verified:** the two prompts in the full practice flow on a simulator or device (reaching U9 needs
  every earlier lesson mastered); VoiceOver reading of the combined ayah element; Dynamic Type at the largest
  sizes; iPad split view; that the listening drill's recitation segments sound complete at word boundaries
  (QUL timings, as L5); teacher review of explanations, the three decisions and a sample of spans.

## Release

- **Commit:** `f4f5ab48`
- **Pushed:** origin/main at `f4f5ab48`
- **TestFlight:** build 977 (0.1.0): `Progress 100%: Upload succeeded.` and `Uploaded Arabican iOS 0.1.0 (977) for
  commit f4f5ab480fb91f13ce8f88325860b0231ac8dbb0 to App Store Connect app Arabican.`
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Teach iqlab, meem idgham, meem ikhfa and the soft madd: add a bridge sura with recitation and timings that
  has them (for example 105 has ikhfa shafawi, but it is a check sura; moving it spends unseen words), then
  re-run `tajweed.py` and fetch its Quran.com file.
- Optional tajweed coloring in the Quran tab reader, reusing `tajweed_span` and `TajweedAyahText`.
- Carried from L5: interleave vocabulary with U4–U7, a meaning-language preference, optional tracing.
