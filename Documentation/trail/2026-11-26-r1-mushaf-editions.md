# Quran R1: downloadable Mushaf editions from verified files.quran.app packs

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-26-quran-roadmap-v2.md](2026-11-26-quran-roadmap-v2.md) (R1 spec),
  [2026-11-26-f1-collection-marks-no-sync.md](2026-11-26-f1-collection-marks-no-sync.md) (same release)

## Context

App: **Quran** (a `Domain/ReadingService` addition and `Example` wiring; Arabican does not use the
new type but compiles the module's package). Roadmap v2 R1: `Reading` already models seven editions
(`Model/QuranKit/Sources/Reading.swift:11-17`) and `ReadingSelectorFeature` already lists every
available one, but the app shipped `remoteResources = nil` (`Example/QuranEngineApp/Classes/Container.swift`),
so only the bundled Hafs 1405 was selectable. The roadmap made the research step a gate: verified
public URLs or mark R1 blocked.

### Research (2026-11-26)

- Source of the URLs: `quran/quran_android` page providers name the host and directories
  (`gh search code "files.quran.app" --repo quran/quran_android`): `MadaniPageProvider.kt`
  (`https://files.quran.app/hafs` + `/madani`), `NewMadaniPageProvider.kt` (`/madani_1421`),
  `TajweedPageProvider.kt` (`/tajweed`), each with `getImagesZipBaseUrl() = "$base/zips/"`.
  Upstream quran-ios's Example also has `filesAppHost = https://files.quran.app/` but `remoteResources = nil`.
- Probed `https://files.quran.app/hafs/<dir>/zips/images_<width>.zip` for each `Reading.imageAssetWidth`
  and listed every zip remotely with HTTP range reads (Python `zipfile` over ranged GETs; nothing
  saved but each ayahinfo database), then hashed each full zip (streamed through `shasum -a 256`):

| Reading | URL path (`files.quran.app/`) | Size (bytes) | sha256 | Contents |
|---|---|---|---|---|
| `hafs_1421` | `hafs/madani_1421/zips/images_1120.zip` | 52,519,753 | `6252e0323b5d45efd13c81f5d54f9775cc1dc27b59834bac63de87a56f447c08` | 604 `width_1120/pageNNN.png`, `.v1`–`.v2`; ayahinfo: glyphs 13,818, ayah_markers 6,236, sura_headers 114 |
| `hafs_1440` | `hafs/madani_1440/zips/images_1352.zip` | 126,858,658 | `14c5bf1e82a0e6a89b2a8c73636c3d968c1d79a6ac058832831d52544fbeceeb` | 604 pages, `.v1`–`.v4`; glyphs 13,273 (6,236 ayahs) |
| `hafs_1439` | `hafs/madani_1439/zips/images_1080.zip` | 91,859,056 | `1307ab8dd6804797f73e03b82320cba541a2146b43a82d39d2fedc7d8d742d2a` | 604 × 15 `width_1080/<page>/<line>.png`; ayah_markers 6,236, ayah_highlights 13,273, sura_headers 114 |
| `hafs_1441` | `hafs/madani_1441/zips/images_1440.zip` | 102,608,011 | `784682f17e083d529476cb738a53d2f4eb461a925e74b9d167d28a244ed1116e` | 604 × 15 line images; same tables as 1439 |
| `tajweed` | `hafs/tajweed/zips/images_1280.zip` | 143,688,256 | `3b4e87837ea961102c77a670a913e68e24a2b7bd9fd1ef0aa320ee17c569c40a` | 604 pages, `.v2`–`.v7`; glyphs 83,881 (6,236 ayahs) |

- Every zip unpacks to `width_<w>/` plus `databases/ayahinfo_<w>.db`, the exact layout under
  `images_<w>/` that `Reading.imagesDirectory(in:)`/`ayahInfoDatabase(in:)` and
  `LinePageAssetService` (`String(pageNumber)/<line>.png`) read, and the `.vN` markers are what
  `RemoteResource.extractedVersionFileURL` checks, so these are the packs the reader was written for.
  The tables match their readers: `glyphs`/`ayah_markers`/`sura_headers` (`GRDBWordFramePersistence`)
  for page images, `ayah_markers`/`ayah_highlights`/`sura_headers` (`GRDBLinePagePersistence`) for line pages.
- **IndoPak: no verified source.** Every guess under `naskh/` and `indopak/` returned 404; the Android
  naskh flavor's page provider is not in the public repository (only `QuranFileConstants.kt` importing
  `NaskhConstants`). Not guessed further.

## Decisions

- **The URL table lives in `Domain/ReadingService` (`QuranAppReadingRemoteResources`), not in `Example`.**
  The spec said "in Example"; putting it beside `ReadingRemoteResources` lets `ReadingServiceTests`
  pin it (the Example app has no test target). `Container` only instantiates it.
- **Version per pack = the newest `.vN` marker in the zip** (2, 4, 7), or 1 for the line-page zips
  that have none, so a device that unzipped a newer upload of the same URL recovers it
  (`RemoteResource.canRecoverSuccessFile`).
- **Hafs 1405 stays bundled** (no remote entry), as the fallback `replaceSavedReadingIfUnavailable` needs.
- **IndoPak stays hidden** (no remote entry): the selector filters by `availableReadings()`, so the
  IndoPak tab does not appear. Roadmap R1 is partly blocked on it.
- **Reading position across editions:** the spec asked to move position by ayah. The app keeps recent
  pages per Mushaf (`CoreDataLastPagePersistence` stores `mushafID`), so switching edition shows that
  edition's own recent pages and never opens the old page number in the new layout; notes, collections
  and highlights are by ayah and carry over. Carrying the reading position itself over is not built
  (follow-up, likely rarely needed).
- **Word pointer:** only Hafs 1405 has word positions (`Reading.supportsWordPositions`); the selector
  already labels the others "No Word-by-word translation".

## Trade-offs

- **Complexity added:** one 65-line source file, one test file, two lines in `Container`. No dependency,
  permission, entitlement or persisted format; downloads go through the existing `ReadingResourcesService`
  (background download, unzip, success marker, retry) and land in `Documents/readings/<edition>`.
- **New failure modes:** the packs are served by Quran.app's CDN; if a URL moves, choosing that edition
  shows the existing download error with Retry, and Hafs 1405 keeps working. Downloads are 52–144 MB
  each; choosing an edition deletes the previously downloaded one (`removeOtherReadings`), so at most one
  is on disk. Requests carry no user data.
- **Who benefits / how often:** readers who prefer a Tajweed-colored or 1421/1440/1441 Mushaf; likely a
  minority of sessions, but it is a setting chosen once.
- **Rejected cheaper options:** bundling editions (52–144 MB each in the app binary); hosting our own copies
  (cost, upkeep).
- **Ongoing cost:** the table must follow Quran.app's CDN layout; `QuranAppReadingRemoteResourcesTests`
  pins it, and a moved URL would surface as a download error.
- **Licensing:** page images are the King Fahd Quran Printing Complex Mushafs as published by Quran.app;
  the owner's 2026-11-25 decision (personal, non-commercial use) covers reuse. Source recorded above.

## Changes

- `Domain/ReadingService/Sources/QuranAppReadingRemoteResources.swift`: verified pack table.
- `Example/QuranEngineApp/Classes/Container.swift`: `remoteResources = QuranAppReadingRemoteResources()`.
- Platforms: iPhone and iPad (same code); no Mac target.

## Tests

- `Domain/ReadingService/Tests/QuranAppReadingRemoteResourcesTests.swift` (4): URL and version per edition;
  none for Hafs 1405 and IndoPak; each zip's name unpacks to the folder the page and line-page readers use;
  `availableReadings()` offers every edition but IndoPak.
- Download, resume, corrupt zip, offline and removal behavior is the existing `ReadingResourcesService`
  path, covered by `ReadingResourcesServiceTests` and `ReadingResourcesRetentionTests` (unchanged).
- Fails without the change: the type does not exist before it (reasoned from the diff).

## Validation

- **Verified:** `make test-no-sync TARGET=ReadingServiceTests`: `Executed 32 tests, with 0 failures`.
  Simulator (iPhone 18 Pro Max, no-sync Debug, light, portrait): Settings > Choose Mushaf shows Uthmani
  and Tajweed tabs (no IndoPak); choosing Madani Mushaf (1441) downloaded and unpacked it
  (`Documents/readings/hafs_1441/success-v1.txt`, 604 page folders, `ayahinfo_1440.db`), and Al-Fātiḥah
  rendered from the line pages with drawn sura header and ayah markers. Full suites on the tree with this
  change and the F1 follow-up: `make test-no-sync` 1,457 passed, 0 failed; `make test-sync` 1,936 passed,
  0 failed; `make test-arabican` 117 passed, 0 failed; `make build-example-no-sync`, `make build-example-sync`,
  `make build-arabican`: `Build Succeeded`; `make format-lint`: `0/1145 files require formatting`.
- **Not verified:** Hafs 1421, 1439, 1440 and Tajweed rendered on screen (their zips verified by listing
  only); resume after killing the app mid-download and airplane mode on a device; Dark mode, landscape and
  iPad layouts of the new editions; disk-space handling on a full device.

## Release

- **Commit:** f1c4aa6b
- **Pushed:** origin/main at f1c4aa6b
- **TestFlight:** Quran build 986 (1.20.3): `Uploaded Quran iOS 1.20.3 (986) for commit f1c4aa6bbd2b923e612315a621f8beeb99a8ac4c to App Store Connect app MemQuran.` (Arabican build 986 uploaded from the same commit for the F1 follow-up's NoorUI change; this change does not alter Arabican.)
- **iCloud / CloudKit schema:** unchanged

## Follow-ups

- IndoPak: needs a verified public pack (owner input, or a source we can verify).
- Optional: carry the reading position to the new edition by ayah when switching.
- Owner checklist: pick each edition on a device, read a page, switch back.
