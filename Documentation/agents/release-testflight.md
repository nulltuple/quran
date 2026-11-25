# Releasing to TestFlight

TestFlight is the only release channel. Every change that can alter the shipped app is pushed to
`origin/main` and then uploaded to TestFlight from that commit (AGENTS.md, definition of done,
step 7).

## Fixed identity

| Item | Value |
|---|---|
| App Store Connect app | MemQuran |
| Name under the icon | Quran |
| Bundle ID | `com.nulltup.memquran` |
| Team ID | `NBMD2V39VV` |
| Devices | iPhone and iPad (one universal iOS target) |
| Variant | no-sync (`QURAN_SYNC` unset) |
| iCloud / CloudKit | none |

The values live in `Tools/lib/app-identity.sh`. `Tools/release.test.sh` fails if the Xcode project,
`Info.plist` or `Makefile` disagree with it.

## Uploading a build

```sh
make release-testflight                        # archive, sign and upload
make release-testflight ARGS=--export-only     # archive and sign locally, upload nothing
make release-testflight ARGS=--allow-unpushed  # dry run on an unpushed commit (export only)
```

`Tools/release-testflight.sh` is the only supported path; read it before changing it. Its
contract:

1. It refuses a dirty tree, and a `HEAD` that is not on `origin/main` (unless
   `--allow-unpushed`, which never uploads).
2. The marketing version is the Example project's single `MARKETING_VERSION`; the build number
   (`CFBundleVersion`) is `git rev-list --count HEAD`, monotonic because `main` is never
   force-pushed. Bump `MARKETING_VERSION` in the project, in its own trail entry, when the owner
   asks for a new version.
3. It archives `QuranEngineApp` in Release for `generic/platform=iOS` with `QURAN_SYNC` unset and
   `-allowProvisioningUpdates`, so Xcode creates or refreshes the App Store profile.
4. It checks the archived app's bundle ID, display name, version and build
   (`quran_verify_bundle_identity`), and that `HEAD` and tracked files did not change during the
   build.
5. It exports with `method app-store-connect`, `destination upload`, automatic signing for the
   team, and uploads symbols. Logs: `.build/testflight/archive.log` and `export.log`.
6. It prints `Uploaded Quran iOS <version> (<build>) for commit <sha> ...`. Record that line in
   the trail entry.

Requirements on the build Mac: Xcode signed in (Settings > Accounts) with an Apple ID that can
manage certificates and profiles for team `NBMD2V39VV`. Agents cannot sign in for the owner.

Builds appear in App Store Connect > MemQuran > TestFlight after processing, usually within
minutes. Processing problems arrive by email to the account holder; agents cannot see them, so ask
the owner if a build does not appear. Export compliance is answered in the build
(`ITSAppUsesNonExemptEncryption = NO`: the app uses only HTTPS and the system's own encryption).

## iCloud and CloudKit schema

The app uses no iCloud today (`Container.supportsCloudKit` is `false`, no iCloud entitlement). If
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
