# M3.1: audit of no-sync personal data, and a local store for verse collections

- **Date:** 2026-11-25
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-24-prioritized-quran-roadmap.md](2026-11-24-prioritized-quran-roadmap.md),
  [Documentation/agents/quran-roadmap-progress.md](../agents/quran-roadmap-progress.md) (M3 rows)

## Context

The owner asked to skip M2 (more reciters) and start M3 (local-first personal data), "starting with a
check of which data stores and features exist without sync". The roadmap's M3 item asks for local
verse collections, colored highlights and verse bookmarks "if absent from shipping mode", extending
shared interfaces instead of adding parallel stores, with no login.

### Audit: what the TestFlight build (`QURAN_SYNC` unset) stores

User-authored data, all in one Core Data store named `Quran` (`Example/QuranEngineApp/Classes/Container.swift:44`),
model `Data/CoreDataModel/Sources/Quran.xcdatamodeld` (current version was `Quran 2`):

| Entity | Feature in the no-sync build | Code |
|---|---|---|
| `MO_Note` + `MO_Verse` | Notes, and verse highlights in 5 colors: a highlight is a note with a color and no text | `Domain/AnnotationsService/Sources/NoteService.swift`, `Features/AyahMenuFeature/Sources/AyahMenuViewModel.swift:187` (`updateHighlight`) |
| `MO_PageBookmark` | Page bookmarks, the Bookmarks tab | `Features/BookmarksFeature/Sources/BookmarksViewModel.swift:8` (`#if !QURAN_SYNC`) |
| `MO_LastPage` | Recent pages ("continue reading") | `Domain/AnnotationsService/Sources/PersistenceLastPageService.swift:10` |

- The store is opened by `NSPersistentCloudKitContainer` (`Data/CoreDataPersistence/Sources/CoreDataStack.swift:123`)
  with history tracking on (`CoreDataStack.swift:209`) and every attribute optional, so the model is
  CloudKit-compatible; CloudKit itself is off (`Container.swift:91`, `supportsCloudKit` is `false`).
  Uniquifiers exist for `MO_LastPage` and `MO_PageBookmark` only (`Container.swift:45-46`).
- Preferences live in `UserDefaults` through `Core/Preferences`.
- Every GRDB/SQLite database under `Data/` holds content or caches, not user data: translations,
  verse text, word frames, word-by-word, audio timings, line pages. `Data/SyncedPageBookmarkPersistence`
  (GRDB `pagebookmarks.db`) is declared in `Package.swift` but no target depends on it: unused upstream
  code, left alone.

### Audit: what only the sync build has

All of these are `#if QURAN_SYNC` and stored in Quran.com's MobileSync database, which also works
without sign-in (`Container.swift:96`):

- Verse collections and Favorites: `Domain/AnnotationsService/Sources/AyahBookmarkCollectionService.swift:1`,
  the collection screens in `Features/BookmarksFeature` (`BookmarkCollections*`, `BookmarkAyahs*`, `AyahSet*`,
  about 2,000 lines), and the ayah menu's Bookmark action (`AyahMenuViewModel.swift:181`).
- Named reading bookmarks (slots): `MobileSyncReadingBookmarkService`, `Features/ReadingBookmarkMenuFeature`.
- Highlights as collections (`MobileSyncAyahHighlightService`), notes over several ranges
  (`MobileSyncNoteService`), ayah indicators (`Model/QuranAnnotations/Sources/AyahIndicator.swift`).
- Account sign-in and sync activity (`Features/SettingsFeature/Sources/AccountSync`), and a one-way
  import of the Core Data store (`Domain/LegacyDataMigration`).

So the TestFlight build has notes, highlights, page bookmarks and recent pages, and lacks verse
bookmarks, collections and named reading bookmarks.

## Decisions

- **Core Data, not MobileSync, for local collections (owner's choice, 2026-11-25).** Asked with three
  options: extend Core Data; ship the sync build without an OAuth client; a minimal bookmark list. The
  owner chose Core Data. It keeps the no-sync build free of the MobileSync binary and keeps M4's
  cheapest path: the stack is already an `NSPersistentCloudKitContainer`.
- **New model version `Quran 3`; `Quran 2` untouched.** `Quran 2` has shipped to TestFlight. The new
  version only adds entities, so Core Data's automatic lightweight migration applies
  (`NSPersistentContainer` migrates and infers mapping models by default; covered by
  `testUpgradingFromTheSecondModelVersionKeepsNotesBookmarksAndLastPages`).
- **Schema:** `MO_Collection` (`id` UUID, `name`, `isDefault`, `createdOn`, `modifiedOn`, to-many
  `verses`, cascade delete) and `MO_CollectionVerse` (`id` UUID, `sura`, `ayah`, `createdOn`, to-one
  `collection`, nullify). All attributes optional, no unique constraints: CloudKit rules for M4.
- **Verse identity is sura and ayah,** not page or mushaf, so a collection shows the same verses in
  every layout (the roadmap's "canonical identifiers independent of layout"). Verses that don't exist in
  the current reading are left out when shown, not deleted.
- **No tombstones.** `NSPersistentCloudKitContainer` mirrors deletions itself, so the store deletes rows.
  Revisit only if M4 chooses another sync design.
- **Favorites has a fixed UUID** (`AyahBookmarkCollectionService.defaultCollectionID`) and is stored the
  first time it gets a verse. Until then the service lists it anyway. Two devices create the same ID, so a
  later sync can merge them instead of showing two Favorites. It is read-only, like the sync build's.
- **Same type name as the sync service.** No-sync builds get a struct named `AyahBookmarkCollectionService`
  (`PersistenceAyahBookmarkCollectionService.swift`) with the sync struct's public API and errors. The
  collection screens can then compile in both modes unchanged in M3.2, with no new protocol. The
  alternative, a protocol with two implementations like `LastPageService`, would also have changed every
  sync-mode initializer and test.
- **Name rules match the sync build's tests:** trimmed length 1 to 255
  (`Features/BookmarksFeature/Tests/BookmarkAyahsViewModelTests.swift:219` asserts 255 against the real
  MobileSync database); duplicates compare trimmed and case-insensitively (the documented sync rule,
  `Model/QuranAnnotations/Sources/BookmarkCollectionErrors.swift`); "Favorites" and `system:` names are
  reserved. The server measures length after HTML-escaping (`TextLengthLimitError.swift`); the local
  store counts characters, so a 255-character local name with `&` could exceed Quran.com's limit if it is
  ever imported there. UNVERIFIED which characters the server escapes.
- **The duplicate check runs inside the write** (`CoreDataCollectionPersistence.checkNameIsFree`), on the
  persistence's serial context, so two quick creates can't both pass it.
- **No wiring into `AppDependencies` yet.** Nothing calls the service until M3.2 adds the screens.
  Shipping the model version first means testers' stores migrate in a build where nothing else changed.

## Trade-offs

- **Complexity added:** one Data target (`CollectionPersistence`, 3 files, 315 lines), one Domain file
  (207 lines), one Core Data model version (2 entities), two model files un-gated in `QuranAnnotations`.
  Tests: 477 lines. No dependency, permission or entitlement. New persisted state: two tables in the
  existing store. New failure mode: a failed lightweight migration on launch, which `LaunchStores`
  already reports like any store-open failure.
- **Who benefits / how often:** nobody yet: there is no UI until M3.2. Verse bookmarks are a core reader
  feature (every major Quran app has them); collections beyond Favorites are likely used by fewer people,
  but they cost nothing extra in the store.
- **Rejected cheaper options:** shipping the sync build (owner declined: MobileSync binary, one-way
  import, M4 CloudKit over MobileSync unproven); a single bookmark list (would be a second UI to remove
  when collections arrive).
- **Ongoing cost:** two collection backends to keep in step, MobileSync's and Core Data's. Their shared
  contract is the service API; a behavior change to one needs the other changed too. The Core Data side
  is small (about 400 lines with the service).

## Changes

- `Data/CoreDataModel/Sources/Quran.xcdatamodeld/Quran 3.xcdatamodel`: new current version with
  `MO_Collection` and `MO_CollectionVerse`; `.xccurrentversion` points at it.
- `Data/CoreDataModel/Sources/Schema.swift`: `Schema.Collection`, `Schema.CollectionVerse` keys.
- `Data/CollectionPersistence/Sources/`: `CollectionPersistence` protocol (following
  `PageBookmarkPersistence`), `CollectionPersistenceModel`, `CollectionVerseID`, `CollectionNameTakenError`,
  `CoreDataCollectionPersistence`.
- `Domain/AnnotationsService/Sources/PersistenceAyahBookmarkCollectionService.swift`: the no-sync
  `AyahBookmarkCollectionService`.
- `Model/QuranAnnotations/Sources/AyahBookmarkCollection.swift`, `BookmarkCollectionErrors.swift`: no longer
  `#if QURAN_SYNC` (plain value types with no MobileSync dependency); sync builds see no change.
- `Package.swift`: `CollectionPersistence` target; `AnnotationsService` depends on it.
- `QuranEngine-Package.xctestplan`: `CollectionPersistenceTests`.
- Platforms: shared layers only, so iPhone and iPad alike; nothing user-visible.

## Tests

- `CollectionPersistenceTests/CoreDataCollectionPersistenceTests` (11 tests, real temporary SQLite store):
  ordering, de-duplicated adds, one verse in several collections, removals, cascade delete, rename and
  `modifiedOn`, case-insensitive unique names, no-ops on missing IDs, data surviving a reopen, and the
  `Quran 2` to `Quran 3` upgrade keeping a note with its verse, a page bookmark and a last page.
- `AnnotationsServiceTests/PersistenceAyahBookmarkCollectionServiceTests` (12 tests, `#if !QURAN_SYNC`,
  real store): Favorites listed before it is stored and stored once, user collections after Favorites,
  add/remove/remove-all, rename/remove, Favorites read-only, reserved names, duplicate names, trimmed
  length limits, ayahs missing from the reading left out, invalid IDs ignored.
- New behavior, not a bug fix, so no fail-before-fix run.

## Validation

- **Verified:**
  - `make test-no-sync TARGET=CollectionPersistenceTests`: `Executed 11 tests, with 0 failures (0 unexpected)`.
  - `make test-no-sync TARGET=AnnotationsServiceTests`: `Executed 47 tests, with 0 failures (0 unexpected)`.
  - `make format-lint`: `0/1069 files require formatting, 19 files skipped.`
  - `make test-no-sync` (full plan): `xcresulttool` summary `Passed`, 1,422 of 1,422 tests (1,399 at
    `cc0e776d`, plus 23 new).
  - `make test-sync` (full plan, run after the no-sync one): `Passed`, 1,916 of 1,916 (1,905 at `cc0e776d`,
    plus the 11 persistence tests; the service tests are no-sync only). The `CoreData: error ... file is not a
    database` lines in its log come from the existing store-recovery tests, which corrupt a temporary store
    on purpose (`TemporaryCoreDataStore.corrupt()`).
  - `make build-example-no-sync` and `make build-example-sync`: `Build Succeeded` each.
- **Not verified:** an upgrade on a real device from TestFlight build 959's store (the migration test
  covers the same model change on a simulator store).

## Release

- **Commit:** `88b60523`
- **Pushed:** origin/main at `88b60523`
- **TestFlight:** build 961 (1.20.3): `Uploaded Quran iOS 1.20.3 (961) for commit
  88b605236628e6c352f8bf74b6fa4c5b94de8b48 to App Store Connect app MemQuran.`
- **iCloud / CloudKit schema:** unchanged (CloudKit stays off; the new entities need a schema deployment
  only when M4 turns it on).

## Follow-ups

- M3.2: wire `CoreDataCollectionPersistence` into `AppDependencies`/`Container`, and make the collection
  screens and the ayah menu's Bookmark action compile without `QURAN_SYNC`. Blockers found: the screens also
  take `MobileSyncAyahHighlightService`, `MobileSyncReadingBookmarkService`, `MobileSyncDataService.syncNow`
  and `SyncSignInNudge`; no-sync needs a highlight service over `NoteService` with the same API, and the
  reading-bookmark and sync parts gated off.
- A uniquifier for `MO_Collection` by `id` (and verses by collection and verse) before CloudKit (M4).
- A user who later moves to a sync build: `LegacyDataMigration` imports notes and page bookmarks but not
  these collections. Not needed while TestFlight is no-sync.
