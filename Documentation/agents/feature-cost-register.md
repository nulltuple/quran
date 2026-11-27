# Feature cost register

Read this before adding to, or building on, a feature area, and update its row when you change
the area. It records what each area costs to keep, so trade-off calls in trail entries rest on
numbers rather than impressions.

**Measured 2026-11-24** at upstream commit `4c0f57a3`, with:

```sh
find Features/<Name>/Sources -name '*.swift' | wc -l                       # files
find Features/<Name>/Sources -name '*.swift' -print0 | xargs -0 cat | wc -l  # lines
find Features/<Name>/Tests -name '*.swift' | wc -l                          # test files
```

Usage is UNVERIFIED for every row: the app ships `LoggingAnalyticsLibrary`
(`Example/QuranEngineApp/Classes/Container.swift`), which only logs locally, so there is no usage
data. "Core" below is a judgment about a Quran reader's main job (reading, listening, finding,
remembering a place), not a measurement.

## Shared layers

| Layer | Source files | Lines | Test files |
|---|---:|---:|---:|
| Core | 70 | 4,600 | 21 |
| Model | 71 | 4,764 | 20 |
| Data | 71 | 6,420 | 33 |
| Domain | 99 | 8,069 | 59 |
| UI (NoorUI, UIx) | 228 | 22,663 | 58 |

## Features

| Feature | Files | Lines | Test files | Core? | Notes for agents |
|---|---:|---:|---:|---|---|
| SettingsFeature | 35 | 4,304 | 13 | yes | Largest feature. Measured 2026-11-26 (F2): adds the no-sync Backup & Restore screen (`Sources/Backup`, 3 files, 373 lines). Share, review, donate and contact actions still point at Quran.com (see the 2026-11-24 trail entry's follow-ups). |
| BookmarksFeature | 21 | 2,615 | 10 | yes | Measured 2026-11-26 (F1). Since F1 the collection screens run in both modes: no-sync shows My Collections (Favorites + user) and Page Bookmarks; sync adds reading bookmarks, highlights, refresh and the Old Page Bookmarks tip behind `#if QURAN_SYNC`. Check both sync modes. |
| AppStructureFeature | 26 | 2,470 | 11 | yes | Launch, tabs and store setup; high regression risk. |
| WhatsNewFeature | 13 | 2,183 | 3 | no | Release notes (`whats-new.plist`), the app-icon reveal and the sync reveal. Its notes were written for upstream releases (UNVERIFIED which apply to this app); candidate for trimming. |
| QuranViewFeature | 7 | 1,897 | 5 | yes | The reader. Performance-critical (page turns). |
| NotesFeature | 12 | 1,684 | 4 | yes | |
| MoreMenuFeature | 19 | 1,409 | 1 | yes | Reader options. Thin test coverage. |
| QuranTranslationFeature | 8 | 1,341 | 5 | yes | Since 2026-11-26 the ayah-number capsule shows collection and note marks in both builds (reading-bookmark marks stay sync-only); without sync only notes with text get the note mark. |
| QuranImageFeature | 6 | 1,110 | 5 | yes | Page images; memory-sensitive. |
| ReadingSelectorFeature | 10 | 1,000 | 2 | yes | The Example bundles only `hafs_1405`; since R1 (2026-11-26) Hafs 1421, 1439, 1440, 1441 and Tajweed download from `files.quran.app` (`Domain/ReadingService/Sources/QuranAppReadingRemoteResources.swift`, 65 lines); IndoPak stays hidden (no verified pack). One edition on disk at a time, 52–144 MB. |
| AudioBannerFeature | 4 | 903 | 2 | yes | |
| HomeFeature | 6 | 866 | 0 | yes | No tests; add coverage when touching it. |
| QuranContentFeature | 6 | 763 | 2 | yes | |
| ReadingBookmarkMenuFeature | 5 | 714 | 3 | yes | |
| TranslationsFeature | 5 | 709 | 1 | yes | |
| AdvancedAudioOptionsFeature | 6 | 681 | 2 | no | Ayah range, verse and list repeat counts, delays. Likely used by a minority of listeners (UNVERIFIED). |
| SearchFeature | 7 | 1,222 | 2 | yes | Thin test coverage for text search. V1 voice search (2026-11-27, +2 files, ~495 lines, 1 test file): a mic button on the Search tab opens Search by Recitation (listen until a pause, recognize on the device, top 5 verses, choose when unsure). Offers the 84 MB model download first. Links `RecitationRecognition` into the feature; 30 strings in 16 catalogs (agent translations). Loads the model when the sheet opens and drops it when it closes (~852 MB footprint while loaded on the simulator; phone UNVERIFIED). |
| AyahMenuFeature | 4 | 577 | 2 | yes | |
| NoteEditorFeature | 4 | 573 | 1 | yes | |
| AudioDownloadsFeature | 5 | 569 | 1 | yes | |
| WordPointerFeature | 3 | 551 | 1 | no | Word pointer over the page. Likely niche (UNVERIFIED). Since M1 (2026-11-24) it reads `word_by_word.db` (all 6,236 ayahs, English/Bengali/transliteration); upstream's `words.db` is gone. Since C2 c2 (2026-11-26) a released word's popover stays 4 s and opens the word study sheet (a button over the popover, `ByPassTouchesView.secondaryCatchTouchesView`). |
| Word-by-word recitation (cross-cutting, 2026-11-24) | ~32 | ~2,100 | 11 | no | Recited-word highlight and English/Bengali meanings. Bundled data +11.0 MB (`qul_afasy.db` 3.1 MB, `word_by_word.db` 8.4 MB; `words.db` removed). Works with one reciter (id 1001). Rebuild with `Tools/fetch-quran-com-words.py` and `Tools/build-qul-word-data.py`; inputs and hashes in `Documentation/agents/quran-roadmap-progress.md`. The time observer runs only for reciters with word timings. M1.4 (2026-11-24): controls translated in all 16 languages; word cells cap at the column width at large text sizes; recited word reads as selected in VoiceOver. M1.5: optional transliteration line in the translation view (off by default, one Bool preference). |
| TranslationVerseFeature | 4 | 404 | 0 | yes | No tests. |
| TafsirFeature | 4 | 475 | 1 | yes | Added 2026-11-26 (C1). Ayah-menu tafsir sheet over downloaded Arabic tafsirs from the translations feed (`Translation.tafsirIDs`); passages via `QuranTextDataService.tafsir(for:translation:)`. No download code of its own. Since 2026-11-26 also English Ibn Kathir and Bengali Ahsanul Bayaan: `Translation.supplementaryTafsirs`, packs from `Tools/build-tafsir-pack.py` on the `tafsir-packs-1` GitHub release; rebuild by hand when Quran.com corrects them. |
| WordStudyFeature (+ morphology data, C2, 2026-11-26) | 7 | 845 | 4 | no | Word study sheet from a word tap in the translation view (word-by-word meaning on): segments, grammar in plain words, root and lemma with Quran-wide counts. Bundled `quran_morphology.db` +5.9 MB (QAC v0.4, `Tools/build-quran-morphology.py`; the same file in `Domain/TestResources`). `GRDBWordMorphologyPersistence` + `WordStudyService` (~240 lines) in the word-text modules. Grammar terms English-only (`Grammar.strings`). Likely used by a minority of readers (UNVERIFIED). C2 slice c1 (2026-11-26): Root and Dictionary form rows open a paged occurrence list (50 per page, read off the main actor); opening an occurrence moves the reader behind the sheet (`WordStudyReaderFollower`, `ContentViewModel.navigate(to:)`) and dismissing returns it. C2 slice c2 (2026-11-26): a Hear row plays the word's excerpt of the Afasy (1001) sura recording with its own `AVPlayer` (`QuranAudioKit` `WordRecitationRetriever`/`WordRecitationPlayer`, ~205 lines), streamed unless the sura is downloaded, pausing the main recitation first; the Mushaf pointer keeps a released word's popover 4 s and a tap opens its study. Likely rarely used (UNVERIFIED). |
| Recitation recognition engine (Domain `RecitationRecognition`, V0, 2026-11-26) | 10 | ~1,020 | 10 | no | On-device Quran recitation → transcript → ranked verses; no screen uses it yet (V1 voice search will). Core ML only, no third-party runtime (ONNX Runtime's iOS binaries are unobtainable since 2026-11-17, V0 trail). The model is **not bundled**: Tilawi's FastConformer CTC (CC-BY-4.0) converted by `Tools/recitation-model.py` to 125 MB (int8, iOS 16) or 83 MB (int4, iOS 18), built locally by `make recitation-model` into git-ignored `.cache/`; shipping it needs a download host (owner decision, V0 trail). Matcher indexes the bundled `verses` search text (~6,236 rows, built once, ~1 s in tests). `GRDBQuranVerseTextPersistence.searchTextOfAllVerses` (+20 lines) is shared with Arabican's import. Test fixtures +459 KB of EveryAyah MP3s. V0 (b) (2026-11-27): +3 files, ~315 lines: `WordAligner` maps recited words (with CTC frames) to canonical `Word`s read from the Uthmani text (`ExpectedWordsReader`, over `WordByWordService.textLayouts`); O(recited × expected) letter comparisons, so align to identified verses only; module now depends on `VerseTextPersistence` and `WordTextService`. |
| RecitationLabFeature (V0 (c) developer screen, 2026-11-27) | 4 | ~460 | 1 | no | Settings > Diagnostics > Developer tools (one Bool preference, off by default) > Recitation Lab: microphone → transcript, verses, timed canonical words, latency and memory numbers. English only (developer screen). Adds the microphone usage string; links `RecitationRecognition` (Core ML, AVFoundation; system frameworks) into the app. Domain additions: `RecitationModelStore`, `RecitationVerseText`, `RecitationMicrophone` (~210 lines). Model not bundled: D7 (2026-11-27) publishes it as the `recitation-model-1` GitHub release (84 MB zip, sha256 pinned); `RecitationModelDownloader` (~120 lines) fetches it with `DownloadManager`, checks and unzips it. The release asset must never be deleted or replaced. Rarely used by design; ~852 MB footprint while recognizing on the simulator. V1 (2026-11-27): the lab now loads through the shared `RecitationEngineLoader` (Domain, ~60 lines) that voice search uses too; `EndOfRecitationDetector` (~90 lines, pure) ends listening at a pause. |
| Local verse collections (Data + Domain, M3, 2026-11-25) | 4 | 522 | 2 | yes | No-sync store for Favorites and user collections: `Data/CollectionPersistence`, `Domain/AnnotationsService/Sources/PersistenceAyahBookmarkCollectionService.swift`, Core Data model `Quran 3`. Same API as the MobileSync `AyahBookmarkCollectionService`; change both together. UI since F1 (2026-11-26): Bookmarks tab and the ayah menu's Bookmark sheet in the no-sync build; highlights stay note-based without sync. |
| Backup and restore (Data + Domain + Settings, F2, 2026-11-26) | 6 | 1,214 | 3 | yes | No-sync only (the Core Data store holds user records only without sync). `Data/BackupPersistence` (snapshot, merge/replace restore in one save), `Domain/BackupService` (JSON format `com.nulltup.memquran.backup` schema 1, validation), `SettingsFeature/Sources/Backup`. Every new user-authored Core Data entity (H1's learning store) must be added to the snapshot, the restore and a new schema version. |
| FeaturesSupport | 7 | 351 | 1 | infra | Shared feature helpers; extend before adding new helpers elsewhere. |
| QuranPagesFeature | 3 | 337 | 0 | yes | No tests. |
| ReciterListFeature | 4 | 307 | 0 | yes | No tests. |
| AppMigrationFeature | 6 | 295 | 2 | infra | Data migrations; user-data-sensitive. |
| AppIconFeature | 4 | 247 | 1 | no | Alternate icon picker with two icons; rarely used, cheap to keep. |
| AppDependencies (+Fake) | 2 | 221 | 0 | infra | The dependency container protocol. |

## Arabican (second app, `ArabicLearning/` + `Apps/Arabican/`)

Arabican is a separate app (App Store Connect "Arabican", `com.nulltup.arabican`). Its cost is
not part of the Quran app's binary; the only shared cost is QuranEngine modules it imports and
any case or initializer added to them for it. Count with the same commands under
`ArabicLearning/Sources` and `ArabicLearning/Tests`.

| Module or area | Files | Lines | Test files | Notes for agents |
|---|---:|---:|---:|---|
| ArabicLearning package, L0 (2026-11-25) | 4 | 172 | 3 | `LearningModel` (skill ids, presentation profile) and `LearningUI` (4-tab shell). Imports QuranEngine's `NoorUI` (and through it most UI and model modules), so Arabican's binary carries those. Shared additions to QuranEngine: three `NoorSystemImage` cases. |
| ArabicLearning package, L1 (2026-11-25) | 11 | 804 | 7 | Adds `ArabicScript` (letters, marks, graphemes; tested on all 6,236 ayahs), `LearningContent` (read-only compiled DB, 140 KB) and the Learn list. Content compiler `Tools/learning/` (Python, 691 lines incl. tests). Shared change: `QuranKit.Word: Sendable`. |
| ArabicLearning package, L3 (2026-11-26) | 30 | 2,715 | 14 | Adds letter audio (140 Antura clips, AAC in `.caf`, +1.7 MB), stroke guides (Noorine), find-in-word (`word_letter`), `TraceChecker` and `TracingCanvas`, U3 (13 lessons). Content DB 296 KB, schema 2. Tools: `audio.py`, `strokes.py`. Tracing is the feature most likely to be rarely used (~280 lines). |
| ArabicLearning package, L4 (2026-11-26) | 33 | 3,485 | 17 | Adds `ReadableWord` (reading features per grapheme), reading exercises and the `audioChoice` kind, compiler-made unit checks over 504 held-out check words, placement (`PlacementTest`, `placement` table: user data, migration v2). U4–U7 (13 lessons + 6 checks). Content DB 420 KB, schema 3. Placement is the feature most likely to be rarely used (~100 lines + one table). |
| ArabicLearning package, L5 (2026-11-26) | 39 | 4,505 | 21 | Adds the Quran tab reader (bridge suras, recited-word highlight, word sheet), record and compare (`AyahRecorder`: microphone permission, one temp file), U8 bridge and U9 vocabulary exercises, lemmas and word segments from QAC (`Tools/learning/morphology.py`). Bundles 3.3 MB of Afasy MP3s; content DB 750 KB, schema 4. Record and compare is the feature most likely to be rarely used (~110 lines + a permission). |
| ArabicLearning package, L6 (2026-11-26) | 41 | 4,761 | 23 | Adds tajweed foundations: `TajweedRule`/`TajweedExample`, `tajweedExamples(bridges:)`, spot and listen exercises, `TajweedAyahText` (underline + letters line: the Quran font's ligatures drop color). Tool `Tools/learning/tajweed.py` (quran-transcript in a scratch virtualenv + Quran.com markup, cross-checked; `05-tajweed-crosscheck.md`). Content DB 768 KB, schema 5. No new permission or dependency in the app. |
| ArabicLearning package, L7 (2026-11-26) | 43 | 5,008 | 25 | Adds progressive substitution (`ProgressiveSubstitution`, reader meaning line: known words in Arabic) and a per-profile meaning language (`MeaningLanguage`, `profile.meaning_language`: user data, migration v2), `PerformanceBudgetTests`. Export/import and the attribution screen were cut by the owner. The meaning line is the feature most likely to be rarely used before U10 (~80 lines). |
| ArabicLearning package, L2 (2026-11-25) | 26 | 2,146 | 11 | Adds `LearningEngine` (mastery, DAG, FSRS via swift-fsrs 6.0.0, planner), `ExerciseKit` (seeded generators, graders), `LearningPersistence` (GRDB, one progress file per profile: user data, needs migrations), profile setup, Practice and Progress tabs. |
