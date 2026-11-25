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
| SettingsFeature | 32 | 3,899 | 12 | yes | Largest feature. Share, review, donate and contact actions still point at Quran.com (see the 2026-11-24 trail entry's follow-ups). |
| BookmarksFeature | 22 | 2,636 | 9 | yes | Several sources branch on `QURAN_SYNC` (for example `BookmarksPreferences.swift`); check both sync modes. |
| AppStructureFeature | 26 | 2,470 | 11 | yes | Launch, tabs and store setup; high regression risk. |
| WhatsNewFeature | 13 | 2,183 | 3 | no | Release notes (`whats-new.plist`), the app-icon reveal and the sync reveal. Its notes were written for upstream releases (UNVERIFIED which apply to this app); candidate for trimming. |
| QuranViewFeature | 7 | 1,897 | 5 | yes | The reader. Performance-critical (page turns). |
| NotesFeature | 12 | 1,684 | 4 | yes | |
| MoreMenuFeature | 19 | 1,409 | 1 | yes | Reader options. Thin test coverage. |
| QuranTranslationFeature | 8 | 1,341 | 5 | yes | |
| QuranImageFeature | 6 | 1,110 | 5 | yes | Page images; memory-sensitive. |
| ReadingSelectorFeature | 10 | 1,000 | 2 | yes | The Example bundles only `hafs_1405`; other readings need remote resources. |
| AudioBannerFeature | 4 | 903 | 2 | yes | |
| HomeFeature | 6 | 866 | 0 | yes | No tests; add coverage when touching it. |
| QuranContentFeature | 6 | 763 | 2 | yes | |
| ReadingBookmarkMenuFeature | 5 | 714 | 3 | yes | |
| TranslationsFeature | 5 | 709 | 1 | yes | |
| AdvancedAudioOptionsFeature | 6 | 681 | 2 | no | Ayah range, verse and list repeat counts, delays. Likely used by a minority of listeners (UNVERIFIED). |
| SearchFeature | 5 | 671 | 1 | yes | Thin test coverage. |
| AyahMenuFeature | 4 | 577 | 2 | yes | |
| NoteEditorFeature | 4 | 573 | 1 | yes | |
| AudioDownloadsFeature | 5 | 569 | 1 | yes | |
| WordPointerFeature | 3 | 456 | 1 | no | Word pointer over the page. Likely niche (UNVERIFIED). |
| Word-by-word recitation (cross-cutting, 2026-11-24) | ~30 | ~1,900 | 9 | no | Recited-word highlight and English/Bengali meanings from QUL. Costs +10.3 MB of bundled data (`qul_afasy.db`, `word_by_word.db`) and works with one reciter (id 1001). Rebuild the data with `Tools/build-qul-word-data.py`. See the 2026-11-24 word-by-word trail entry. |
| TranslationVerseFeature | 4 | 404 | 0 | yes | No tests. |
| FeaturesSupport | 7 | 351 | 1 | infra | Shared feature helpers; extend before adding new helpers elsewhere. |
| QuranPagesFeature | 3 | 337 | 0 | yes | No tests. |
| ReciterListFeature | 4 | 307 | 0 | yes | No tests. |
| AppMigrationFeature | 6 | 295 | 2 | infra | Data migrations; user-data-sensitive. |
| AppIconFeature | 4 | 247 | 1 | no | Alternate icon picker with two icons; rarely used, cheap to keep. |
| AppDependencies (+Fake) | 2 | 221 | 0 | infra | The dependency container protocol. |
