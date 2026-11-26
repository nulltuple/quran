#!/bin/bash
#
# The Quran app (root Package.resolved) and the Arabican app (ArabicLearning/Package.resolved and
# the Arabican project's resolved file) share QuranEngine's dependencies. Every package pinned
# in more than one of these files must be pinned to the same version, so both apps build the
# shared modules from identical sources. Packages only Arabican uses may appear only in its files.
# Run: bash Tools/package-pins.test.sh (or make test-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

passed=0
failed=0
check() {
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

# same_pins <a.resolved> <b.resolved>: shared identities have the same version and revision.
same_pins() {
    python3 -I - "$1" "$2" <<'PY'
import json, sys

def pins(path):
    with open(path) as f:
        return {p["identity"]: (p["state"].get("version"), p["state"].get("revision")) for p in json.load(f)["pins"]}

a, b = pins(sys.argv[1]), pins(sys.argv[2])
bad = [f"{k}: {a[k]} vs {b[k]}" for k in sorted(a.keys() & b.keys()) if a[k] != b[k]]
if bad:
    print("\n".join(bad))
    sys.exit(1)
PY
}

root="$ROOT/Package.resolved"
learning="$ROOT/ArabicLearning/Package.resolved"
app="$ROOT/Apps/Arabican/Arabican.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

# The checker itself.
printf '{"pins":[{"identity":"grdb.swift","state":{"version":"6.29.2","revision":"a"}}]}' > "$scratch/one.json"
printf '{"pins":[{"identity":"grdb.swift","state":{"version":"6.29.3","revision":"b"}},{"identity":"swift-fsrs","state":{"version":"5.0.0","revision":"c"}}]}' > "$scratch/two.json"
printf '{"pins":[{"identity":"grdb.swift","state":{"version":"6.29.2","revision":"a"}},{"identity":"swift-fsrs","state":{"version":"5.0.0","revision":"c"}}]}' > "$scratch/three.json"
check "detects a shared package pinned to different versions" fails same_pins "$scratch/one.json" "$scratch/two.json"
check "allows packages only one app uses" same_pins "$scratch/one.json" "$scratch/three.json"

# The repository's files.
check "ArabicLearning pins QuranEngine's dependencies to the Quran app's versions" same_pins "$root" "$learning"
check "the Arabican project pins QuranEngine's dependencies to the Quran app's versions" same_pins "$root" "$app"
check "the Arabican project and the ArabicLearning package agree" same_pins "$learning" "$app"

echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
