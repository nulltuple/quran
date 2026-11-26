# Arabican L0: second app bootstrap, two-app tooling and guidelines

- **Date:** 2026-11-25
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature | tooling
- **Status:** shipped
- **Related:** [2026-11-25-arabic-learning-source-evaluation.md](2026-11-25-arabic-learning-source-evaluation.md),
  `Documentation/ArabicLearning/03-spec-roadmap-risks.md` §5 (L0)

**App:** Arabican (new). Shared change to QuranEngine: three `NoorSystemImage` cases. Tooling: both apps.

## Context

The owner asked to continue `Documentation/ArabicLearning/HANDOFF.md` (milestone L0 onward), naming the
second app: "I already created an app named Arabican and an id com.nulltup.arabican. Please use those for
branding", with "MAXIMUM REUSE OF SHAREABLE MODULES" and "PROPER AGENTIC GUIDELINE UPDATE AND SPEC UPDATE
TO ENSURE FUTURE AGENTIC SESSIONS DO NOT GET CONFUSED ABOUT TWO APPS UNDER SAME REPO", plus a TestFlight
build to Arabican for every major milestone. Asked about FSRS, the owner answered: "DO NOT WORRY ABOUT ANY
LICENSING. THIS IS FOR PERSONAL USE ... PICK THE BEST OPTIONS. UPDATE SPEC AND AGENTIC GUIDELINE TO
CLARIFY NO LICENSING RESTRICTION."

## Decisions

- **Nested package identity.** `ArabicLearning/Package.swift` depends on `.package(name: "QuranEngine", path: "..")`
  and names products with `package: "QuranEngine"`. The name, not the directory, keeps product references
  valid in worktrees whose folder is not `quran` (verified: resolution printed `QuranEngine: /Users/.../quran @ local`).
- **Swift 6 tools and language mode** for the new package (`swift-tools-version:6.0`); QuranEngine stays 5.8.
- **App project**: hand-written `Apps/Arabican/Arabican.xcodeproj` (objectVersion 77) using a file-system
  synchronized group, so new files in `Apps/Arabican/Arabican/` need no project edits. The app target holds only
  `ArabicanApp.swift`, the asset catalog and the icon; it links `LearningUI`. Mirrors `Example/` (thin app,
  local package reference). Rejected XcodeGen/Tuist: a generator is a new tool for every agent and CI.
- **Folder naming**: brand on what ships (`Apps/Arabican`, scheme/target `Arabican`, display name `Arabican`);
  domain names for modules (`ArabicLearning`, `LearningModel`, `LearningUI`) as in ADR-0001. Changed the ADR's
  `Apps/ArabicLearning/` accordingly.
- **Shared SF Symbols**: `LearningUI` imports `NoorUI` and uses `NoorSystemImage` (one source of truth, AGENTS §4),
  adding `learn`, `practice`, `learningProgress`; Quran tab reuses the existing `study` alias. ADR §4.1 now allows
  `NoorUI` (it also gives Arabican the Quran text and sura-name APIs it must use).
- **iOS 17**: `TabView` uses `.tabItem`/`.tag`, not the iOS 18 `Tab` API.
- **Pins**: `ArabicLearning/Package.resolved` and the Arabican project's resolved file are seeded from the root
  `Package.resolved`; `Tools/package-pins.test.sh` keeps shared pins identical. Without the seed SwiftPM resolved
  newer versions (GRDB 6.29.3, swift-log 1.17.2 vs the Quran app's 6.29.2, 1.4.2), and Xcode later re-resolved
  the project file to newer versions once more; the new test caught that.
- **Release lane**: `Tools/release-testflight.sh --app quran|arabican` is required; `make release-testflight`
  now refuses and names `release-testflight-quran` / `release-testflight-arabican`. Explicit over a default,
  like the explicit sync-mode targets.
- **Arabican tests on their own simulator** (`iPhone Air`), so they never share state with Quran suites (iPhone 17e).
- **Guardrail 4**: no Swift file outside `ArabicLearning/` and `Apps/Arabican/` may import an ArabicLearning
  module, and the root `Package.swift`/Example project may not name it. `ArabicLearning/*`, `Apps/*` need trail
  entries; `Tools/learning/*.py` is source and `Tools/learning/*.test.py` its tests.
- **Licensing**: recorded in AGENTS.md ("Licensing (owner decision, 2026-11-25)") and the spec header; risks 3–5
  closed.
- **FSRS**: owner delegated; chose swift-fsrs (the reference implementation from the FSRS authors) over an in-house
  port, approved for `ArabicLearning` only. Added at L2, not now (no module needs it yet).
- **Not run at L0**: swift-fsrs `swift test` and quran-transcript `pytest`. Running a freshly downloaded repository's
  test code is executing untrusted third-party code; swift-fsrs gets compiled and exercised by our own tests when
  L2 adds it, and quran-transcript is not needed until the pilot phonetic plan. Recorded in spec §5.1.
- **Icon**: Icon Composer `.icon` with a teal fill and a white letter ba (ب) drawn as a stroked bowl plus dot (no
  font dependency). Placeholder-quality artwork; the owner may replace it.

## Trade-offs

- **Complexity added:** a second package (2 modules, 4 source files, 172 lines; 3 test files), an Xcode project,
  4 Make targets, 2 CI jobs, a tool test, ~50 lines in the guardrail and release scripts. No permissions,
  entitlements, background work or persisted state.
- **Who benefits / how often:** the owner, for every Arabican milestone. The Quran app gains nothing and loses
  nothing: its binary changes only by three unused enum cases.
- **Rejected cheaper options:** a separate repository (ADR option B; owner chose A); adding Arabican targets to the
  root `Package.swift` (would raise iOS 15 code to iOS 17 or need per-target availability, and couple release lanes);
  copying symbol names into LearningUI (parallel list).
- **Ongoing cost:** two CI jobs (~5–10 min each); every root pin bump must be copied into two Arabican files
  (enforced by a test); Arabican links most of QuranEngine's UI stack through `NoorUI`, so Arabican's binary is
  larger than a from-scratch shell (size not measured).

## Changes

- `ArabicLearning/Package.swift`, `Package.resolved`: nested package, products `LearningModel`, `LearningUI`.
- `ArabicLearning/Sources/LearningModel/SkillID.swift`, `PresentationProfile.swift`: validated skill ids; child/adult profile.
- `ArabicLearning/Sources/LearningUI/AppTab.swift`, `ArabicanRootView.swift`, `Resources/Localizable.xcstrings`: 4-tab shell.
- `Apps/Arabican/Arabican.xcodeproj` (+ shared scheme, workspace, resolved file), `Apps/Arabican/Arabican/ArabicanApp.swift`,
  `Assets.xcassets` (AccentColor), `AppIcon.icon`.
- `UI/NoorUI/Sources/Images/NoorSystemImage.swift`: `learn`, `practice`, `learningProgress` (shared, additive).
- `Tools/lib/app-identity.sh`: Arabican identity, `app_identity_select`. `Tools/release-testflight.sh`: `--app`.
- `Tools/check-agent-guardrails.sh`: Arabican paths, learning Python, one-way dependency check.
- `Tools/package-pins.test.sh` (new), `Tools/release.test.sh`, `Tools/check-agent-guardrails.test.sh`.
- `Makefile`: `test-arabican`, `build-arabican`, `run-arabican`, `test-learning-tools`, `release-testflight-{quran,arabican}`;
  `run-example-app` now wraps a shared `run-simulator-app` macro.
- `.github/workflows/ci.yml`: `ArabicanPackage`, `ArabicanApp` jobs.
- Docs: `AGENTS.md` (two-app header, "Two apps, one repository", licensing, DoD per app, identity table, Make
  commands, architecture, dependencies), `README.md`, `Documentation/agents/release-testflight.md`,
  `Documentation/agents/feature-cost-register.md`, ADR-0001, spec 03 (§5.1 status table, licensing, risks),
  `Documentation/ArabicLearning/HANDOFF.md`.
- Platforms: iPhone and iPad (both apps universal).

## Tests

- `LearningModelTests`: `SkillIDTests` (valid/malformed ids, Codable round trip and rejection),
  `PresentationProfileTests`. `LearningUITests`: `AppTabTests` (order, localized titles, distinct symbols).
- Tool tests: 7 new guardrail cases (Arabican paths need entries, learning Python needs a test, Quran module
  importing an ArabicLearning module rejected in staged and range mode, root `Package.swift` naming it rejected),
  release identity tests for both projects and `--app`, `Tools/package-pins.test.sh` (checker self-test plus the
  three real files; it failed before the re-seed, see Decisions).

## Validation

- **Verified:**
  - Quran baseline before any change (HEAD `79e4c4d7`): `make test-no-sync` xcresult `result: Passed, totalTestCount: 1422,
    passedTests: 1422, failedTests: 0`; `make test-sync` `totalTestCount: 1916, passedTests: 1916, failedTests: 0`.
    (The `NoorSystemImage` edit landed while that run was building; it is additive and is re-verified below.)
  - After the change: `make test-no-sync` `result: Passed, totalTestCount: 1422, passedTests: 1422, failedTests: 0`;
    `make test-sync` `totalTestCount: 1916, passedTests: 1916, failedTests: 0`; `make build-example-no-sync` and
    `make build-example-sync` both `Build Succeeded`.
  - `make test-arabican`: `result: Passed, totalTestCount: 7, passedTests: 7, failedTests: 0`.
  - `make build-arabican`: `Build Succeeded`. Installed and launched on the iPhone 18 Pro simulator
    (`com.nulltup.arabican: 43276`); screenshot showed the Learn tab and the four tabs Learn, Practice, Quran, Progress.
  - `make test-tools`: guardrails `22 passed, 0 failed`, release `34 passed, 0 failed`, icons `16 passed`,
    word data `46 passed`, pins `5 passed, 0 failed`.
  - `make format-lint`: `0/1078 files require formatting`.
- **Not verified:** iPad layout, Dark mode, large Dynamic Type and VoiceOver on the shell (placeholder screens using
  system `ContentUnavailableView`); icon rendering on device; Arabican binary size and launch time.

## Release

- **Commit:** recorded in the follow-up `docs(trail)` commit.
- **Pushed:** recorded in the follow-up `docs(trail)` commit.
- **TestFlight:** Arabican build recorded in the follow-up commit. Quran: a build is required by the rules
  (shared `UI/NoorUI` file changed) but the change is three unused enum cases; see the follow-up commit.
- **iCloud / CloudKit schema:** unchanged (neither app uses iCloud).

## Follow-ups

- L1 content compiler pilot (`Tools/learning/`, `ArabicScript`, `LearningContent`).
- The Quran app's project resolved file is gitignored (`.gitignore`, `/Example/.../Package.resolved`), so its
  archive can resolve dependency versions newer than the root `Package.resolved`; consider committing it like
  Arabican's (Quran-app change, needs its own entry).
