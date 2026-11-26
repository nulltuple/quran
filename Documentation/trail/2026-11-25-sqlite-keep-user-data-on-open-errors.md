# Quran: SQLite user-data stores no longer delete their file on open errors

- **Date:** 2026-11-25
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** fix
- **Status:** shipped
- **Related:** [2026-11-25-arabican-l2-engine-profiles-practice.md](2026-11-25-arabican-l2-engine-profiles-practice.md)
  (found the problem; Arabican's learner store avoids `DatabaseConnection` because of it),
  [2026-11-25-m3-1-local-verse-collections-store.md](2026-11-25-m3-1-local-verse-collections-store.md)
  (earlier no-sync personal-data audit)

App: **Quran** (shared QuranEngine module `SQLitePersistence`, which Arabican also links).

## Context

While building Arabican's learner store, an agent found that `DatabaseConnection` deletes the
database file whenever GRDB reports `SQLITE_PERM`, `SQLITE_NOTADB`, `SQLITE_CORRUPT` or
`SQLITE_CANTOPEN`, on open, read, write or migration (the private `PersistenceError.init(_:databaseURL:)`,
then `Data/SQLitePersistence/Sources/DatabaseConnection.swift:162-178` at `6a940160`). That suits
re-downloadable files, whose download sometimes completes broken, but it erases user data if a
user-data store opens through `DatabaseConnection`. `SQLITE_CANTOPEN` can also be transient, for
example under file protection while the device is locked. This task audits every caller and
closes the hole.

The same initializer assigned `self` up to three times without returning, so the final
`self = PersistenceError.query(error)` always won: `.badFile` was never reported, and a
`PersistenceError` thrown from a read or write block came back wrapped in `.query`. Confirmed by
the regression tests below (with the early returns removed they report
`Expected .badFile, got ...query(SQLite error 26: file is not a database ...)`). Nothing in the
repository switches on `.badFile` or `.query` (`git grep -n "badFile\|case .query"`), so reporting
the right case changes no behavior beyond the error value.

### Audit: every `DatabaseConnection(` caller

`git grep -n "DatabaseConnection(" -- 'Data/*.swift' 'Domain/*.swift' 'ArabicLearning/*.swift'` (tests excluded):

| Caller | File | Mode | Holds | Class | Deletes on bad file |
|---|---|---|---|---|---|
| `GRDBSyncedPageBookmarkPersistence(directory:)` (`Data/SyncedPageBookmarkPersistence/Sources/GRDBSyncedPageBookmarkPersistence.swift:29`) | `pagebookmarks.db` | read-write | the user's page bookmarks | **user data** | **no (changed)** |
| `GRDBActiveTranslationsPersistence(directory:)` (`Data/TranslationPersistence/Sources/GRDBActiveTranslationsPersistence.swift:28`) | `Documents/translations.db` | read-write | translations catalog and installed versions | rebuildable: `TranslationsRepository.downloadAndSyncTranslations` refills it from the server (`Domain/TranslationService/Sources/TranslationsRepository.swift:39`), and `TranslationsVersionUpdater` re-derives `installedVersion` from the files on disk (`Domain/TranslationService/Sources/TranslationsVersionUpdater.swift:45-63`). Selected translations live in preferences (`SelectedTranslationsPreferences`), not here | yes (unchanged) |
| `GRDBDownloadsPersistence(fileURL:)` (`Data/BatchDownloader/Sources/Downloader/GRDBDownloadsPersistence.swift:27`) | `Documents/downloads.db` (`Example/QuranEngineApp/Classes/Container.swift:78`) | read-write | in-flight download bookkeeping | rebuildable: losing it loses track of running downloads, which the user can start again | yes (unchanged) |
| `GRDBAyahTimingPersistence` (`Data/AudioTimingPersistence/Sources/GRDBAyahTimingPersistence.swift:22`) | audio timing db | read-only | downloaded content | re-downloadable | yes (unchanged) |
| `GRDBLinePagePersistence` (`Data/LinePagePersistence/Sources/GRDBLinePagePersistence.swift:22`) | line-page db | read-only | bundled or downloaded content | re-downloadable | yes (unchanged) |
| `GRDBDatabaseVersionPersistence` (`Data/VerseTextPersistence/Sources/GRDBDatabaseVersionPersistence.swift:20`) | translation and text files | read-only | downloaded content | re-downloadable | yes (unchanged) |
| `GRDBVerseTextPersistence` (`Data/VerseTextPersistence/Sources/GRDBVerseTextPersistence.swift:146`) | Quran text, translations | read-only | bundled or downloaded content | re-downloadable | yes (unchanged) |
| `GRDBWordFramePersistence` (`Data/WordFramePersistence/Sources/GRDBWordFramePersistence.swift:22`) | word frames | read-only | bundled or downloaded content | re-downloadable | yes (unchanged) |
| `GRDBWordByWordPersistence` (`Data/WordTextPersistence/Sources/GRDBWordByWordPersistence.swift:31`) | `word_by_word.db` | read-only | bundled content | re-downloadable (the bundle is read-only, so removal fails) | yes (unchanged) |
| `LearningContentStore` (Arabican, `ArabicLearning/Sources/LearningContent/LearningContentStore.swift:20`) | bundled content db | read-only | bundled content | bundle, removal fails | yes (unchanged) |

Where the rest of the user's data lives: the Core Data store `Quran` (notes, ayah and page
bookmarks, last pages, collections; see the M3.1 entry) and, in sync builds, MobileSync's own
database. Neither goes through `DatabaseConnection`. No other `DatabaseQueue(`/`DatabasePool(` is
opened in `Core/ Data/ Domain/ Features/ Example/` outside tests (`git grep`).

**Exposure:** `pagebookmarks.db` was the only user-data store on the deleting path. It is not
reachable from the shipped app today: no target depends on `SyncedPageBookmarkPersistence`
(`Package.swift:246` is its only mention), so this was a latent hole, closed before anything wires
it up.

## Decisions

- **Opt-out flag, default unchanged.** `DatabaseConnection.init(url:readonly:deletesBadFile:)`
  with `deletesBadFile = true` keeps every existing caller's behavior and source compatible; user
  data passes `false`. A safer default (`false`, or "only read-only files") was rejected: it would
  stop `translations.db` and `downloads.db` from healing themselves after a real `SQLITE_NOTADB`,
  and would silently change behavior for Arabican's caller. The doc comment on the initializer
  tells future user-data stores to pass `false`.
- **The flag applies on every path** (pool open, `read`, `write`, `readPublisher`'s open, and
  `DatabaseMigrator.migrate(_:)`), because a `SQLITE_CORRUPT` during a query also deleted the file.
- **Pooled connections:** the pool opens a URL once; the first opener's flag governs the open,
  each connection's own flag governs its later read and write errors. Only one store opens
  `pagebookmarks.db`, so the two never disagree in practice.
- **`translations.db` and `downloads.db` keep deletion.** Both are rebuildable (table above).
  Deleting either on a transient `SQLITE_CANTOPEN` costs a catalog refetch or a re-started
  download, not user content.
- **The `PersistenceError` initializer is now internal** (was `private extension`) so the tests
  can reach it through `@testable import`; it stays non-public.

## Trade-offs

- **Complexity added:** one `Bool` parameter and stored property on `DatabaseConnection`, threaded
  through the pool (`DatabaseConnection.swift`, +44/-24 lines), one argument at one caller.
  No new dependencies, permissions, entitlements, background work or persisted formats. New failure
  mode, by design: a user-data file that is really corrupt now stays on disk and keeps failing
  (`.badFile`), instead of being replaced by an empty database. That is the right failure for user
  data: the file can be recovered or exported; an empty database cannot.
- **Who benefits / how often:** nobody today, since `pagebookmarks.db` is unused (see the audit). The
  value is preventing data loss the day a user-data store opens through `DatabaseConnection`, and a
  correct `.badFile` error for diagnostics.
- **Rejected cheaper options:** deleting `SyncedPageBookmarkPersistence` (unused upstream code; a
  deletion is a larger, upstream-diverging change and the owner did not ask); dropping
  `SQLITE_CANTOPEN` from the deletion list for everyone (changes re-download behavior for content,
  out of scope; see Follow-ups); moving the store to a raw `DatabaseQueue` as Arabican did (loses
  the pool and `readPublisher` the store uses).
- **Ongoing cost:** negligible: one parameter to remember when adding a store, documented in the
  initializer. Upstream merges touching `DatabaseConnection.swift` may conflict on the threaded
  parameter.

## Changes

- `Data/SQLitePersistence/Sources/DatabaseConnection.swift`: `deletesBadFile` parameter on
  `DatabaseConnection.init` (line 96) and the pool's open; `PersistenceError.init(_:databaseURL:deletesBadFile:)`
  (line 185) returns from each branch, deletes only when asked, logs whether the file was kept;
  `DatabaseMigrator.migrate(_:)` passes the connection's flag.
- `Data/SyncedPageBookmarkPersistence/Sources/GRDBSyncedPageBookmarkPersistence.swift:29`: opens
  `pagebookmarks.db` with `deletesBadFile: false`.
- Platforms: shared code, iPhone and iPad alike; no UI.
- Feature cost register: no row changed; `SQLitePersistence` is a shared Data module, not a
  feature area.

## Tests

- `Data/SQLitePersistence/Tests/DatabaseConnectionTests.swift` (8 new):
  `test_corruption_reportsBadFile`, `test_corruption_keepsFileWhenDeletionIsOff`,
  `test_migrationOfCorruptFile_keepsFileWhenDeletionIsOff`,
  `test_badFileErrorWhileReading_keepsDataWhenDeletionIsOff` (CANTOPEN, CORRUPT, PERM, NOTADB
  injected as `DatabaseError` from the block; data still readable afterwards),
  `test_badFileErrorWhileWriting_keepsDataWhenDeletionIsOff`,
  `test_badFileErrorWhileReading_deletesFileByDefault`, `test_otherDatabaseError_isQueryErrorAndKeepsFile`,
  `test_persistenceErrorFromBlock_isPassedThrough`. The existing `test_corruption` (default deletes)
  is unchanged.
- `Data/SyncedPageBookmarkPersistence/Tests/GRDBSyncedPageBookmarkPersistenceTests.swift`:
  `testCorruptFileIsKept` opens a corrupt `pagebookmarks.db` through the public
  `init(directory:)` and asserts the bytes survive.
- **Shown to fail without the fix (ran, not reasoned):**
  - Early `return`s removed (the old overwrite): `Executed 14 tests, with 10 failures`, every
    bad-file test reporting `Expected .badFile, got ...query(...)` and the pass-through test
    `Expected .general, got ...query(...general(...))`.
  - Deletion forced regardless of the flag: `Executed 14 tests, with 8 failures (4 unexpected)`;
    all four keep-file tests failed.
  - Page-bookmark store without `deletesBadFile: false`: `Executed 3 tests, with 1 failure`;
    `testCorruptFileIsKept` failed because the file had been deleted and replaced by a fresh
    SQLite database (`The file couldn't be opened because it isn't in the correct format.`).
  Each source file was restored byte-for-byte afterwards (`cmp`).

## Validation

- **Verified:**
  - `make format-lint`: `0/1109 files require formatting, 28 files skipped.`
  - `make test-no-sync TARGET=SQLitePersistenceTests`: `Executed 14 tests, with 0 failures (0 unexpected)`
  - `make test-no-sync TARGET=SyncedPageBookmarkPersistenceTests`: `Executed 3 tests, with 0 failures (0 unexpected)`
  - `make test-no-sync`: xcresult summary `result: Passed, totalTestCount: 1433, passedTests: 1433, failedTests: 0`
  - `make test-sync` (after no-sync, same simulator): `result: Passed, totalTestCount: 1927, passedTests: 1927, failedTests: 0`
  - `make build-example-no-sync` and `make build-example-sync`: `Build Succeeded` each
  - `make test-arabican` (its own simulator, alongside the Quran runs): `result: Passed, totalTestCount: 49, passedTests: 49, failedTests: 0`
  - `make build-arabican`: `Build Succeeded`
- **Not verified:** a real transient `SQLITE_CANTOPEN` on a locked device (simulated by injecting
  `DatabaseError(resultCode: .SQLITE_CANTOPEN)`; file protection cannot be exercised in unit tests).

## Release

- **Commit:** filled in after commit.
- **Pushed:** filled in after push.
- **TestFlight:** filled in after upload.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Deleting a bad file removes only the main file, not its `-wal` and `-shm` siblings
  (`DatabasePool` uses WAL). A stale WAL beside a re-downloaded file is a corruption risk. Pre-existing,
  not changed here.
- `badFileCodes.contains(error.extendedResultCode)` misses extended codes such as
  `SQLITE_CORRUPT_INDEX` or `SQLITE_CANTOPEN_ISDIR` (exact equality on the extended code).
  Matching the primary `resultCode` would widen deletion, so it needs its own decision.
- Consider not deleting re-downloadable files on `SQLITE_CANTOPEN` either: a transient lock forces
  a large re-download of a translation or word database.
- `SyncedPageBookmarkPersistence` is unused upstream code; if M4 sync never needs it, delete it.
