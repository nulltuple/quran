#!/bin/bash
#
# Checks that every icon the Example app names exists, so a renamed asset can't ship a blank
# App Icon preview or a missing alternate icon, and that the shipped icon keeps a pure black
# background. The Example app has no test target, so this runs as a tool test.
# Run: bash Tools/example-app-icons.test.sh (or make test-tools)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$ROOT/Example/QuranEngineApp/Resources"
CATALOG="$ROOT/Example/QuranEngineApp/Classes/AppIconCatalog+Example.swift"
PBXPROJ="$ROOT/Example/QuranEngineApp.xcodeproj/project.pbxproj"

passed=0
failed=0
check() {
    local description="$1"
    shift
    if "$@"; then
        passed=$((passed + 1))
        echo "ok - $description"
    else
        failed=$((failed + 1))
        echo "not ok - $description"
    fi
}

# Image sets named by the catalog's previewImageName and artworkImageName.
names="$(sed -nE 's/.*(previewImageName|artworkImageName): "([^"]+)".*/\2/p' "$CATALOG")"
check "the catalog names preview and artwork images" [ -n "$names" ]
has_png() { compgen -G "$RESOURCES/Assets.xcassets/$1.imageset/*.png" > /dev/null; }
for name in $names; do
    check "image set $name has a PNG" has_png "$name"
done

# Alternate icons named by the catalog and by the build settings.
for name in $(sed -nE 's/.*alternateIconName: "([^"]+)".*/\1/p' "$CATALOG"); do
    check "alternate icon $name exists" [ -f "$RESOURCES/$name.icon/icon.json" ]
    check "alternate icon $name is in ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES" \
        grep -qE "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = \"?([^\";]* )?$name[ \";]" "$PBXPROJ"
done
check "the primary icon exists" [ -f "$RESOURCES/AppIcon.icon/icon.json" ]

# Every image an icon's layers name is in its Assets folder.
for icon in "$RESOURCES"/*.icon; do
    for image in $(sed -nE 's/.*"image-name" : "([^"]+)".*/\1/p' "$icon/icon.json"); do
        check "$(basename "$icon") has its layer image $image" [ -f "$icon/Assets/$image" ]
    done
done

# The primary icon is the white glyph on pure black.
check "the primary icon's fill is solid black" \
    grep -qF '"solid" : "srgb:0.00000,0.00000,0.00000,1.00000"' "$RESOURCES/AppIcon.icon/icon.json"
png_property() { sips -g "$2" "$1" | sed -nE "s/^ +$2: //p"; }
check "the iOS master is 1024 px" [ "$(png_property "$ROOT/Branding/AppIcon-iOS-1024.png" pixelWidth)" = 1024 ]
check "the iOS master is opaque" [ "$(png_property "$ROOT/Branding/AppIcon-iOS-1024.png" hasAlpha)" = no ]
check "the macOS master is 1024 px" [ "$(png_property "$ROOT/Branding/AppIcon-macOS-1024.png" pixelWidth)" = 1024 ]
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/corner.swift" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let context = CGContext(
    data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
    space: image.colorSpace!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
// Draw so that the top-left pixel of the image lands on the 1x1 context.
context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
let pixel = context.data!.bindMemory(to: UInt8.self, capacity: 4)
print(pixel[0], pixel[1], pixel[2])
SWIFT
corner="$(xcrun swift "$scratch/corner.swift" "$ROOT/Branding/AppIcon-iOS-1024.png")"
check "the iOS master's corner is #000000 (got $corner)" [ "$corner" = "0 0 0" ]

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
