# Releasing to TestFlight

TestFlight is the only release channel. This repository ships **two apps**, each with its own
App Store Connect app and release lane. Every change that can alter an app's binary is pushed to
`origin/main` and then that app is uploaded from that commit (AGENTS.md, definition of done,
step 7, and "Two apps, one repository", rule 5).

## Fixed identities

| Item | Quran | Arabican |
|---|---|---|
| App Store Connect app | MemQuran | Arabican |
| Name under the icon | Quran | Arabican |
| Bundle ID | `com.nulltup.memquran` | `com.nulltup.arabican` |
| Team ID | `NBMD2V39VV` | `NBMD2V39VV` |
| Project, scheme | `Example/QuranEngineApp.xcodeproj`, `QuranEngineApp` | `Apps/Arabican/Arabican.xcodeproj`, `Arabican` |
| Devices | iPhone and iPad (one universal iOS target) | iPhone and iPad (one universal iOS target) |
| Variant | no-sync (`QURAN_SYNC` unset) | no-sync |
| iCloud / CloudKit | none | none |
| Make target | `make release-testflight-quran` | `make release-testflight-arabican` |

The values live in `Tools/lib/app-identity.sh`. `Tools/release.test.sh` fails if either Xcode
project, the Quran `Info.plist` or the `Makefile` disagree with it.

## Uploading a build

```sh
make release-testflight-quran                          # Quran: archive, sign and upload to MemQuran
make release-testflight-arabican                       # Arabican: archive, sign and upload to Arabican
make release-testflight-arabican ARGS=--export-only    # archive and sign locally, upload nothing
make release-testflight-arabican ARGS=--allow-unpushed # dry run on an unpushed commit (export only)
```

`make release-testflight` without an app name prints both choices and fails, so a build never
goes to the wrong App Store Connect app. `Tools/release-testflight.sh --app <quran|arabican>` is
the only supported path; read it before changing it. Its contract:

1. It refuses a dirty tree, and a `HEAD` that is not on `origin/main` (unless
   `--allow-unpushed`, which never uploads).
2. The marketing version is the chosen app project's single `MARKETING_VERSION` (Quran 1.x,
   Arabican 0.x); the build number (`CFBundleVersion`) is `git rev-list --count HEAD`, shared by
   both apps and monotonic for each because `main` is never force-pushed. Bump
   `MARKETING_VERSION` in the project, in its own trail entry, when the owner asks for a new
   version.
3. It archives the app's scheme in Release for `generic/platform=iOS` with `QURAN_SYNC` unset and
   `-allowProvisioningUpdates`, so Xcode creates or refreshes the App Store profile.
4. It checks the archived app's bundle ID, display name, version and build
   (`quran_verify_bundle_identity`), and that `HEAD` and tracked files did not change during the
   build.
5. It exports with `method app-store-connect`, `destination upload`, automatic signing for the
   team, and uploads symbols. Logs: `.build/testflight/<app>/archive.log` and `export.log`.
6. It prints `Uploaded <Quran|Arabican> iOS <version> (<build>) for commit <sha> to App Store
   Connect app <MemQuran|Arabican>.` Record that line in the trail entry. Logs are under
   `.build/testflight/<quran|arabican>/`.

Requirements on the build Mac: Xcode signed in (Settings > Accounts) with an Apple ID that can
manage certificates and profiles for team `NBMD2V39VV`. Agents cannot sign in for the owner.

Builds appear in App Store Connect > MemQuran (or Arabican) > TestFlight after processing, usually within
minutes. Processing problems arrive by email to the account holder; agents cannot see them, so ask
the owner if a build does not appear. Export compliance is answered in the build
(`ITSAppUsesNonExemptEncryption = NO`: the app uses only HTTPS and the system's own encryption).

## iCloud and CloudKit schema

Neither app uses iCloud today. For the Quran app: (`Container.supportsCloudKit` is `false`, no iCloud entitlement). If
a change adds iCloud, CloudKit or another capability:

1. Ask the owner first (AGENTS.md, safety rails): a capability changes the App ID and the
   provisioning profile.
2. The container is `iCloud.com.nulltup.memquran` unless the owner names another. Record it in
   `Tools/lib/app-identity.sh` and the identity tables.
3. TestFlight and App Store builds use the **Production** CloudKit environment, which never
   creates record types itself. Development-signed builds create them in **Development**. After
   any record type, field or index change, stop and send the owner these instructions, filled in:

> **CloudKit schema deployment needed for MemQuran**
>
> 1. Open
>    <https://icloud.developer.apple.com/dashboard/database/teams/NBMD2V39VV/containers/iCloud.com.nulltup.memquran/environments/DEVELOPMENT/types>
>    and sign in with the Apple ID for team NBMD2V39VV. (The deep-link format is UNVERIFIED; if it
>    does not open, go to <https://icloud.developer.apple.com/>, choose CloudKit Database, then
>    the container `iCloud.com.nulltup.memquran`.)
> 2. Confirm the Development schema shows: *<record types, fields and indexes that changed>*.
>    If one is missing, run a Development-signed build once with the feature on, then reload.
> 3. Click **Deploy Schema Changes…**, check that the diff lists only those changes, then click
>    **Deploy**.
> 4. Reply "deployed", and the agent records it in the trail entry.
>
> Deployment cannot be undone: record types and fields cannot be removed from Production.

Until the owner replies, the trail entry's **Release** section says the schema is pending, and
testers' sync is expected to fail.
