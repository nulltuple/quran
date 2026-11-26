# Handoff · Arabican (Quranic Arabic learning app)

Give this file to a new Claude Code session opened in this repository (`nulltuple/quran`). Read it fully, then
`AGENTS.md` (especially "Two apps, one repository"), before acting.

## Which app this is

This repository builds **two apps**. This handoff is for **Arabican** only.

| | Arabican (this handoff) | Quran (not this handoff) |
|---|---|---|
| App Store Connect / bundle id | **Arabican** / `com.nulltup.arabican` | MemQuran / `com.nulltup.memquran` |
| Code | `ArabicLearning/` (nested Swift package, iOS 17, Swift 6) | root package `QuranEngine` |
| App project | `Apps/Arabican/Arabican.xcodeproj`, scheme `Arabican` | `Example/QuranEngineApp.xcodeproj` |
| Content tools | `Tools/learning/` | `Tools/build-qul-word-data.py` etc. |
| Test / build / run | `make test-arabican`, `make build-arabican`, `make run-arabican` | `make test-no-sync`, `make test-sync`, `make build-example-*` |
| Release | `make release-testflight-arabican` | `make release-testflight-quran` |

Arabican imports QuranEngine modules (`NoorUI`, `QuranKit`, `QuranResources`, `SQLitePersistence`, ...); QuranEngine never
imports Arabican (guardrail-enforced). A change to a shared QuranEngine module must pass **both** apps' suites.

## State (updated at the end of each milestone)

See the milestone status table, `03-spec-roadmap-risks.md` §5.1, for done/not-done per milestone, trail entries and
TestFlight builds. Summary:

- **L0 done (2026-11-25):** nested package, app project, icon, 4-tab shell, two-app release lane, guardrails, CI jobs,
  AGENTS.md two-app rules. Trail: `../trail/2026-11-25-arabican-l0-bootstrap.md`.
- **L1 done (2026-11-25):** `Tools/learning/compile.py` (+ validate, 19 tests) builds
  `ArabicLearning/Sources/LearningContent/Resources/learning-content.sqlite` from TOML content and QuranEngine's
  canonical text; `ArabicScript` (letters, marks, graphemes); `LearningContent` store; Learn tab lists lessons.
  Trail: `../trail/2026-11-25-arabican-l1-content-compiler.md`.
- **L2 done (2026-11-25):** local profiles (`LearningPersistence`, GRDB, one progress file per profile), `LearningEngine`
  (mastery with uncertain, prerequisite graph, FSRS via swift-fsrs 6.0.0, session planner), `ExerciseKit` (seeded
  choice/match/explanation exercises and graders), profile setup, Practice and Progress tabs. 49 package tests.
  Trail: `../trail/2026-11-25-arabican-l2-engine-profiles-practice.md`. Open from L2: VoiceOver/Dynamic Type smoke check.
- **L3 done (2026-11-26):** 140 Antura letter clips (`Tools/learning/audio.py`, audition log `04-audio-audition.md`,
  AAC in `.caf` under `LearningContent/Resources/Audio`), Noorine stroke guides (`Tools/learning/strokes.py` →
  `content/strokes.json`), content schema 2 (`audio_clip`, `stroke`, `word_letter`), U3 (13 lessons: joining forms,
  find-in-word, tracing), listening exercises, `TraceChecker` + `TracingCanvas`. 67 package tests.
  Trail: `../trail/2026-11-26-arabican-l3-literacy-audio-tracing.md`. Open: articulation review by a qualified
  listener (risk 2), audio heard on a device, tracing by finger, VoiceOver/Dynamic Type.
- **L4 done (2026-11-26):** U4–U7 (13 lessons: short vowels, long vowels, sukun/shaddah/tanwin/silent letters,
  decoding), compiler-made unit checks `u<N>.check` for U2–U7 over 504 held-out check words (`check_suras`, schema 3
  `pool` column), placement check (`PlacementTest`, `placement` table, migration v2), `ArabicScript.ReadableWord`,
  `audioChoice` exercises. 90 package tests. TestFlight build 973. Trail: `../trail/2026-11-26-arabican-l4-reading-and-placement.md`.
  Open: teacher review of U4–U7 text and stage rules, audio on a device, VoiceOver/Dynamic Type, tracing still
  blocks u3.check for learners who cannot trace.
- **L5 done (2026-11-26):** Quran tab = learning-mode reader for bridge suras 1, 112, 113, 114, 108, 103, 110, 111
  (bundled Afasy MP3s, byte for byte, timed by `qul_afasy.db`; recited-word highlight; word sheet with EN/BN meaning,
  transliteration, QAC parts, lemma gloss, root, part of speech, Quran-wide count), record and compare per ayah
  (microphone permission, one temp file deleted on close), `Tools/learning/morphology.py` (QAC v0.4 + QuranicWords
  glosses → `content/lemmas.tsv`, `content/word_segments.tsv`), content schema 4, compiler-made U8 (bridge: word by
  ear, meaning in ayah) and U9 (top 300 lemmas, 10 per lesson). 100 package tests. Foundational beta.
  TestFlight build 975. Trail: `../trail/2026-11-26-arabican-l5-quran-bridge-vocabulary.md`.
  Open: teacher review of glosses (13 authored in `glosses.toml`) and bridge lessons, a real recording on a device,
  reader accessibility (VoiceOver, Dynamic Type, iPad), practice screens of the new prompts not yet seen on screen.
- **Next: L6** Tajweed foundations (§5.2): full `phonetic_plan` + tajweed spans for the bridge suras
  (quran-transcript, Hafs defaults recorded) cross-checked against Quran.com `uthmani_tajweed`; T1 lessons
  (noon/meem sakinah, qalqalah, madd, waqf basics) with explanation, verified examples and a listening drill — the
  bridge recordings and word timings now exist for drills. Running quran-transcript (pip, third-party code) and
  fetching Quran.com tajweed text need the owner's OK first (ask, as L5 did for downloads). Smaller L5 follow-ups
  that fit any session: interleave U9 vocabulary with U4–U7 (planner offers one next lesson today), a
  meaning-language preference (Bengali data is compiled), making tracing optional (L4 follow-up).

## Decisions already made by the owner (do not re-ask)

- Repository home: nested package in this repo (ADR-0001 option A).
- Brand: **Arabican**, bundle id `com.nulltup.arabican`, App Store Connect app "Arabican" (owner created it).
- **Licensing does not restrict reuse** (personal, non-commercial use, 2026-11-25). Record sources for traceability only.
  Risks 3–5 are closed.
- swift-fsrs is approved for `ArabicLearning/Package.swift` (owner delegated the choice). Pin it exactly at L2.
- Push an Arabican TestFlight build at the end of every milestone.

## Facts a new session should not re-derive

- Nested package depends on `.package(name: "QuranEngine", path: "..")`; products are referenced with
  `package: "QuranEngine"` (works in worktrees with any folder name).
- `ArabicLearning/Package.resolved` and `Apps/Arabican/Arabican.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  must pin shared packages exactly like the root `Package.resolved` (`Tools/package-pins.test.sh`). Xcode may re-resolve
  the project file to newer versions; copy the root pins back and re-run `xcodebuild -resolvePackageDependencies`.
- The app project uses a file-system synchronized group: files under `Apps/Arabican/Arabican/` are picked up without
  editing `project.pbxproj`. Keep the app target thin (composition only).
- SF Symbols come from `NoorSystemImage` (NoorUI); add cases there (a shared QuranEngine change).
- Arabican package tests run on the `iPhone Air` simulator, Quran's on `iPhone 17e`, so they can run concurrently.
- Canonical Quran text: `QuranResources.quranUthmaniV2Database` (`arabic_text(sura, ayah, text)`), 6,236 ayahs, 72 distinct
  code points (inventory 2026-11-25). The canonical text stores a vowel before shadda (`رَّ` = ra, fatha, shadda).
- Word identities: `word_by_word.db` (`Example/QuranEngineApp/Resources/`): `word_meanings(sura, ayah, word, english,
  bengali, transliteration)`; `uthmani_tokens` maps tokens to words only for the six ayahs that don't split one token
  per word (15:7, 27:20, 36:22, 37:130, 37:164, 41:47). `۞` and pause marks are attached to word tokens, not separate.
- After editing `Tools/learning/content/*.toml`, run `python3 -I Tools/learning/compile.py` and commit the regenerated
  database and manifest; `compile.test.py` fails on a stale database.
- Arabican builds pass `-onlyUsePackageVersionsFromResolvedFile` (Makefile `ARABICAN_RESOLVE_FLAGS`, release script) so
  Xcode keeps the committed pins. When adding a package (FSRS), resolve once without the flag, then re-run
  `bash Tools/package-pins.test.sh`.
- Learner data (profiles, progress) must never go through QuranEngine's `DatabaseConnection`: it deletes the file on
  `SQLITE_CANTOPEN`/`NOTADB`/`CORRUPT` (`Data/SQLitePersistence/Sources/DatabaseConnection.swift:162-178`). Use GRDB
  `DatabaseQueue` + `DatabaseMigrator` as `ProfileStore`/`ProgressStore` do; every schema change needs a migration test.
- Mastery: `SkillEvidence.state(for:)` (orientation skills use `MasteryPolicy.explanation`); always use `state(for:)`,
  not `state()`, when a skill id is at hand.
- Arabic glyphs: `Font.custom(.uthmanicHafs, size:, relativeTo:)` from NoorFont; fonts are registered by
  `ArabicanRootView.registerFonts()` at launch.
- TestFlight: `make release-testflight-arabican`. If export says the app record is missing, the owner must fix App Store
  Connect; a saved `.xcarchive` can be re-exported with `xcodebuild -exportArchive` and
  `.build/testflight/arabican/ExportOptions.plist`.
- Running freshly downloaded third-party test suites (swift-fsrs `swift test`, quran-transcript `pytest`) was deliberately
  not done; swift-fsrs is exercised through our own tests once added.
- Noorine stroke data, Antura letter audio and quran-transcript details: see `01-source-evaluation.md`.
- Re-running `Tools/learning/audio.py` needs the Antura wavs (download from
  `https://media.githubusercontent.com/media/vgwb/Antura/<commit>/Assets/_lang_bundles/arabic/Audio/Letters/<file>`);
  output is byte-for-byte reproducible (`.caf`; `.m4a` is not). Then run `compile.py`.
- Content schema is 4 (`LearningContentStore.schemaVersion`); bump both when the compiled tables change. The content
  DB is replaced wholesale, so no migration is needed (it is not user data).
- Find-in-word never asks for or offers a letter that a word only implies (ٱ أ ة ى ۥ, dagger alif...):
  `IMPLIED_LETTERS` in `compile.py`, checked against `ArabicScript.graphemes` by `LetterMediaContentTests`.
- KFGQPC encoding (L4): U+0652 is **not a sukun**; it is the "never read" circle on ا/و/ي. The sukun is U+06E1.
  U+0656/0657/065E are the staggered tanwin. The text never uses U+0622 (آ): it writes alif + U+0653; write such test
  literals with `\u{...}` escapes, since editors may compose them.
- Reading stages: `ArabicScript.ReadableWord` (features per grapheme, `isSilent(at:)`), `ReadingStage` in ExerciseKit.
  Unit checks: `Curriculum.checkRequirements`; `ExerciseGenerator(checks:)` builds a required skill's exercise from
  check words without transliteration and scores the check (`Exercise.scoring`). Placement mastery:
  `PlacementMastery.mastery(evidence:placements:curriculum:)`; always plan with `placements:`.
- L5 data: `Tools/learning/morphology.py` needs the two downloads named in the L5 trail entry (QAC
  `quran-morphology.txt` at mustafa0x/quran-morphology `8f38b39`, QuranicWords `dataset/words.json` at `4fd80e1`);
  it covers suras 1 and 78–114 (`COVERED_SURAS`), so bridge/check suras in Juz Amma can change without re-running
  it. A top lemma without a gloss fails the tool: add it to `content/glosses.toml`. Gloss matching needs same word
  class + root and a count within 2x (QuranicWords splits senses and spells lemmas differently).
- Bridge recordings: `content/recitation.toml` pins each MP3's SHA-256; the compiler rejects a different file because
  `qul_afasy.db` timings belong to these exact recordings. Do not transcode them (encoder delay shifts timings).
- Bridge/vocabulary lessons are generated (`bridge_and_vocabulary` in `compile.py`), like unit checks; U8/U9 lesson
  ids are `u8.lNN`, `u9.lNN`; skills `bridge.listen.<sura>`, `bridge.meaning.<sura>`, `lemma.meaning.<QAC lemma>`.
- `UIx.WrappingHStack` flows right to left under `.environment(\.layoutDirection, .rightToLeft)` (seen in the
  simulator). Keep Arabic and English in separate `Text`s: a mixed string reorders by bidi rules.
- The simulator's microphone is the Mac's: when checking record and compare, choose Don't Allow unless the owner asks.
- Swift `String.contains` compares grapheme clusters: a letter with marks never matches a bare letter. Compare
  `unicodeScalars`.
- `ImageRenderer` does not draw `ScrollView` content; render a subview to snapshot it.

## Owner preferences

- Cut scope aggressively and reorder for simplicity. Don't follow proposals verbatim.
- Maximum reuse of QuranEngine modules; never copy a QuranEngine type into ArabicLearning.
- Work token-efficiently. Write or refresh this handoff whenever the context grows large.

## Still pending with the owner (not needed before L6)

A qualified reviewer or reciter for letter audio and lessons (spec risk 2, 11).
