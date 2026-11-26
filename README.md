<p align="center">
    <img src="Branding/AppIcon-iOS-1024.png" width="200" alt="Quran app icon">
</p>

# Quran

[![CI](https://github.com/nulltuple/quran/actions/workflows/ci.yml/badge.svg)](https://github.com/nulltuple/quran/actions/workflows/ci.yml)

**Quran** is an iPhone and iPad Quran reader, distributed through TestFlight as the App Store Connect app MemQuran (`com.nulltup.memquran`). It is a fork of [QuranEngine](https://github.com/quran/quran-ios), the open-source library behind the [Quran.com iOS App](https://apps.apple.com/app/id1118663303). The library's modules keep their `QuranEngine` names; the app lives in [Example](Example) as QuranEngineApp.

This repository also hosts a **second, separate app, Arabican** (App Store Connect "Arabican", `com.nulltup.arabican`): a Quranic Arabic learning app in [ArabicLearning](ArabicLearning) (its Swift package, which reuses QuranEngine's modules) and [Apps/Arabican](Apps/Arabican) (its Xcode project). Its spec, roadmap and handoff are in [Documentation/ArabicLearning](Documentation/ArabicLearning/HANDOFF.md).

**Only AI agents write code in this repository.** Read [AGENTS.md](AGENTS.md) before any change: it is the binding contract (no subagents, no unverified claims, explicit trade-offs, shared business logic, tests with every change, a [change trail](Documentation/trail/README.md) entry, push, and a TestFlight upload).

## Requirements

- Xcode 27.1 or later. CI builds with Xcode 27.2.
- iOS 15 or later.
- Swift Package Manager. We do not support CocoaPods or Carthage, and we do not plan to support them.

## Installation

Add the package with Swift Package Manager:

```swift
.package(url: "https://github.com/quran/quran-ios", branch: "main")
```

Then use one or more of its targets as dependencies. Every target is available as a product, for example:

```swift
.product(name: "AppStructureFeature", package: "quran-ios"),
```

To pin a release, use the commit of its tag with `.package(url: "https://github.com/quran/quran-ios", revision: "<commit>")`. Releases are tagged with the app's version. Version requirements such as `from:` do not work, because QuranEngine depends on a package that is pinned to a branch.

## Run the Example App

```sh
make run-example-no-sync
```

This builds the app, boots an iPhone simulator on the latest installed iOS, installs the app, and launches it. Use `make run-example-sync` for the sync-enabled build.

## Release

```sh
make release-testflight
```

This archives the pushed `main` commit and uploads it to TestFlight. See [Documentation/agents/release-testflight.md](Documentation/agents/release-testflight.md).

## Building and Testing

Every build and test command names its sync mode. `QURAN_SYNC` turns on Quran.com account sync, which adds the [mobile-sync-spm](https://github.com/quran/mobile-sync-spm) package. The `-no-sync` and `-sync` targets set it explicitly, so a value left in your shell never changes the build. Code behind `#if QURAN_SYNC` must compile in both modes.

```sh
# Build the package, or one scheme
make build-no-sync
make build-sync TARGET=NoorUI

# Run the complete package test plan
make test-no-sync
make test-sync

# Run one test target through the package test scheme
make test-no-sync TARGET=AyahMenuFeature
make test-sync TARGET=AyahMenuFeatureTests

# Check formatting
make format-lint
```

For test commands, `TARGET` accepts either the production target or its `Tests` target. Both focused examples above select `AyahMenuFeatureTests`. New test targets must also be added to `QuranEngine-Package.xctestplan`.

## Architecture

The library is split into 6 layers, each a top-level directory:

* **Core**: General purpose libraries that work with any app. The only exception is the Localization library, which we aim to make more universal.

* **Model**: Contains simple entities that facilitate building a Quran App. These entities mostly work together without including extensive logic.

* **Data**: Persistence and networking: SQLite (GRDB), Core Data, downloads, authentication, and the sync-backed stores. These libraries abstract away the underlying technologies.

* **Domain**: This is where the business logic of the app resides. It depends on Model and Data to serve such business logic.

* **UI**: Houses the design system used by the App, NoorUI. Components are built with SwiftUI; navigation stays in UIKit. UI does not depend on Domain or Data, but can depend on Core and Model.

* **Features**: Comprises the screens making up the app. They rely on all other components to create our Quran apps. Features can encompass other features to create higher-level features. For example, `AppStructureFeature` hosts all other features to create the app.

```mermaid
flowchart TD
    Apps["Quran app (Example/QuranEngineApp)"] --> Features
    Features --> Domain
    Features --> UI
    Domain --> Data
    Data --> Model
    UI --> Model
    Model --> Core
    Data -.-> Sync["mobile-sync-spm<br>QURAN_SYNC builds only"]
    Domain -.-> Sync
    Features -.-> Sync
```

A layer may import any layer it can reach by following the arrows, plus other targets in its own layer. [Package.swift](Package.swift) enforces this: `TargetType.validDependencies` lists what each layer may import, and `validateDependenciesStructure` stops the manifest from loading when a target breaks the rule.

The other top-level directories are:

* **Example**: QuranEngineApp, the Quran app.
* **Tools**: Developer scripts: terminal SwiftUI previews, app icon export, agent guardrails and the TestFlight release.
* **Documentation**: Guides for specific workflows, agent runbooks, and the change trail.
* **Branding**: The app icon's 1024 px iOS and macOS PNG masters, generated from the Icon Composer icon.
* **AllTargetsTests**: Links targets without their own tests, so coverage reports include them.

## More Documentation

* [SwiftUI previews from the terminal](Documentation/Previews.md): run a file's `#Preview`s on a simulator with `make preview`.
* [Mobile sync local development](Documentation/MobileSyncLocalDevelopment.md): the `QURAN_SYNC` flag, OAuth settings, and building against local `mobile-sync` checkouts.
* [Releasing to TestFlight](Documentation/agents/release-testflight.md) and the [feature cost register](Documentation/agents/feature-cost-register.md).
* [Change trail](Documentation/trail/README.md): why every change since the fork was made.

## Contributions

Changes are made by AI agents under [AGENTS.md](AGENTS.md). Upstream QuranEngine welcomes contributions at [quran/quran-ios](https://github.com/quran/quran-ios).

## Intended Use

We are re-open sourcing the app because we see a lot of benefits in allowing developers to build on top of what we have already built. This way, developers don't have to re-implement the foundation and can innovate more on the idea itself. The malicious behavior we've seen previously, including but not limited to selling this free code to people who are not aware of this repo's existence, is negligible compared to the overall benefit of giving what we have implemented to others. We look forward to seeing great Islamic innovation that helps Muslims everywhere inshaa'Allah.

We welcome all types of use. However, we kindly ask that you don't use the QuranEngineApp example and republish it without making any modifications. You may also need to bring your own data.

## License and Credits

* QuranEngine is available under the Apache-2.0 license. See the [LICENSE](LICENSE) file for more info.
* The classic Madani (1405 AH) page images come from the [quran images project](https://github.com/quran/quran.com-images) on GitHub. The Medina 1421, 1439, 1440, and 1441 and the IndoPak page images are from the King Fahd Quran Printing Complex, and the Tajweed page images are from the Dar al-Marefa edition.
* Translation, tafsir, and Arabic data come from [QuranEnc](https://quranenc.com) and [King Saud University](https://quran.ksu.edu.sa). A small number of translations also come from [Tanzil](https://tanzil.net).
* Data is licensed under the licenses of its authors, typically [CC BY-NC-ND](https://creativecommons.org/licenses/by-nc-nd/2.0/), but this may differ depending on the source.
