# Shipped identities of the TWO apps built from this repository. Source this file; never
# hardcode these values elsewhere in tooling. Tools/release.test.sh checks that each Xcode
# project and the Makefile agree with it.
#
#   quran     Quran reader. App Store Connect "MemQuran". Project Example/ (QuranEngine package).
#   arabican  Arabic learning app. App Store Connect "Arabican". Project Apps/Arabican/
#             (ArabicLearning package, which depends on QuranEngine; never the reverse).
#
# Once a bundle identifier has shipped to TestFlight, renaming it strands testers' data.

QURAN_APP_STORE_CONNECT_NAME="MemQuran"
QURAN_DISPLAY_NAME="Quran"
QURAN_BUNDLE_ID="com.nulltup.memquran"
QURAN_TEAM_ID="NBMD2V39VV"
QURAN_EXAMPLE_PROJECT="Example/QuranEngineApp.xcodeproj"
QURAN_EXAMPLE_SCHEME="QuranEngineApp"

ARABICAN_APP_STORE_CONNECT_NAME="Arabican"
ARABICAN_DISPLAY_NAME="Arabican"
ARABICAN_BUNDLE_ID="com.nulltup.arabican"
ARABICAN_TEAM_ID="NBMD2V39VV"
ARABICAN_PROJECT="Apps/Arabican/Arabican.xcodeproj"
ARABICAN_SCHEME="Arabican"

# app_identity_select <quran|arabican>
# Sets APP_KEY, APP_STORE_CONNECT_NAME, APP_DISPLAY_NAME, APP_BUNDLE_ID, APP_TEAM_ID,
# APP_PROJECT and APP_SCHEME for one app, or fails for any other name.
app_identity_select() {
    case "${1:-}" in
        quran)
            APP_KEY=quran
            APP_STORE_CONNECT_NAME="$QURAN_APP_STORE_CONNECT_NAME"
            APP_DISPLAY_NAME="$QURAN_DISPLAY_NAME"
            APP_BUNDLE_ID="$QURAN_BUNDLE_ID"
            APP_TEAM_ID="$QURAN_TEAM_ID"
            APP_PROJECT="$QURAN_EXAMPLE_PROJECT"
            APP_SCHEME="$QURAN_EXAMPLE_SCHEME"
            ;;
        arabican)
            APP_KEY=arabican
            APP_STORE_CONNECT_NAME="$ARABICAN_APP_STORE_CONNECT_NAME"
            APP_DISPLAY_NAME="$ARABICAN_DISPLAY_NAME"
            APP_BUNDLE_ID="$ARABICAN_BUNDLE_ID"
            APP_TEAM_ID="$ARABICAN_TEAM_ID"
            APP_PROJECT="$ARABICAN_PROJECT"
            APP_SCHEME="$ARABICAN_SCHEME"
            ;;
        *)
            echo "unknown app '${1:-}': expected quran (MemQuran) or arabican (Arabican)" >&2
            return 1
            ;;
    esac
}
