#!/bin/bash
#
# Archives the pushed HEAD of main and uploads it to TestFlight
# (App Store Connect app "MemQuran", bundle com.nulltup.memquran, iPhone and iPad).
#
# Usage:
#   Tools/release-testflight.sh                   # archive, sign and upload
#   Tools/release-testflight.sh --export-only     # archive and sign locally, upload nothing
#   Tools/release-testflight.sh --allow-unpushed  # dry run on a local commit (implies --export-only)
#
# The build is the no-sync variant (QURAN_SYNC unset): sync needs Quran.com OAuth credentials
# this app does not have. Marketing version comes from MARKETING_VERSION in the Example project;
# the build number is `git rev-list --count HEAD`.
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

WORK="${QURAN_TESTFLIGHT_WORK_DIR:-$ROOT/.build/testflight}"
DERIVED_DATA="${QURAN_TESTFLIGHT_DERIVED_DATA:-$ROOT/.build/DerivedData/testflight}"

destination="upload"
allow_unpushed=0
while [ $# -gt 0 ]; do
    case "$1" in
        --export-only) destination="export" ;;
        --allow-unpushed) allow_unpushed=1; destination="export" ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

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

version="$(quran_marketing_version "$QURAN_EXAMPLE_PROJECT/project.pbxproj")"
build_number="$(quran_build_number "$ROOT")"
echo "$QURAN_DISPLAY_NAME $version ($build_number) from $head_sha -> $destination"

rm -rf "$WORK"
mkdir -p "$WORK"
archive="$WORK/$QURAN_EXAMPLE_SCHEME.xcarchive"

echo "==> Archiving (log: $WORK/archive.log)"
if ! env QURAN_SYNC= xcrun xcodebuild archive \
    -project "$QURAN_EXAMPLE_PROJECT" \
    -scheme "$QURAN_EXAMPLE_SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$QURAN_TEAM_ID" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    > "$WORK/archive.log" 2>&1; then
    grep -E "error:" "$WORK/archive.log" | head -30 >&2 || tail -60 "$WORK/archive.log" >&2
    echo "Archive failed; see $WORK/archive.log" >&2
    exit 1
fi

quran_verify_bundle_identity "$archive/Products/Applications/$QURAN_EXAMPLE_SCHEME.app/Info.plist" \
    "$QURAN_BUNDLE_ID" "$QURAN_DISPLAY_NAME" "$version" "$build_number"

# The archive read the working tree; if HEAD or tracked files changed meanwhile (another
# agent or session), the binary may not match $head_sha.
if [ "$(git rev-parse HEAD)" != "$head_sha" ] || ! tree_is_clean; then
    echo "HEAD or the working tree changed during the build; it may not match $head_sha. Not uploading." >&2
    exit 1
fi

echo "==> Exporting (log: $WORK/export.log)"
quran_write_export_options "$WORK/ExportOptions.plist" "$QURAN_TEAM_ID" "$destination"
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
    echo "Uploaded $QURAN_DISPLAY_NAME iOS $version ($build_number) for commit $head_sha to App Store Connect app $QURAN_APP_STORE_CONNECT_NAME."
    echo "Record this in the trail entry: TestFlight build $build_number ($version), commit $head_sha."
else
    echo "Exported $QURAN_DISPLAY_NAME iOS $version ($build_number) to $WORK/export (not uploaded)."
fi
