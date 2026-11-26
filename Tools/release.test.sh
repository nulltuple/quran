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

# app_identity_select picks exactly one app and refuses anything else.
check "selects the Quran app" equals "$(app_identity_select quran && echo "$APP_BUNDLE_ID $APP_PROJECT")" "$QURAN_BUNDLE_ID $QURAN_EXAMPLE_PROJECT"
check "selects the Arabican app" equals "$(app_identity_select arabican && echo "$APP_BUNDLE_ID $APP_PROJECT $APP_STORE_CONNECT_NAME")" "$ARABICAN_BUNDLE_ID $ARABICAN_PROJECT $ARABICAN_APP_STORE_CONNECT_NAME"
check "rejects an unknown app" fails app_identity_select memquran
check "rejects a missing app" fails app_identity_select
check "the two apps never share a bundle id" fails equals "$QURAN_BUNDLE_ID" "$ARABICAN_BUNDLE_ID"
check "the release script requires --app" fails bash "$ROOT/Tools/release-testflight.sh" --export-only

# Each project, and the Makefile, agree with Tools/lib/app-identity.sh.
values() { sed -nE "s/^[[:space:]]*$2 = \"?([^\";]+)\"?;\$/\\1/p" "$1" | sort -u | tr '\n' ' ' | sed 's/ $//'; }
check_project_identity() {
    # check_project_identity <label> <project dir> <bundle id> <team> <display name>
    local label="$1" pbxproj="$ROOT/$2/project.pbxproj"
    check "$label: every configuration uses the shipped bundle id" equals "$(values "$pbxproj" PRODUCT_BUNDLE_IDENTIFIER)" "$3"
    check "$label: every configuration uses the shipped team" equals "$(values "$pbxproj" DEVELOPMENT_TEAM)" "$4"
    check "$label: every configuration uses the display name" equals "$(values "$pbxproj" INFOPLIST_KEY_CFBundleDisplayName)" "$5"
    check "$label: every configuration declares exempt encryption" equals "$(values "$pbxproj" INFOPLIST_KEY_ITSAppUsesNonExemptEncryption)" "NO"
    check "$label: the project has one MARKETING_VERSION" quran_marketing_version "$pbxproj"
}
check_project_identity Quran "$QURAN_EXAMPLE_PROJECT" "$QURAN_BUNDLE_ID" "$QURAN_TEAM_ID" "$QURAN_DISPLAY_NAME"
check_project_identity Arabican "$ARABICAN_PROJECT" "$ARABICAN_BUNDLE_ID" "$ARABICAN_TEAM_ID" "$ARABICAN_DISPLAY_NAME"
check "Quran: the URL type is named by the bundle id" equals "$(quran_plist_value "$ROOT/Example/QuranEngineApp/Info.plist" 'CFBundleURLTypes:0:CFBundleURLName')" "$QURAN_BUNDLE_ID"
check "Quran: make run-example launches the shipped bundle id" grep -qxF "EXAMPLE_BUNDLE_IDENTIFIER ?= $QURAN_BUNDLE_ID" "$ROOT/Makefile"
check "Quran: the Makefile builds the shipped project and scheme" grep -qxF "EXAMPLE_SCHEME ?= $QURAN_EXAMPLE_SCHEME" "$ROOT/Makefile"
check "Arabican: make run-arabican launches the shipped bundle id" grep -qxF "ARABICAN_BUNDLE_IDENTIFIER ?= $ARABICAN_BUNDLE_ID" "$ROOT/Makefile"
check "Arabican: the Makefile builds the shipped project" grep -qxF "ARABICAN_PROJECT ?= $ARABICAN_PROJECT" "$ROOT/Makefile"
check "Arabican: the Makefile builds the shipped scheme" grep -qxF "ARABICAN_SCHEME ?= $ARABICAN_SCHEME" "$ROOT/Makefile"
check "Arabican: the scheme builds the Arabican target" grep -qF 'BuildableName = "Arabican.app"' "$ROOT/$ARABICAN_PROJECT/xcshareddata/xcschemes/$ARABICAN_SCHEME.xcscheme"

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
