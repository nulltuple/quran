#!/bin/bash
#
# Archives the pushed HEAD of main and uploads ONE app to TestFlight. This repository ships
# two apps; --app is required so a release never goes to the wrong one:
#   --app quran     Quran reader, App Store Connect "MemQuran", com.nulltup.memquran
#   --app arabican  Arabic learning app, App Store Connect "Arabican", com.nulltup.arabican
#
# Usage:
#   Tools/release-testflight.sh --app <quran|arabican>                   # archive, sign and upload
#   Tools/release-testflight.sh --app <quran|arabican> --export-only     # archive and sign locally, upload nothing
#   Tools/release-testflight.sh --app <quran|arabican> --allow-unpushed  # dry run on a local commit (implies --export-only)
#
# Both builds are no-sync (QURAN_SYNC unset): sync needs Quran.com OAuth credentials the apps
# do not have. Marketing version comes from the app project's MARKETING_VERSION; the build
# number is `git rev-list --count HEAD` (shared by both apps, monotonic for each).
#
# Requirements: Xcode signed in (Settings > Accounts) with an account that can manage
# certificates and profiles for the team in Tools/lib/app-identity.sh.
# See Documentation/agents/release-testflight.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/app-identity.sh
source "$ROOT/Tools/lib/app-identity.sh"
# shellcheck source=lib/release.sh
source "$ROOT/Tools/lib/release.sh"

destination="upload"
allow_unpushed=0
app=""
while [ $# -gt 0 ]; do
    case "$1" in
        --app) app="${2:-}"; shift ;;
        --export-only) destination="export" ;;
        --allow-unpushed) allow_unpushed=1; destination="export" ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$app" ]; then
    echo "--app quran|arabican is required: this repository ships two apps." >&2
    exit 2
fi
app_identity_select "$app" || exit 2

WORK="${QURAN_TESTFLIGHT_WORK_DIR:-$ROOT/.build/testflight/$APP_KEY}"
DERIVED_DATA="${QURAN_TESTFLIGHT_DERIVED_DATA:-$ROOT/.build/DerivedData/testflight-$APP_KEY}"

cd "$ROOT"
tree_is_clean() { [ -z "$(git status --porcelain --untracked-files=no)" ]; }
if ! tree_is_clean; then
    echo "Refusing to release a dirty tree; commit first." >&2
    exit 1
fi
git fetch --quiet origin main
head_sha="$(git rev-parse HEAD)"
if [ "$allow_unpushed" != 1 ] && ! git merge-base --is-ancestor "$head_sha" origin/main; then
    echo "HEAD $head_sha is not on origin/main. Push first, or use --allow-unpushed for a dry run." >&2
    exit 1
fi

version="$(quran_marketing_version "$APP_PROJECT/project.pbxproj")"
build_number="$(quran_build_number "$ROOT")"
echo "$APP_DISPLAY_NAME ($APP_BUNDLE_ID, App Store Connect $APP_STORE_CONNECT_NAME) $version ($build_number) from $head_sha -> $destination"

rm -rf "$WORK"
mkdir -p "$WORK"
archive="$WORK/$APP_SCHEME.xcarchive"

echo "==> Archiving (log: $WORK/archive.log)"
# shellcheck disable=SC2086  # APP_RESOLVE_FLAGS is a word list
if ! env QURAN_SYNC= xcrun xcodebuild archive $APP_RESOLVE_FLAGS \
    -project "$APP_PROJECT" \
    -scheme "$APP_SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$APP_TEAM_ID" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    > "$WORK/archive.log" 2>&1; then
    grep -E "error:" "$WORK/archive.log" | head -30 >&2 || tail -60 "$WORK/archive.log" >&2
    echo "Archive failed; see $WORK/archive.log" >&2
    exit 1
fi

quran_verify_bundle_identity "$archive/Products/Applications/$APP_SCHEME.app/Info.plist" \
    "$APP_BUNDLE_ID" "$APP_DISPLAY_NAME" "$version" "$build_number"

# The archive read the working tree; if HEAD or tracked files changed meanwhile (another
# agent or session), the binary may not match $head_sha.
if [ "$(git rev-parse HEAD)" != "$head_sha" ] || ! tree_is_clean; then
    echo "HEAD or the working tree changed during the build; it may not match $head_sha. Not uploading." >&2
    exit 1
fi

echo "==> Exporting (log: $WORK/export.log)"
quran_write_export_options "$WORK/ExportOptions.plist" "$APP_TEAM_ID" "$destination"
set +e
xcrun xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" \
    -exportPath "$WORK/export" \
    -allowProvisioningUpdates \
    > "$WORK/export.log" 2>&1
status=$?
set -e
grep -E "Upload succeeded|EXPORT SUCCEEDED|error:|Error " "$WORK/export.log" | tail -5 || true
if [ "$status" -ne 0 ]; then
    echo "xcodebuild -exportArchive failed ($status); see $WORK/export.log" >&2
    exit "$status"
fi

if [ "$destination" = upload ]; then
    echo "Uploaded $APP_DISPLAY_NAME iOS $version ($build_number) for commit $head_sha to App Store Connect app $APP_STORE_CONNECT_NAME."
    echo "Record this in the trail entry: TestFlight build $build_number ($version), commit $head_sha."
else
    echo "Exported $APP_DISPLAY_NAME iOS $version ($build_number) to $WORK/export (not uploaded)."
fi
