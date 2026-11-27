# V0: recitation model published as a GitHub release and downloaded in the app (D7)

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-27-v0-recitation-lab.md](2026-11-27-v0-recitation-lab.md) (the lab this adds a download to),
  [2026-11-26-v0-recitation-engine.md](2026-11-26-v0-recitation-engine.md) (the model and its conversion),
  [2026-11-26-c1-english-bengali-tafsir.md](2026-11-26-c1-english-bengali-tafsir.md) (the same pattern for tafsir packs)

App: **Quran** (Domain `RecitationRecognition`, Features `RecitationLabFeature`, the shared test fake
`AppDependenciesFake`). Arabican imports none of these.

## Context

Owner decision **D7 (2026-11-27)**, answering "Where should the 125 MB recitation model download from?": "GitHub release
asset". Until now the model reached a device only by hand (copying into the app container), so neither the owner's phone
nor V1 voice search could use it.

## Decisions

- **Release `recitation-model-1` of `nulltuple/quran`**, published this session with `gh release create` (target `main`):
  one asset, `recitation-model-1.zip`, 84,288,886 bytes, sha256
  `a6c3ee79f6b848ddd303146bc2b873889e5711c770169ea33dc2697d05ebc7e3` (GitHub's own digest matches). It holds
  `TilawiFastConformerInt8.mlpackage` (the package `make recitation-model` builds, 125 MB unpacked), `vocab.json` and
  `ATTRIBUTION.txt` (weights CC-BY-4.0 from `muhdur/tilawi-fastconformer-quran` at revision
  `e9448a0e84f3adb64c28b7a8db501dd8e0e59a84`; the release notes say the same). `curl -sIL` on the asset URL:
  `HTTP/2 200`, `content-length: 84288886`, no sign-in.
- **Ship the `.mlpackage`, compile on the device.** A compiled `.mlmodelc` is tied to the Core ML compiler version;
  `RecitationModelStore` already compiles on first load and keeps the result. Installing a new archive deletes a
  compiled model so the new package is compiled.
- **Download with the app's `DownloadManager`**, as Mushaf editions (`ReadingResourceDownloader`) and translations do:
  background session, resume, and a running download is joined after a relaunch (matched by its destination,
  `Documents/recitation-model/recitation-model-1.zip`; the audio, translation and reading downloaders filter by their own
  paths, so they ignore it). The archive is deleted after install, valid or not.
- **sha256 pinned in code** (`RecitationModelArchive.current`): a corrupt, truncated or replaced file is rejected with
  `checksumMismatch` and nothing is installed. A new model means a new release tag and a new pinned digest.
- **`AppDependenciesFake.downloadManager` is now an idle real `DownloadManager`** (ephemeral configuration, temporary
  database, never started, so it opens no session) instead of `fatalError`: the Diagnostics test builds the Recitation
  Lab, whose builder now reads the container's download manager.

## Trade-offs

- **Complexity added:** `RecitationModelDownloader.swift` (~120 lines: archive pin, download, sha256, install);
  `RecitationLabViewModel.downloadModel()` and a `.downloading(progress:)` state; a Download button and progress bar;
  `RecitationRecognition` depends on `BatchDownloader` and `SystemDependencies` (`DefaultZipper`), both already in the
  package; CryptoKit (system). A public release asset that must stay published while builds point at it.
- **Who benefits / how often:** the owner (device benchmarks now possible without Xcode) and, next, V1 voice search, which
  will offer the same download to every tester. 84 MB once per device; 125 MB on disk plus the compiled copy (about the
  same again, UNVERIFIED on a device).
- **Rejected cheaper options:** bundling (125 MB in every install, even for people who never use voice features); a plain
  `URLSession` download (no background resume, a second download path to maintain); shipping a compiled `.mlmodelc`
  (compiler-version dependent).
- **Ongoing cost:** the release asset is part of the app's contract: never delete or replace `recitation-model-1`; publish
  `recitation-model-2` with a new pin instead. Disk: package and compiled model both stay (deleting the package after
  compiling would save ~125 MB; not done, so a recompile never needs a new download).

## Changes

- `Domain/RecitationRecognition/Sources/RecitationModelDownloader.swift`: `RecitationModelArchive` (`.current` =
  `recitation-model-1`), `RecitationModelDownloadError`, `RecitationModelDownloader` (`download(onProgress:)`,
  `install(archiveAt:)`, `sha256(of:)`).
- `Features/RecitationLabFeature/Sources/`: the view model's `downloadModel()` and `.downloading` state; the view's
  Download button and `ProgressView`; the builder passes `RecitationModelDownloader(downloadManager:store:)`.
- `Features/AppDependenciesFake/Sources/AppDependenciesFake.swift`: idle `downloadManager`.
- `Package.swift`: `RecitationRecognition` adds `BatchDownloader`, `SystemDependencies`; its tests add
  `BatchDownloaderFake`, `ZIPFoundation`; `RecitationLabFeature` tests add `BatchDownloader`.
- Docs: roadmap §5, §6 V0, §7 D7; `quran-roadmap-progress.md`; `feature-cost-register.md`; trail index.

## Tests

- `RecitationModelDownloaderTests` (4): through `DownloadManager` over `NetworkSessionFake` and the real file system, a
  stand-in archive laid out like the published one is downloaded, checked, unzipped into the model directory and deleted,
  with progress reported; an archive whose sha256 differs is rejected and deleted with nothing installed; installing drops
  a model compiled from an older package; `sha256(of:)` of "abc" is the standard digest.
- `RecitationLabViewModelTests` (2, updated for the new initializer) and `DiagnosticsViewModelTests` (unchanged; now build
  the lab with the idle download manager).

## Validation

- **Verified:**
  - `make format-lint`: `0/1215 files require formatting`.
  - `make test-no-sync TARGET=RecitationRecognitionTests`: 57 passed; `TARGET=RecitationLabFeatureTests`: 2 passed;
    `TARGET=SettingsFeatureTests`: 43 passed.
  - Simulator (iPhone 18 Pro Max): with the hand-copied model removed, the lab offered "Download the model (84 MB)";
    tapping it downloaded the real asset from GitHub, checked it, unzipped and compiled it within about 6 s on this
    network, and showed "Model ready (loaded in 1958 ms)"; `Application Support/RecitationModel` then held
    `ATTRIBUTION.txt`, the `.mlmodelc`, the `.mlpackage` and `vocab.json`, and `Documents/recitation-model/` was empty.
  - `make test-no-sync`: 1,627 passed, 0 failed, 0 skipped; then `make test-sync`: 2,106 passed, 0 failed, 0 skipped;
    then `make test-arabican`: 117 passed, 0 failed (xcresult summaries; one after the other).
  - `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: `Build Succeeded`.
- **Not verified:** the download on a phone, over cellular, with the app sent to the background mid-download, and resumed
  after the app is killed (the `DownloadManager` paths are the ones Mushaf downloads use; owner checklist item 23).

## Release

- **Commit:** `d5d7d7df` (feat(recitation): download the recitation model from its GitHub release)
- **Pushed:** origin/main at `d5d7d7df`
- **TestFlight:** Quran build 1008 (1.20.3): `Uploaded Quran iOS 1.20.3 (1008) for commit d5d7d7df2b1d281482b3b4a3e9ed0ac0f2a009ce to App Store Connect app MemQuran.`
  No Arabican build (it imports none of the changed modules).
- **GitHub release:** `https://github.com/nulltuple/quran/releases/tag/recitation-model-1` (owner decision D7).
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- V1 voice search offers this download (localized, with the size) before the first search.
- A way to delete the model (Settings) once testers can download it.
