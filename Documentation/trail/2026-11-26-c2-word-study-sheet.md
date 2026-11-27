# C2 (Quran): full-Quran morphology database and the word study sheet

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped (slices a and b of C2; slice c, occurrences and tap-to-hear, is a follow-up)
- **Related:** [Arabican L5](2026-11-26-arabican-l5-quran-bridge-vocabulary.md) (the QAC approach this promotes),
  [M1 canonical word data](2026-11-24-m1-canonical-word-data.md), [roadmap v2](2026-11-26-quran-roadmap-v2.md) §6 C2

App: **Quran**, with shared QuranEngine modules Arabican also compiles (`QuranText`, `NoorUI`, `Localization`), so
both apps' suites and builds ran and both are released.

## Context

The owner asked to "continue the Quran roadmap from Documentation/agents/quran-roadmap-progress.md, starting with
the first item under Next steps", which was C2 word study: QAC v0.4 `quran-morphology.txt` mapped onto M1's
canonical word ids into a bundled `quran_morphology.db`, a Domain `WordStudyService`, a word sheet from the
translation view's word tap and the page word pointer, occurrences and tap-to-hear, in 2–3 slices. This entry
ships slices (a) tool + database + coverage report and (b) service + sheet from the translation view.

Source (downloaded 2026-11-26 into an empty scratchpad directory, not in git): the owner approved this download
for Arabican L5 on 2026-11-26 and roadmap v2 names it for C2.

| Source | Pin | SHA-256 |
|---|---|---|
| `https://raw.githubusercontent.com/mustafa0x/quran-morphology/8f38b39016824284f9ed16ae15069ff9102c4acf/quran-morphology.txt` | commit `8f38b39` | `742bfac59941b2cb09736d5b7aae694af50792261fb8450cbf6afafcc340645f` (same as L5) |

Facts verified before building: 130,030 segment lines over 77,429 QAC words; QAC numbers words like
`word_by_word.db` everywhere except 2:181, 8:6 and 13:37, where QAC keeps `بَعْدَ مَا` as one word of two segments
and the canonical words (QUL recitation, Quran.com) are two (inspected in both files; `word_by_word.db` gives both
canonical words the meaning "after what").

## Decisions

- **Split, not skip, the three `بَعْدَ مَا` words.** The tool finds the one QAC word whose segments are exactly
  بعد + ما in an ayah with one word fewer and gives each segment its own canonical word; any other mismatch fails
  the build. Result: all 77,432 canonical words mapped, none listed as an exception.
- **No guessed grammar.** Every QAC feature must decode into a known column (word class, derivation, role,
  person/gender/number, verb form, aspect, voice, mood, case, indefinite, family) or the tool fails naming the
  segment. Two gaps surfaced and were handled from the data, not guessed: `ADDR` also tags three noun suffixes
  (6:40, 6:47, 17:62), and `NV` nouns carry `PERF`/`IMPF`/`IMPV` (أُفٍّ, هَيْهَاتَ), kept as their aspect.
- **Counts are QAC segment counts**, as the QAC website reports them: root ح م د 68, lemma حَمْد 43, ر ح م 339,
  رَحْمٰن 57 (each checked in the database; the first two also by `build-quran-morphology.test.sh`). A lemma is its
  text and root, because QAC spells seven lemmas the same under two roots (عَصا, آن, عاد, نَعَم, قائِل, جَواب, يُغاثُ).
- **Grammar interned in its own table** (1,067 distinct feature sets): the first layout with grammar columns on
  every segment was 9.3 MB; interned it is 5.9 MB (2.2 MB gzipped). Reproducible: a rebuild gives the same SHA-256
  `691564dc80a202b8daf8ec71b07435ff5de33d3ff1416262cc2201afed97a99b`.
- **No surface-form index** (roadmap v2 listed root, lemma and surface form): the sheet uses root and lemma; a form
  index adds size with no screen that reads it yet.
- **The real database in TestResources**, not a subset: git stores the identical file once, and tests check
  Quran-wide counts. `build-quran-morphology.test.sh` checks the bundled copy; the two copies must stay identical
  (copy both when rebuilding).
- **Grammar terms in a new English-only `Grammar` strings table**; other languages fall back to English through the
  existing `l(_:table:)` fallback. Agent translations of 90 linguistic terms into 15 languages would be poor and
  unreviewable; the 11 screen strings (title, labels, hint, attribution) are in all 16 `Localizable.strings`
  catalogs (agent translations, native review UNVERIFIED). Term names follow the QAC tagset; teacher review
  UNVERIFIED.
- **Entry point: a tap on a word in the translation view's word-by-word Arabic** (shown when word-by-word meaning
  is English or Bengali). The tap travels through the translation list's existing `TranslationURL` handler
  (`.word(sura:ayah:word:)`), then `ContentListener.presentWordStudy(_:)` (an existing listener extended by one
  method) to `QuranInteractor`, which presents the sheet like the tafsir sheet (`presentTranslatedVerse`, medium and
  large detents, leading Close).
- **`simultaneousGesture` tap, not `onTapGesture` or a Button.** With `onTapGesture` the page's UIKit long press (the
  ayah menu) no longer started on a word (seen in the simulator); with `simultaneousGesture(TapGesture())` both work
  (simulator: a tap opens word study, a long press on the same word opens the ayah menu). Without a handler the
  word takes no gesture at all.
- **The page word pointer entry is not in this slice**: the pointer shows a popover while dragging and has no
  "release to open" interaction to extend; designing one is part of slice (c).
- **The meaning in the sheet** is the reader's word-by-word language, or English when meanings are off.
- **IndoPak**: the corpus text is Uthmani, so with the IndoPak reading the sheet uses the Uthmanic Hafs font (as
  `QuranWordByWordText` does for its ayah marker).

## Trade-offs

- **Complexity added:** ~1,000 lines: tool 284 + test 115; Swift 333 (feature, 4 files) + 139 (persistence) + 102
  (service) + 199 (model types) + ~100 changed lines in 14 files; tests ~270 lines. A new feature module
  (`WordStudyFeature`), one `AppDependencies` property, one `ContentListener` method, one `NoorSystemImage` case
  (`wordStudy`, `character.book.closed`), a `Grammar` strings table (90 English terms), 11 keys × 16 catalogs.
  No dependency, permission, entitlement, background work or persisted user state.
- **Who benefits / how often:** readers who want to understand the Arabic; the sheet is one tap from the
  word-by-word view. Likely used by a minority of sessions (UNVERIFIED, no analytics), but it is the comprehension
  feature the roadmap ranks fifth and that Tarteel lacks.
- **Rejected cheaper options:** reuse Arabican's `lemmas.tsv`/`word_segments.tsv` (Juz Amma only, and QuranEngine
  must not depend on Arabican); QUL's morphology downloads (need the owner's signed-in browser, and QAC is the
  source QUL derives from); store raw QAC feature strings and parse in Swift (moves the "no guessed grammar" check
  from build time to run time).
- **Ongoing cost:** binary +5.9 MB uncompressed (~2.2 MB in the compressed IPA, UNVERIFIED against the real IPA).
  The database is read only when the sheet opens; launch time is unaffected (nothing opens it at launch).
  Rebuilding needs the one download above. Grammar term wording needs a teacher's review.

## Changes

- Tools: `Tools/build-quran-morphology.py` (QAC → `quran_morphology.db`, coverage report),
  `Tools/build-quran-morphology.test.sh` (31 checks), `make test-tools` runs it.
- Data: `Example/QuranEngineApp/Resources/quran_morphology.db` (bundled in `QuranEngineApp.xcodeproj` Resources),
  the same file in `Domain/TestResources/Sources/test_data/`.
- `Model/QuranText/Sources/WordMorphology.swift`: `WordMorphology` (`headSegment`), `MorphologySegment` (not `WordSegment`: Arabican's `LearningModel` has one), `WordLemma`,
  `WordRoot` (`spacedLetters`), `WordGrammar`, `WordStudyTerm`.
- `Data/WordTextPersistence`: `GRDBWordMorphologyPersistence` (`segments(of:)`, paged `occurrences(of:quran:after:limit:)`);
  `GRDBWordByWordPersistence.texts(for words:column:)` for scattered words; the target now depends on `QuranText`.
- `Domain/WordTextService/Sources/WordStudyService.swift`: `WordStudyService`, `WordStudy`, `WordOccurrence`.
- `Features/WordStudyFeature` (new): `WordStudyBuilder`, `WordStudyViewModel`, `WordStudyView`, `WordGrammarText`.
- `UI/NoorUI`: `QuranWordByWordText(onWordTapped:)` (button trait, hint, accessibility action), `NoorSystemImage.wordStudy`.
- `Features/QuranTranslationFeature`: `TranslationURL.word`, `TranslationArabicText.wordNumbers`,
  `ContentTranslationViewModel.onWordTapped`, `ContentTranslationBuilder.build(at:onWordTapped:…)`.
- `Features/QuranContentFeature`: `ContentListener.presentWordStudy(_:)`, `ContentViewModel.onWordTapped(_:)`, `PagesView`.
- `Features/QuranViewFeature`: `QuranInteractor.presentWordStudy(_:)`, `wordStudyBuilder` in `Deps`, `QuranBuilder` (sync and no-sync).
- `Features/AppDependencies(+Fake)`, `Example/.../Container.swift`: `quranMorphologyDatabase`.
- `Core/Localization`: `Table.grammar`, `en.lproj/Grammar.strings`, 11 `word_study.*` keys × 16 catalogs.
- `Package.swift`, `QuranEngine-Package.xctestplan`: `WordStudyFeature` and its tests.
- Platforms: iPhone and iPad (one universal target); no platform-specific code.

## Tests

- `Tools/build-quran-morphology.test.sh` (31): fixture build, coverage report, `بعد ما` split and renumbering,
  segment-count occurrences, lemmas kept apart by root, decoding of article, noun, passive jussive form IV verb,
  perfect verb, pronoun suffix, indefinite adjective participle, particle gender vs kind; rejects an unknown tag, two
  particle kinds, an unmappable ayah, a missing ayah; bundled database: every canonical word, 130,030 segments,
  ح م د 68, حَمْد 43, 1:2 word 1, 13:37 words 8–9, pinned source.
- `WordTextServiceTests/WordStudyServiceTests` (8): 1:2 ٱلْحَمْدُ segments and grammar, root and lemma counts, verb
  grammar of 2:3 word 2, Bengali and English fallback, 13:37 split words, a word past the ayah end, root occurrences
  paged in Quran order (68 distinct words), lemma occurrences (43).
- `WordStudyFeatureTests` (8): `WordStudyViewModelTests` (loaded, missing word, missing database),
  `WordGrammarTextTests` (noun, verb, derived noun, family particle; every grammar value in the database has an
  English term).
- `NoorUITests/QuranWordByWordTextTapTests` (4): button and selected traits, `wordStudy` symbol exists.

## Validation

- **Verified:**
  - `python3 -I Tools/build-quran-morphology.py <qac> <out>`: `ayahs 6236, words 77432, segments 130030, roots 1651,
    lemmas 4783, grammar 1067, split_words 3`, then the three `split …` lines.
  - `bash Tools/build-quran-morphology.test.sh`: `31 passed, 0 failed`.
  - `make test-no-sync TARGET=WordTextServiceTests`: `Executed 38 tests, with 0 failures`;
    `TARGET=WordStudyFeatureTests`: `Executed 8 tests, with 0 failures`.
  - Simulator (iPhone 18 Pro Max), no-sync build: Al-Fatihah in Translation/Tafseer mode, word-by-word English on;
    tapping ٱلرَّحْمَٰنِ opened the sheet (l-raḥmāni, "the Most Gracious", Al-Fātihah, Ayah 1, word 3; prefix
    Definite article; Adjective · masculine singular · genitive; Root ر ح م, 339; Dictionary form رَحْمٰن, 57), in
    Light and Dark; long press on a word opened the ayah menu; long press on the translation text too.
  - `make test-no-sync TARGET=QuranTranslationFeatureTests`: `Executed 51 tests, with 0 failures`;
    `TARGET=QuranContentFeatureTests`: `Executed 25 tests, with 0 failures`.
  - Full suites after the last source change (xcresult summaries): `make test-no-sync` `Passed 1531/1531` (1,507 at C1
    EN/BN); `make test-sync` 2,009 of 2,010 passed; `make test-arabican` `Passed 117/117`. An earlier full sync run on
    this change (before the type rename below) passed 2,010/2,010.
  - The one sync failure, `NotesViewModelTests/test_dismissHighlightsTip_retiresItForLaterLaunches` ("Test exceeded
    execution time allowance of 1 minute"), is flaky and unrelated (no Notes code changed): `make test-sync
    TARGET=NotesFeatureTests` on this change twice, `Executed 21 tests, with 0 failures` both times; on the parent
    commit `82e14eef` (temporary worktree), `Executed 21 tests, with 0 failures`.
  - The first `make test-arabican` failed to compile: `'WordSegment' is ambiguous for type lookup` in
    `ArabicLearning/Sources/LearningContent/LearningContentStore.swift:293`, because Arabican's `LearningModel` already
    has a `WordSegment`. The QuranEngine type is now `MorphologySegment`; Arabican is unchanged.
  - `make test-tools`: every suite passed (`31 passed, 0 failed` for the new one). `make format-lint`: `0/1173 files
    require formatting`. `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: `Build Succeeded`.
- **Not verified:** VoiceOver on the sheet and on tappable words on a device; the largest Dynamic Type sizes (the
  sheet is a standard inset-grouped `List` with system text styles); landscape; iPad split view (no iPad simulator
  allowed); the sync build in the simulator (compiled and tested only); IPA size growth; teacher review of the
  grammar terms; native review of the 15 agent translations.

## Release

- **Commit:** `f03021d83b44f37ff729382b400edc0f3f7c476d`
- **Pushed:** origin/main at `f03021d8` (`82e14eef..f03021d8  HEAD -> main`)
- **TestFlight:** Quran build 994 (1.20.3): `Uploaded Quran iOS 1.20.3 (994) for commit
  f03021d83b44f37ff729382b400edc0f3f7c476d to App Store Connect app MemQuran.` Arabican (its binary changes through
  `QuranText`, `NoorUI` and `Localization`): **not uploaded**. `make release-testflight-arabican` archived, then the
  export failed twice with `error: exportArchive Failed to Use Accounts` / `App Store Connect access for "NBMD2V39VV"
  is required. Ensure that your Apple Account usernames and passwords are correct in Accounts settings.`
  (`.build/testflight/arabican/export.log`), minutes after the Quran upload succeeded with the same account. Needs the
  owner to re-sign in to Xcode > Settings > Accounts, then rerun `make release-testflight-arabican` on `f03021d8` or later.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- C2 slice (c): occurrence list (paged, cancellable; `WordStudyService.occurrences` exists and is tested) that jumps
  to the ayah and returns; measure the `ال` (8,377) and و lists on the main actor; tap-to-hear the word from the
  Afasy word timings, labeled as an excerpt of connected recitation; a word pointer entry.
- Make Arabican's `Tools/learning/morphology.py` read the shared database or tool instead of re-parsing QAC
  (Arabican change, its own release).
- Upload Arabican from `f03021d8` or later once the owner has re-signed in to Xcode (above).
- Teacher review of `Grammar.strings`; translate it once reviewed terms exist.
