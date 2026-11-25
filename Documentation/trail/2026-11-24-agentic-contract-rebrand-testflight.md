# Agent-only contract, change trail, Quran rebrand and TestFlight path

- **Date:** 2026-11-24
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** tooling
- **Status:** shipped
- **Related:** None (first trail entry; upstream history ends at `4c0f57a3`)

## Context

The owner asked to make the repository "fully agentic code ready" because "ONLY AGENTS WILL BE
WRITING CODE IN THIS REPOSITORY GOING FORWARD", with: no subagents; a detailed trail for every
feature and fix; good test coverage for every change; business logic shared across platforms
with only UX differing, per Apple's guidelines; no hallucination; explicit trade-offs, "particularly
the features that have very little use"; a performant, native app; and a push to origin plus a
TestFlight upload after each change. Also: "rebrand this project to Quran wherever required", an
icon "with pure black background", and a TestFlight upload to the App Store Connect app MemQuran,
`com.nulltup.memquran`.

Evidence before the change:

- `AGENTS.md` held engineering conventions but no agent operating rules; `claude.md` was a
  lowercase symlink to it.
- The app shipped as `com.quran.QuranEngineApp`, team `MKP73M5X4A` (upstream's), with no display
  name (`Example/QuranEngineApp.xcodeproj/project.pbxproj`).
- The icon (`Example/QuranEngineApp/Resources/AppIcon.icon`) was an amber gradient with a
  "QuranEngine" wordmark under the calligraphy glyph.
- The app uses no iCloud: `Container.supportsCloudKit` returns `false`
  (`Example/QuranEngineApp/Classes/Container.swift`), and there is no entitlements file.
- The owner's message mentioned an attached SVG, but none arrived and no matching file was found
  in `~/Downloads`, `~/Desktop`, `~/Documents` or `~/Pictures`. Asked; the owner chose the
  repository's existing glyph (`AppIcon.icon/Assets/Glyph.svg`) on black, and "Quran" as the name
  under the icon.
- Team `NBMD2V39VV` comes from the owner's other TestFlight app (`~/git/skryb`, `AGENTS.md`
  identity table), which uses the same `com.nulltup.*` bundle prefix.

## Decisions

- **Contract mirrors the owner's Skryb repository** (one agent, ground truth, trade-offs, shared
  logic, tests, performance, trail, definition of done, safety rails), adapted to this repo's Make
  targets, layers and `Documentation/` folder. The existing conventions stay verbatim below it.
- **Mechanical enforcement over prose**: `Tools/check-agent-guardrails.sh` (git hooks via
  `make install-git-hooks`, and a CI job) rejects code commits without a complete trail entry,
  source changes without a test or a written `No new tests` reason, and removal of the
  `.claude/settings.json` deny on the `Agent` tool. Layering is already enforced by
  `Package.swift`, so the script does not duplicate it.
- **Rebrand user-facing identity only**: display name `Quran`, bundle ID, team, icon, icon option
  name, README. Swift modules, the `QuranEngine` package, the `QuranEngineApp` scheme and the
  `QuranEngine_Localization` bundle keep their names (see Trade-offs).
- **Icon stays an Icon Composer `.icon`**, now a solid black fill with the white glyph, no glass
  and no wordmark. Xcode compiles it into PNG app icons for every iOS version the app supports
  (verified: `AppIcon60x60@2x.png` and `AppIcon76x76@2x~ipad.png` in the built app), and iOS 26+
  derives the dark, tinted and clear appearances from the same source. The standalone PNGs the
  owner asked for (`Branding/AppIcon-iOS-1024.png`, opaque; `Branding/AppIcon-macOS-1024.png`,
  macOS rendition) come from the existing `Tools/export-app-icon-images.sh`, extended with a
  `master` mode, so the `.icon` remains the single source.
- **Pure black is exact**: ictool dithers flat fills by one level, so the opaque export snaps
  pixels with every channel at or below 2 to 0. The master's corners read `0 0 0`.
- **Graphite alternate kept**, with its "QuranEngine" wordmark removed and the glyph centered.
- **TestFlight build is no-sync**: `QURAN_SYNC` needs Quran.com OAuth client credentials this
  app does not have (`Container.swift`, `QURAN_OAUTH_CLIENT_ID`).
- **Marketing version stays 1.20.3** (the project's value); the build number is the commit count.
- **Agents push to `main` directly**, per the owner's "push to origin" instruction; the upstream
  rule about PR screenshots now applies only when the owner asks for a PR.
- `CFBundleURLSchemes` (`quran`, `quran-ios`, `com.quran.oauth`) are unchanged: the OAuth scheme
  is registered with Quran.com, and the deep-link schemes are a product decision (see Follow-ups).
- `ITSAppUsesNonExemptEncryption = NO` added so TestFlight builds don't wait on the export
  compliance question; the app's networking is HTTPS through the system.

## Trade-offs

- **Complexity added:** about 1,440 added lines of docs, shell and config (`git diff --numstat`),
  most of it `AGENTS.md` and the trail: 4 tool files (`check-agent-guardrails.sh`,
  `release-testflight.sh`, `lib/release.sh`, `lib/app-identity.sh`), 3 test scripts, 2 git
  hooks, 1 CI job, 4 Make targets, 4 documents. No Swift dependency, entitlement, persisted state
  or runtime cost. The guardrail adds a few seconds to each commit and push.
- **Who benefits / how often:** every future agent change. The `No new tests` escape hatch is the
  main way the rule can be gamed; it requires a written reason that lands in the trail.
- **Rejected cheaper options:** a prose-only contract (unenforceable); renaming modules and
  scheme to "Quran" (hundreds of files, broken blame and upstream merges, no user-visible gain);
  a hand-made `AppIcon.appiconset` of PNGs (a second icon source, and no iOS 26 dark, tinted or
  clear appearances); deleting the Graphite alternate icon (a user-visible feature; the AppIcon
  feature is about 250 lines and rarely used, but cheap to keep).
- **Ongoing cost:** trail entries cost each change a few minutes; the TestFlight upload adds
  about the length of a Release archive to every app-affecting change.

## Changes

Agent contract and trail:
- `AGENTS.md`: new agent operating contract, identity table, agent Make targets, pushing rules;
  existing conventions kept. `CLAUDE.md` replaces the lowercase `claude.md` symlink.
- `Documentation/trail/` (`README.md`, `TEMPLATE.md`, this entry),
  `Documentation/agents/release-testflight.md`, `Documentation/agents/feature-cost-register.md`.
- `.claude/settings.json`: denies the `Agent` tool.
- `Tools/check-agent-guardrails.sh`, `.githooks/pre-commit`, `.githooks/pre-push`,
  `Makefile` (`guardrails`, `test-tools`, `install-git-hooks`, `release-testflight`),
  `.github/workflows/ci.yml` (`Guardrails` job on `ubuntu-latest`).

Release:
- `Tools/lib/app-identity.sh` (single source of the shipped identity), `Tools/lib/release.sh`
  (version, build number, identity check, export options), `Tools/release-testflight.sh`.

Rebrand (iPhone and iPad; one target):
- `project.pbxproj`: bundle ID `com.nulltup.memquran`, team `NBMD2V39VV`,
  `INFOPLIST_KEY_CFBundleDisplayName = Quran`, `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`.
- `Example/QuranEngineApp/Info.plist`: URL type named by the new bundle ID.
- `Makefile`: `EXAMPLE_BUNDLE_IDENTIFIER`.
- `AppIcon.icon`, `AppIcon-Graphite.icon`: black fill and centered glyph; wordmark and background
  layers removed.
- Asset sets renamed `app-icon-engine-amber` → `app-icon-quran`, `app-artwork-engine-amber` →
  `app-artwork-quran`, `*-engine-graphite` → `*-graphite`, all regenerated by
  `make export-example-app-icon-images`; `Branding/` masters added.
- `AppIconCatalog+Example.swift`: option `quran` named "Quran", IDs `quran` and `graphite`.
- `UI/NoorUI/Sources/AppIcon/AppIconAccent.swift`: comment no longer names QuranEngine icons.
- `Tools/export-app-icon-images.sh`: `master` mode, `copy` re-encode, black snapping.
- `README.md`: Quran name, icon, agent-only notice, release section.

## Tests

- `Tools/check-agent-guardrails.test.sh` (14 cases): README-only changes pass; source without an
  entry, an entry missing a section, a misnamed entry, source without a test or reason, a too-short
  reason, and a dropped `Agent` deny are rejected; range mode checks each commit; trail-only
  commits pass.
- `Tools/release.test.sh` (19 cases): marketing-version parsing (one, disagreeing, none), build
  number, bundle identity accept and reject, export options, and that the project, `Info.plist`
  and `Makefile` match `Tools/lib/app-identity.sh`.
- `Tools/example-app-icons.test.sh` (16 cases): every image set and alternate icon the catalog
  names exists, every icon layer image exists, the primary fill is black, the masters are 1024 px
  and the iOS master is opaque with a `0 0 0` corner. Shown to fail by renaming one artwork name
  in the catalog (`not ok - image set app-artwork-missing has a PNG`), then restored.
- All three run from `make test-tools`; the guardrail test also runs in CI.

## Validation

- **Verified:**
  - `bash Tools/check-agent-guardrails.test.sh`: `14 passed, 0 failed`.
  - `bash Tools/release.test.sh`: `19 passed, 0 failed`.
  - `bash Tools/example-app-icons.test.sh`: `16 passed, 0 failed`.
  - `make format-lint`: `0/1045 files require formatting, 12 files skipped.`
  - `make guardrails` on the staged change: `guardrail: ok (staged)`.
  - `make test-no-sync`: `Test Succeeded`; the result bundle reports 1,317 tests, 1,317 passed,
    0 failed, 0 skipped.
  - `make test-sync`: `Test Succeeded`; the result bundle reports 1,823 tests, 1,823 passed,
    0 failed, 0 skipped.
  - `make build-example-sync`: `Build Succeeded`.
  - `make build-example-no-sync`: `Build Succeeded`. The built `Info.plist` has
    `CFBundleIdentifier=com.nulltup.memquran`, `CFBundleDisplayName=Quran`,
    `ITSAppUsesNonExemptEncryption=false`, and `CFBundlePrimaryIcon` with `AppIcon60x60`; the
    compiled `AppIcon60x60@2x.png` (120 px) shows the white glyph on black.
- **Not verified:** the icon on a device Home Screen in dark, tinted and clear modes; the App Icon
  picker and What's New reveal with the renamed images on a device.

## Release

- **Commit:** pending
- **Pushed:** pending
- **TestFlight:** pending
- **iCloud / CloudKit schema:** unchanged (the app uses no iCloud), so no owner deployment is
  needed.

## Follow-ups

- **Quran.com links still in the app:** "Share app" and "Write a review" use Quran.com's App Store
  ID `1118663303` (`Features/SettingsFeature/Sources/SettingsRootViewModel.swift`,
  `Domain/SettingsService/Sources/ReviewService.swift`), and Donate opens
  `give.quran.foundation`. Pointing them at MemQuran needs its App Store Apple ID and the owner's
  decisions on donation and contact links; then inject the values from the app instead of
  hardcoding them in Features and Domain.
- **Deep-link schemes:** `quran://` and `quran-ios://` are also claimed by the Quran.com app, so
  iOS may open either app. Decide whether MemQuran keeps them.
- **CI runners:** the Package, Sync, Example and SwiftFormat jobs use the upstream `xcode-27`
  runner label, which `nulltuple/quran` may not have (no workflow runs were listed before this
  change). Only the new `Guardrails` job is known to have a runner.
- **Upstream's request:** the README asks not to republish the example app without
  modifications. A public App Store release should carry meaningful changes beyond this rebrand.
- **Mac:** no Mac target exists. If the owner wants one, prefer checking "Designed for iPad" on
  Apple silicon first; Mac Catalyst is a larger change.
