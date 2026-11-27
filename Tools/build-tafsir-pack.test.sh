#!/bin/bash
#
# Tests Tools/build-tafsir-pack.py on a fixture shaped like Quran.com API v4 `by_chapter` entries.
# Run: bash Tools/build-tafsir-pack.test.sh (or make test-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/Tools/build-tafsir-pack.py"
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
text_of() { sqlite3 "$1" "SELECT text FROM verses WHERE sura = $2 AND ayah = $3"; }

# A fixture with every ayah: 2:8 starts a passage that 2:9 continues, 3:1 has no text (a sura's
# first ayah never continues the previous sura's passage), and 1:1 has headings, entities and inline tags.
python3 -I - "$TOOL" "$scratch" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("tool", sys.argv[1])
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
entries = []
for sura, count in enumerate(tool.AYAH_COUNTS, start=1):
    for ayah in range(1, count + 1):
        entries.append({"verse_key": f"{sura}:{ayah}", "text": f"<p>Explanation of {sura}:{ayah}</p>"})
def put(key, text):
    next(e for e in entries if e["verse_key"] == key)["text"] = text
put("1:1", "<h2>The  Opener</h2><p>Al-Fatihah &amp; its <em>names</em>,<br>said Ibn &#39;Abbas.</p>")
put("2:9", "")
put("3:1", "")
json.dump({"resource_id": 1, "tafsirs": entries}, open(f"{sys.argv[2]}/raw.json", "w"))
missing = [e for e in entries if e["verse_key"] != "114:6"]
json.dump({"resource_id": 1, "tafsirs": missing}, open(f"{sys.argv[2]}/missing.json", "w"))
json.dump({"resource_id": 1, "tafsirs": entries + [entries[0]]}, open(f"{sys.argv[2]}/duplicate.json", "w"))
PY

db="$scratch/quran.en.test.db"
check "builds a pack from a complete download" python3 -I "$TOOL" build "$scratch/raw.json" "$db" 3
check "has one row per ayah" equals "$(sqlite3 "$db" 'SELECT count(*) FROM verses')" 6236
check "keeps the feed's schema and the text version" equals "$(sqlite3 "$db" "SELECT group_concat(property || '=' || value, ',') FROM properties")" "schema_version=5,text_version=3"
check "is searchable like the feed's packs" equals "$(sqlite3 "$db" "SELECT sura || ':' || ayah FROM verses WHERE verses MATCH 'opener'")" "1:1"
check "turns HTML into paragraphs and decodes entities" equals "$(text_of "$db" 1 1)" "$(printf "The Opener\n\nAl-Fatihah & its names,\n\nsaid Ibn 'Abbas.")"
check "keeps plain explanations" equals "$(text_of "$db" 2 8)" "Explanation of 2:8"
check "stores a passage continuation as the 1-based index of its first ayah" equals "$(text_of "$db" 2 9)" "15"
check "leaves a sura's first ayah without text empty" equals "$(text_of "$db" 3 1)" ""
check "refuses a download missing an ayah" fails python3 -I "$TOOL" build "$scratch/missing.json" "$scratch/missing.db" 1
check "refuses a download with a duplicate ayah" fails python3 -I "$TOOL" build "$scratch/duplicate.json" "$scratch/duplicate.db" 1
check "zips only the database, under its own name" python3 -I "$TOOL" zip "$db" "$scratch/pack.zip"
check "the zip lists the database" equals "$(unzip -Z1 "$scratch/pack.zip")" "quran.en.test.db"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
