# Quran H5 — Similar verses and confusion drills

- **Date:** 2026-11-27
- **Agent:** Codex
- **Type:** feature
- **Status:** verified
- **Related:** [H4 spot tests](2026-11-27-h4-spot-tests.md), [H3 review queue](2026-11-27-h3-memorization-map-and-review-queue.md), [roadmap H5](../agents/quran-prioritized-roadmap.md#h5--similar-verses)

App: **Quran**. Arabican shares NoorUI and Localization and goes through the shared-module verification and release lanes.

## Context

The owner asked to finish H4 and continue H5. H5 brings similar ayahs into the reader's study menu and gives learners two ways to test recall. The owner downloaded the [QUL Similar Ayah SQLite export](https://qul.tarteel.ai/resources/similar-ayah/74) and the [QUL Mutashabihat JSON export](https://qul.tarteel.ai/resources/mutashabihat/73).

## Decisions

- `Tools/build-similar-verses.py` canonicalizes each pair, verifies every reference, and requires the two Mutashabihat indexes to agree. The Mutashabihat archive uses a `.json.bz2` suffix and contains a ZIP with `phrases.json` and `phrase_verses.json`.
- Word n-grams come from the 6,236 ayahs in `arabic_text` of the bundled Uthmani database. The search table prepends a Basmala to some sura openings. The importer removes annotation marks and folds alef variants for comparison. The sheet displays the original Uthmani words.
- The reader offers a pair when at least one QUL export lists it and canonical words share a contiguous bigram. The audit retains every QUL-only and canonical 4-gram-only candidate. Review decisions apply by category. Longer thematic relationships without a canonical sequence and unlabeled candidates stay out of the drill pool. For example, 1:6 and 10:25 share a guidance theme with different wording. 2:2 and 10:37 share a four-word sequence and lack a QUL pair in the supplied exports. The QUL links 1:1 to 27:30 and 109:3 to 109:5 are independently corroborated. This review did not adjudicate every pair individually.
- A continuation uses the next ayah within each sura and requires distinguishable answer text. An ending hides one to three final words and lets the learner recite and then reveal and self-grade. Drills record one manual correct or mistake outcome against the expected ayah via `MemorizationService.recordSession`. The alternative ayah and the text of the learner's response are not stored.
- The study sheet uses the existing reader navigation and audio banner, and restores the opening ayah when the learner closes after jumping to or playing another ayah. The ayah menu offers the entry for a single selected ayah. The roadmap's optional inline marker remains a follow-up.

### Source audit

| Input | SHA-256 |
|---|---|
| QUL resource 74 `matching-ayah.db.zip` | `f0d911bdff94e1e95dd63224bdae4c1885c24933bb6bc957caac6d37dbc06cec` |
| QUL resource 73 `Mutashabihat ul Quran.json.bz2` | `2ac8d84e90cf885980ee91756e77240c6bb69b701b4b202d3df282bd2a9181c1` |
| `Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db` | `4db2c1d0416c7f38dedd202a4cca78cee5ffdbeed42929b25439b1fb514f00db` |

Importer output was `6236 canonical verses; 2336 Similar Ayah pairs; 17862 Mutashabihat pairs` and
`17434 corroborated pairs; 1951 QUL-only; 3175 index-only`. The bundle stores one row per unordered
pair. The `sources` and `shared_ngram` columns record each disagreement and its eligibility for the sheet.

## Trade-offs

- **Complexity added:** an offline importer and fixture tests, one read-only GRDB lookup and a 740 KiB bundle, one domain comparison service, the reader sheet and two drill states, and 10 keys in 16 catalogs. The feature uses existing persistence, permissions, entitlements and audio. A broken resource or failed evidence write has a retry path.
- **Who benefits:** memorization learners revising similar passages. The compare sheet and both drill types are likely rarely used by readers outside this group (UNVERIFIED).
- **Cheaper alternatives considered:** QUL references alone would provide wider coverage with less review, but the roadmap calls for an independent wording check. An in-app index would reconstruct static data on a learner's device. The offline index limits runtime work to a small indexed lookup and the verses being compared.
- **Ongoing cost:** refresh and re-audit QUL exports when they change, maintain translations, and carry the bundle in Quran. No launch timing or peak memory measurements were taken. I/O starts when the sheet opens.

## Changes

- `Tools/build-similar-verses.py` and `Tools/build-similar-verses.test.py` compile and validate the shipped H5 database.
- `Data/VerseTextPersistence` reads corroborated matches. `Domain/MemorizationService` bundles the index and builds differences, continuation choices, and ending prompts from real Quran text.
- `Features/HifzReviewFeature` hosts the study sheet and submits drill grades to the same evidence store as Practice and Spot Test.
- `Features/QuranViewFeature`, `Features/AyahMenuFeature`, and NoorUI wire the single-ayah action to the reader's current audio and navigation.
- One iPhone and iPad implementation. The comparison stacks at accessibility Dynamic Type sizes.

## Tests

- Importer tests use fixture ZIPs with the upstream schema. They check reciprocal links, both disagreement classes, rejection of unknown verses and inconsistent phrase indexes, atomic replacement and repeatability.
- `SimilarVerseServiceTests` check the bundled relationships, changed words and continuation boundaries. `SimilarVersesViewModelTests` exercise the real Uthmani DB and Core Data store, including abandoned reveals and duplicate submission. The playback regression test covers stopping and returning to the opening ayah once on dismissal.

## Validation

- **Verified:**
  - The importer fixture suite reported `Ran 4 tests` and `OK`. The original downloads rebuilt the bundled DB byte-for-byte. `PRAGMA quick_check` returned `ok`.
  - `make format-lint`: `0/1288 files require formatting, 65 files skipped.`
  - The test-first run reported `cannot find 'SimilarVerseService' in scope` before the H5 comparison code was added.
  - `make test-no-sync TARGET=MemorizationServiceTests`: `Executed 43 tests, with 0 failures (0 unexpected)`.
  - `make test-no-sync TARGET=HifzReviewFeatureTests`: `Executed 10 tests, with 0 failures (0 unexpected)`. Before the audio lifecycle fix the added test failed because the reader did not return to the opening ayah.
  - `make test-no-sync TARGET=LocalizationTests` and `make test-sync TARGET=LocalizationTests` each reported `Executed 53 tests, with 0 failures (0 unexpected)`.
  - Final `make test-no-sync`: `Test Succeeded`. Result bundle reports 1,794 passed, 0 failures, 0 skips.
  - Final `make test-sync`: `Test Succeeded`. Result bundle reports 2,275 passed, 0 failures, 0 skips.
  - Final `make test-arabican`: `Test Succeeded`. Result bundle reports 117 passed, 0 failures, 0 skips.
  - `make test-tools` exited 0, including `Ran 4 tests` and `OK` for the H5 importer.
  - `make build-example-no-sync`, `make build-example-sync`, and `make build-arabican` each reported `Build Succeeded`. Restored Xcode's generated root `Package.resolved` after the sync build.
  - Temporary iPhone 18 Pro Max UI tests for the ayah-menu entry at 109:3, continuation choice, saved-grade feedback, portrait Large, and Dark Accessibility Extra Large reported `** TEST SUCCEEDED **`. Checked the comparison cards and visible selector in screenshots, and visually confirmed that the comparison stacked at Accessibility Extra Large. The simulator returned to Light and Large.
  - The follow-up temporary simulator test exercised the visible selector and captured the settled landscape comparison. It reported `** TEST SUCCEEDED **`.
- **Not verified:** physical-device audio routing, VoiceOver, compact iPhone, iPad split view, and native localization review. The ending self-grade was exercised through the view model with real Core Data.

## Release

- **Commit:** feature commit tracked by this trail. The release record will include its SHA.
- **TestFlight:** pending.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Run both H5 TestFlight lanes and record the upload receipts.
- Owner checks on iPad split view, compact iPhone, VoiceOver, and native localization review.
- Continue to H7 foundation and V3b after marking H5 shipped.
