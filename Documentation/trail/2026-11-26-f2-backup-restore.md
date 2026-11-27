# Quran F2: JSON backup and restore of notes, bookmarks, collections and recent pages

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-25-m3-1-local-verse-collections-store.md](2026-11-25-m3-1-local-verse-collections-store.md)
  (store audit), [2026-11-26-f1-local-collections-ui.md](2026-11-26-f1-local-collections-ui.md),
  roadmap v2 §6 F2 ([quran-prioritized-roadmap.md](../agents/quran-prioritized-roadmap.md))

## Context

App: **Quran** (shared NoorUI change, so Arabican builds too). The owner asked to continue the roadmap from
the first Next step, F2: "Versioned JSON of every user-authored record (notes, highlights, page bookmarks,
collections, last pages) ... Import: validate fully before writing, preview counts, explicit merge or
replace, merge is idempotent by record id, replace is atomic, unknown newer schema refused, corrupt input
refused without touching data. Export via the share sheet; import via the document picker."

The M3.1 audit lists every user-authored record of the no-sync build: one Core Data store `Quran`, model
`Quran 3` (`Data/CoreDataModel/Sources/Quran.xcdatamodeld/Quran 3.xcdatamodel/contents`): `MO_Note` +
`MO_Verse` (notes and highlights), `MO_PageBookmark`, `MO_LastPage`, `MO_Collection` + `MO_CollectionVerse`.
Only collections have IDs; the other entities have none.

## Decisions

- **No-sync only.** In sync builds the user's records live in MobileSync, and the Core Data store is the
  legacy source of a one-way import. The Settings row and screen are `#if !QURAN_SYNC`; the persistence,
  service and view model compile and are tested in both modes.
- **Record identity is the natural key** (the store has no IDs except collections): a note by its verse
  set, page bookmarks and recent pages by mushaf and page, a collection by ID, then by trimmed
  case-insensitive name, a collection verse by sura and ayah. This is the roadmap's "idempotent by record id".
- **Merge rules** (`Data/BackupPersistence/Sources/CoreDataBackupPersistence.swift`, `Restorer`):
  - Note with free verses: added. Same verses as a stored note: the newer text and color win, unless the
    newer text is blank (a highlight over an older note keeps the note text). Overlapping stored notes:
    joined into one, as the note editor does (`CoreDataNotePersistence.createOrUpdateNoteHighlight`), each
    distinct text once (`joinedDistinctTexts`), so a second merge changes nothing.
  - Pages: added, or the stored one keeps the later modified and the earlier created date.
  - Collections: verses are only added, never removed; a newer backup renames a stored collection if the
    name is free; Favorites keeps its name.
  - Values are only assigned when different, so merging a backup that is already there saves nothing
    (`testMergeSavesNothingWhenTheBackupIsAlreadyThere` checks the persistent-history token).
- **Atomic restore:** one background context, deletes (replace) and inserts, one `save`; any throw rolls
  back. All validation (`BackupService.validate`) runs before `restore` can be called: `restore` takes a
  `ValidatedBackup`, which only `readBackup` creates. Recent pages over the store's 10 are trimmed by the
  existing `CoreDataLastPageUniquifier` after the save, as for any write.
- **Format:** `{"format": "com.nulltup.memquran.backup", "schemaVersion": 1, "appVersion", "exportedAt",
  "data": {notes, pageBookmarks, recentPages, collections}}`, pretty-printed, sorted keys, ISO 8601 dates
  with milliseconds. The header is decoded first, so a schema 2 file says "made by a newer version" instead
  of "damaged". Dates within 1 ms count as equal, because the file keeps milliseconds and the store more.
- **Checks before writing:** verse exists in Hafs (`AyahNumber`), page exists in its mushaf, color is a
  `HighlightColor`, note has verses, collection name is 1–255 characters trimmed (the constant moved to
  `AyahBookmarkCollection.nameLengthLimit` so the service and the backup share it), file at most 20 MB.
- **Not in the backup:** preferences (UserDefaults), downloads, the selected mushaf. The export footer says
  so. Page bookmarks' unused `color` attribute is not exported (nothing reads it).
- **UI:** Settings > Backup & Restore (after Translations). Export writes `Quran Backup YYYY-MM-DD.json` to
  a temporary folder, shares it with `UIActivityViewController` (the existing `share` helper), and deletes
  it when the sheet closes. Restore uses SwiftUI `fileImporter` (JSON), reads off the main actor with
  security-scoped access, shows the counts and the export date, then Merge, Replace (destructive
  confirmation) or Cancel. 24 new string keys in all 16 `Localizable.strings` (agent translations, native review
  UNVERIFIED; `LocalizationCatalogTests` requires every key in every catalog).

## Trade-offs

- **Complexity added:** two package targets (`BackupPersistence` 2 files 618 lines, `BackupService` 1 file
  223 lines), 3 Settings files (373 lines), 2 NoorUI symbols, 24 string keys × 16 languages. Tests: 652 lines. No
  dependency, permission or entitlement; no persisted state (temporary export file only); no network.
  New failure mode: a restore that fails to save shows an error and leaves the store unchanged.
- **Who benefits / how often:** rarely used, by design: a backup before reinstalling, moving to a new
  phone, or before H1 changes the schema. It is the only way to move notes between devices until P1
  (iCloud) ships, and it protects user data that has no other copy.
- **Rejected cheaper options:** copying the SQLite file (ties backups to the model version and the
  mushaf-specific internals; no merge or preview); export only (no recovery path); reusing
  `CoreDataLegacyDataReader` (sync-only, maps to MobileSync types, never writes).
- **Ongoing cost:** every new user-authored Core Data entity or attribute (H1's learning records) must be
  added to `BackupSnapshot`, the restore and a schema bump with a reader for the old version. Recorded in
  the feature cost register row.

## Changes

- `Data/BackupPersistence/Sources/BackupSnapshot.swift`: `BackupSnapshot`, `BackupNote`, `BackupPage`,
  `BackupCollection`, `BackupCollectionVerse`, `BackupVerse`, `BackupRestoreMode`.
- `Data/BackupPersistence/Sources/CoreDataBackupPersistence.swift`: `snapshot()`, `restore(_:mode:)`, merge
  rules (`Restorer`).
- `Domain/BackupService/Sources/BackupService.swift`: export, file name, `readBackup` (header, version,
  validation), `restore`, `BackupSummary`, `BackupError`.
- `Features/SettingsFeature/Sources/Backup/`: `BackupBuilder`, `BackupViewModel` (+ `BackupError`
  messages), `BackupView`.
- `Features/SettingsFeature/Sources/SettingsRootView.swift`, `SettingsRootViewModel.swift`,
  `SettingsBuilder.swift`: the no-sync "Backup & Restore" row and navigation.
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: `backup` (`externaldrive`), `restoreBackup`
  (`arrow.down.doc`), alias `exportBackup` (`.share`).
- `Model/QuranAnnotations/Sources/AyahBookmarkCollection.swift`: `nameLengthLimit` (moved from the no-sync
  collection service, which now refers to it).
- `Core/Localization/Sources/Resources/*.lproj/Localizable.strings`: 24 `backup.*` keys in all 16 languages.
- `Package.swift`, `QuranEngine-Package.xctestplan`: the two targets and their test targets; SettingsFeature
  depends on them.
- Platforms: iPhone and iPad share every file; `fileImporter` and the share sheet present as form sheets
  on iPad (the share helper already sets a popover source).

## Tests

- `BackupPersistenceTests/CoreDataBackupPersistenceTests` (13): snapshot of every kind with missing dates and
  verse-less notes; replace round trip into an empty store; merging twice changes nothing; merge saves
  nothing when the backup is already there; replace deletes other records; empty replace deletes note
  verses too; newer/older/blank note text rules; overlapping notes join once; collection matched by name;
  rename only when the name is free; `joinedDistinctTexts`.
- `BackupServiceTests/BackupServiceTests` (10): export → read round trip and counts; JSON header and ISO
  dates; merge, merge again, replace through the service; newer schema refused; non-backups refused;
  missing fields damaged; 9 impossible records refused; a refused file leaves the store; oversized file;
  millisecond dates.
- `SettingsFeatureTests/BackupViewModelTests` (6): export shares a JSON file and deletes it when the sheet
  closes; reading shows counts without writing; merge; replace with confirmation; a non-backup file shows
  the English message and changes nothing; cancel forgets the backup.
- New behavior, not a bug fix, so no fail-before-fix run.

## Validation

- **Verified:**
  - `make test-no-sync TARGET=BackupPersistenceTests`: `Executed 13 tests, with 0 failures (0 unexpected)`.
  - `make test-no-sync TARGET="BackupPersistenceTests -only-testing:BackupServiceTests"`: BackupService
    `Executed 10 tests, with 0 failures (0 unexpected)`.
  - `make test-no-sync TARGET=SettingsFeatureTests`: `Executed 41 tests, with 0 failures (0 unexpected)`.
  - `make format-lint`: `0/1163 files require formatting, 42 files skipped.`
  - First full `make test-no-sync`: 1,503 of 1,504 passed; `LocalizationCatalogTests/testLocalizableStringsMatchEnglishCatalog`
    failed because the new keys were only in English. Added them to the 15 other catalogs; then
    `make test-no-sync TARGET=LocalizationTests`: `Executed 53 tests, with 0 failures (0 unexpected)`.
  - `make build-example-no-sync`: `Build Succeeded`.
  - Simulator (iPhone 18 Pro Max, no-sync build): Settings shows "Backup & Restore"; Export opened the share
    sheet with `Quran Backup 2026-11-26` (JSON, 822 bytes); Save to Files; Restore from Backup opened the
    document picker, the file showed the preview (1 collection, 1 ayah in collections, 1 recent page), Merge
    showed "Backup restored". Dark mode renders. The first tap on Restore right after the Files save sheet
    closed did not open the picker; the second did (the save sheet was still dismissing, UNVERIFIED cause).
  - `make test-no-sync` (full plan): `xcresulttool` summary `Passed`, 1,504 of 1,504 (1,475 at `2688bda9`, plus 29 new).
  - `make test-sync` (full plan, after no-sync): `Passed`, 1,983 of 1,983.
  - `make test-arabican` (after sync; NoorUI changed): `Passed`, 117 of 117.
  - `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: `Build Succeeded` each.
- **Not verified:** VoiceOver and the largest text size on this screen (standard `NoorListItem` rows, which
  wrap); iPad form-sheet presentation (no iPad simulator, AGENTS.md "Simulator"); a real device-to-device
  move (owner checklist 16); a store with thousands of notes (merge is linear, one fetch per entity, but not
  measured).

## Release

- **Commit:** filled in by the `docs(trail)` follow-up.
- **Pushed:** filled in by the `docs(trail)` follow-up.
- **TestFlight:** filled in by the `docs(trail)` follow-up.
- **iCloud / CloudKit schema:** unchanged (no model change).

## Follow-ups

- H1's learning records must join the backup (schema 2) when they land.
- Native review of the 15 agent translations of the `backup.*` strings.
- Optional: an automatic weekly backup to iCloud Drive (needs an entitlement; owner decision).
