# Handoff · Arabican (Quranic Arabic learning app)

Give this file to a new Claude Code session opened in this repository (`nulltuple/quran`). Read it fully, then
`AGENTS.md` (especially "Two apps, one repository"), before acting.

## Which app this is

This repository builds **two apps**. This handoff is for **Arabican** only.

| | Arabican (this handoff) | Quran (not this handoff) |
|---|---|---|
| App Store Connect / bundle id | **Arabican** / `com.nulltup.arabican` | MemQuran / `com.nulltup.memquran` |
| Code | `ArabicLearning/` (nested Swift package, iOS 17, Swift 6) | root package `QuranEngine` |
| App project | `Apps/Arabican/Arabican.xcodeproj`, scheme `Arabican` | `Example/QuranEngineApp.xcodeproj` |
| Content tools | `Tools/learning/` | `Tools/build-qul-word-data.py` etc. |
| Test / build / run | `make test-arabican`, `make build-arabican`, `make run-arabican` | `make test-no-sync`, `make test-sync`, `make build-example-*` |
| Release | `make release-testflight-arabican` | `make release-testflight-quran` |

Arabican imports QuranEngine modules (`NoorUI`, `QuranKit`, `QuranResources`, `SQLitePersistence`, ...); QuranEngine never
imports Arabican (guardrail-enforced). A change to a shared QuranEngine module must pass **both** apps' suites.

## State (updated at the end of each milestone)

See the milestone status table, `03-spec-roadmap-risks.md` §5.1, for done/not-done per milestone, trail entries and
TestFlight builds. Summary:

- **L0 done (2026-11-25):** nested package, app project, icon, 4-tab shell, two-app release lane, guardrails, CI jobs,
  AGENTS.md two-app rules. Trail: `../trail/2026-11-25-arabican-l0-bootstrap.md`.
- **Next: L1** content compiler pilot (§5.2).

## Decisions already made by the owner (do not re-ask)

- Repository home: nested package in this repo (ADR-0001 option A).
- Brand: **Arabican**, bundle id `com.nulltup.arabican`, App Store Connect app "Arabican" (owner created it).
- **Licensing does not restrict reuse** (personal, non-commercial use, 2026-11-25). Record sources for traceability only.
  Risks 3–5 are closed.
- swift-fsrs is approved for `ArabicLearning/Package.swift` (owner delegated the choice). Pin it exactly at L2.
- Push an Arabican TestFlight build at the end of every milestone.

## Facts a new session should not re-derive

- Nested package depends on `.package(name: "QuranEngine", path: "..")`; products are referenced with
  `package: "QuranEngine"` (works in worktrees with any folder name).
- `ArabicLearning/Package.resolved` and `Apps/Arabican/Arabican.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  must pin shared packages exactly like the root `Package.resolved` (`Tools/package-pins.test.sh`). Xcode may re-resolve
  the project file to newer versions; copy the root pins back and re-run `xcodebuild -resolvePackageDependencies`.
- The app project uses a file-system synchronized group: files under `Apps/Arabican/Arabican/` are picked up without
  editing `project.pbxproj`. Keep the app target thin (composition only).
- SF Symbols come from `NoorSystemImage` (NoorUI); add cases there (a shared QuranEngine change).
- Arabican package tests run on the `iPhone Air` simulator, Quran's on `iPhone 17e`, so they can run concurrently.
- Canonical Quran text: `QuranResources.quranUthmaniV2Database` (`arabic_text(sura, ayah, text)`), 6,236 ayahs, 72 distinct
  code points (inventory 2026-11-25). The canonical text stores a vowel before shadda (`رَّ` = ra, fatha, shadda).
- Word identities: `word_by_word.db` (`Example/QuranEngineApp/Resources/`): `word_meanings(sura, ayah, word, english,
  bengali, transliteration)`; `uthmani_tokens` maps tokens to words only for the six ayahs that don't split one token
  per word (15:7, 27:20, 36:22, 37:130, 37:164, 41:47). `۞` and pause marks are attached to word tokens, not separate.
- Running freshly downloaded third-party test suites (swift-fsrs `swift test`, quran-transcript `pytest`) was deliberately
  not done; swift-fsrs is exercised through our own tests once added.
- Noorine stroke data, Antura letter audio and quran-transcript details: see `01-source-evaluation.md`.

## Owner preferences

- Cut scope aggressively and reorder for simplicity. Don't follow proposals verbatim.
- Maximum reuse of QuranEngine modules; never copy a QuranEngine type into ArabicLearning.
- Work token-efficiently. Write or refresh this handoff whenever the context grows large.

## Still pending with the owner (not needed before L4)

A qualified reviewer or reciter for letter audio and lessons (spec risk 2, 11).
