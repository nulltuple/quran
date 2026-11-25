#!/bin/bash
#
# Tests the release helpers in Tools/lib/release.sh, and that the Xcode project, Info.plist
# and Makefile agree with the shipped identity in Tools/lib/app-identity.sh.
# Run: bash Tools/release.test.sh (or make test-tools). Needs macOS (PlistBuddy, plutil).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/Tools/lib/app-identity.sh"
source "$ROOT/Tools/lib/release.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

passed=0
failed=0
check() {
    # check <description> <command...>: passes when the command succeeds.
    local description="$1"
    shift
    if "$@" > "$scratch/out" 2>&1; then
        passed=$((passed + 1))
        echo "ok - $description"
    else
        failed=$((failed + 1))
        echo "not ok - $description"
        sed 's/^/    /' "$scratch/out"
    fi
}
fails() { ! "$@"; }
equals() { [ "$1" = "$2" ] || { echo "'$1' != '$2'"; return 1; }; }

# MARKETING_VERSION
printf '\t\tMARKETING_VERSION = 1.2.3;\n\t\tMARKETING_VERSION = 1.2.3;\n' > "$scratch/same.pbxproj"
printf '\t\tMARKETING_VERSION = 1.2.3;\n\t\tMARKETING_VERSION = 1.2.4;\n' > "$scratch/split.pbxproj"
printf '\t\tPRODUCT_NAME = App;\n' > "$scratch/none.pbxproj"
check "reads one MARKETING_VERSION" equals "$(quran_marketing_version "$scratch/same.pbxproj")" "1.2.3"
check "rejects disagreeing MARKETING_VERSIONs" fails quran_marketing_version "$scratch/split.pbxproj"
check "rejects a project without MARKETING_VERSION" fails quran_marketing_version "$scratch/none.pbxproj"
check "the Example project has one MARKETING_VERSION" quran_marketing_version "$ROOT/$QURAN_EXAMPLE_PROJECT/project.pbxproj"

# Build number
git -C "$scratch" init --quiet repo
git -C "$scratch/repo" -c user.email=t@example.com -c user.name=T commit --quiet --allow-empty -m one
git -C "$scratch/repo" -c user.email=t@example.com -c user.name=T commit --quiet --allow-empty -m two
check "build number is the commit count" equals "$(quran_build_number "$scratch/repo")" "2"

# Bundle identity
plist="$scratch/Info.plist"
plutil -create xml1 "$plist"
plutil -insert CFBundleIdentifier -string "$QURAN_BUNDLE_ID" "$plist"
plutil -insert CFBundleDisplayName -string "$QURAN_DISPLAY_NAME" "$plist"
plutil -insert CFBundleShortVersionString -string "1.2.3" "$plist"
plutil -insert CFBundleVersion -string "42" "$plist"
check "accepts the expected identity" quran_verify_bundle_identity "$plist" "$QURAN_BUNDLE_ID" "$QURAN_DISPLAY_NAME" 1.2.3 42
check "rejects another bundle id" fails quran_verify_bundle_identity "$plist" com.example.other "$QURAN_DISPLAY_NAME" 1.2.3 42
check "rejects another build number" fails quran_verify_bundle_identity "$plist" "$QURAN_BUNDLE_ID" "$QURAN_DISPLAY_NAME" 1.2.3 43
plutil -remove CFBundleDisplayName "$plist"
check "rejects a missing display name" fails quran_verify_bundle_identity "$plist" "$QURAN_BUNDLE_ID" "$QURAN_DISPLAY_NAME" 1.2.3 42

# Export options
quran_write_export_options "$scratch/upload.plist" "$QURAN_TEAM_ID" upload
check "export options upload to App Store Connect" equals "$(quran_plist_value "$scratch/upload.plist" destination)/$(quran_plist_value "$scratch/upload.plist" method)" "upload/app-store-connect"
check "export options name the team" equals "$(quran_plist_value "$scratch/upload.plist" teamID)" "$QURAN_TEAM_ID"
check "export options keep the build number" equals "$(quran_plist_value "$scratch/upload.plist" manageAppVersionAndBuildNumber)" "false"

# The project, Info.plist and Makefile agree with Tools/lib/app-identity.sh.
pbxproj="$ROOT/$QURAN_EXAMPLE_PROJECT/project.pbxproj"
values() { sed -nE "s/^[[:space:]]*$1 = \"?([^\";]+)\"?;\$/\\1/p" "$pbxproj" | sort -u | tr '\n' ' ' | sed 's/ $//'; }
check "every configuration uses the shipped bundle id" equals "$(values PRODUCT_BUNDLE_IDENTIFIER)" "$QURAN_BUNDLE_ID"
check "every configuration uses the shipped team" equals "$(values DEVELOPMENT_TEAM)" "$QURAN_TEAM_ID"
check "every configuration uses the display name" equals "$(values INFOPLIST_KEY_CFBundleDisplayName)" "$QURAN_DISPLAY_NAME"
check "every configuration declares exempt encryption" equals "$(values INFOPLIST_KEY_ITSAppUsesNonExemptEncryption)" "NO"
check "the URL type is named by the bundle id" equals "$(quran_plist_value "$ROOT/Example/QuranEngineApp/Info.plist" 'CFBundleURLTypes:0:CFBundleURLName')" "$QURAN_BUNDLE_ID"
check "make run-example launches the shipped bundle id" grep -qxF "EXAMPLE_BUNDLE_IDENTIFIER ?= $QURAN_BUNDLE_ID" "$ROOT/Makefile"
check "the Makefile builds the shipped project and scheme" grep -qxF "EXAMPLE_SCHEME ?= $QURAN_EXAMPLE_SCHEME" "$ROOT/Makefile"

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
