# Helpers shared by Tools/release-testflight.sh and its tests (Tools/release.test.sh).
# Source this file; it defines functions only.

# quran_marketing_version <project.pbxproj>
# Prints the project's single MARKETING_VERSION, or fails if configurations disagree.
quran_marketing_version() {
    local versions
    versions="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION = "?([^";]+)"?;$/\1/p' "$1" | sort -u)"
    if [ -z "$versions" ]; then
        echo "No MARKETING_VERSION in $1" >&2
        return 1
    fi
    if [ "$(printf '%s\n' "$versions" | wc -l | tr -d ' ')" != 1 ]; then
        echo "Build configurations in $1 disagree on MARKETING_VERSION: $(echo $versions)" >&2
        return 1
    fi
    printf '%s\n' "$versions"
}

# quran_build_number <repository>
# CFBundleVersion: the commit count of HEAD, monotonic because main is never force-pushed.
quran_build_number() {
    git -C "$1" rev-list --count HEAD
}

# quran_plist_value <Info.plist> <key>
quran_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

# quran_verify_bundle_identity <Info.plist> <bundle id> <display name> <version> <build>
# Fails, naming each mismatch, unless the built app carries exactly this identity.
quran_verify_bundle_identity() {
    local plist="$1" status=0 key expected actual
    for pair in "CFBundleIdentifier=$2" "CFBundleDisplayName=$3" "CFBundleShortVersionString=$4" "CFBundleVersion=$5"; do
        key="${pair%%=*}"
        expected="${pair#*=}"
        actual="$(quran_plist_value "$plist" "$key" || true)"
        if [ "$actual" != "$expected" ]; then
            echo "$plist: $key is '$actual', expected '$expected'" >&2
            status=1
        fi
    done
    return "$status"
}

# quran_write_export_options <output.plist> <team id> <upload|export>
quran_write_export_options() {
    cat > "$1" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>$3</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$2</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST
    plutil -lint "$1" > /dev/null
}
