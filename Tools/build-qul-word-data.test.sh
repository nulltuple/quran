#!/bin/bash
#
# Tests Tools/build-qul-word-data.py and Tools/fetch-quran-com-words.py on small fixtures shaped
# like QUL's and Quran.com's data, and checks the databases built for the Example app and the
# package tests. Run: bash Tools/build-qul-word-data.test.sh (or make test-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/Tools/build-qul-word-data.py"
FETCH="$ROOT/Tools/fetch-quran-com-words.py"
RESOURCES="$ROOT/Example/QuranEngineApp/Resources"
TEST_DATA="$ROOT/Domain/TestResources/Sources/test_data"
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
query() { sqlite3 "$1" "$2"; }
recited() {
    # recited <db> <sura> <ayah>: the ayah's recited words, as word@start.
    query "$1" "SELECT group_concat(word || '@' || start, ' ') FROM (SELECT * FROM word_timings WHERE sura = $2 AND ayah = $3 ORDER BY seq)"
}
start_of() { query "$1" "SELECT time FROM timings WHERE sura = $2 AND ayah = $3"; }

# MARK: - timings

# Word counts come from QUL's translation: words, then the ayah-number pseudo-word.
sqlite3 "$scratch/counts.db" "CREATE TABLE word_translation (surah_number INTEGER, ayah_number INTEGER, word_number TEXT, text TEXT);"
for spec in 1:1:2 1:2:2 2:1:2 2:2:3 2:3:3 2:4:2 2:5:3 3:1:2 3:2:3; do
    IFS=: read -r sura ayah words <<< "$spec"
    for word in $(seq 1 "$words"); do
        sqlite3 "$scratch/counts.db" "INSERT INTO word_translation VALUES ($sura, $ayah, '$word', 'w$word')"
    done
    sqlite3 "$scratch/counts.db" "INSERT INTO word_translation VALUES ($sura, $ayah, '$((words + 1))', '($ayah)')"
done
sqlite3 "$scratch/recitation.db" <<'SQL'
CREATE TABLE segments (surah_number INTEGER, ayah_number INTEGER, duration_sec INTEGER, timestamp_from INTEGER, timestamp_to INTEGER, segments TEXT);
INSERT INTO segments VALUES (1, 1, 1, 0, 1000, '[[1,0,400],[2,450,1000]]');
-- A genuine repetition: the reciter goes back to word 1 and recites on.
INSERT INTO segments VALUES (1, 2, 1, 1200, 2500, '[[1,1200,1500],[2,1550,1800],[1,1850,2100],[2,2150,2500]]');
-- An inverted segment, and one far outside the ayah.
INSERT INTO segments VALUES (2, 1, 1, 0, 900, '[[1,0,500],[2,900,600],[2,50000,50100]]');
-- Word 2's segment trails the ayah after word 3 (QUL's commonest defect).
INSERT INTO segments VALUES (2, 2, 1, 1000, 2000, '[[1,1000,1300],[3,1350,1700],[2,1750,2000]]');
-- A stray word 2 before the recitation starts at word 1.
INSERT INTO segments VALUES (2, 3, 1, 2200, 3000, '[[2,2200,2300],[1,2350,2500],[2,2550,2700],[3,2750,3000]]');
-- The ayah's segments begin 3 s before its start, after the previous ayah ended.
INSERT INTO segments VALUES (2, 4, 1, 7000, 8000, '[[2,4000,5000],[1,7000,8000]]');
-- A word number the ayah doesn't have.
INSERT INTO segments VALUES (2, 5, 1, 8200, 9000, '[[1,8200,8500],[4,8550,8700],[2,8750,8800],[3,8850,9000]]');
-- 3:1's last word runs on through 3:2, whose segments begin inside it.
INSERT INTO segments VALUES (3, 1, 1, 0, 9000, '[[1,0,500],[2,550,9000]]');
INSERT INTO segments VALUES (3, 2, 1, 9200, 9600, '[[2,4000,4500],[3,4550,5000],[1,9200,9600]]');
SQL
check "builds timings" python3 -I "$TOOL" timings "$scratch/recitation.db" "$scratch/counts.db" "$scratch/timings.db"
check "writes ayah starts and sura ends" equals \
    "$(query "$scratch/timings.db" "SELECT group_concat(sura || ':' || ayah || '=' || time, ' ') FROM (SELECT * FROM timings WHERE sura < 3 ORDER BY sura, ayah)")" \
    "1:1=0 1:2=1200 1:999=2500 2:1=0 2:2=1000 2:3=2200 2:4=3200 2:5=8200 2:999=9000"
check "keeps a genuine repetition in recitation order" equals "$(recited "$scratch/timings.db" 1 2)" "1@1200 2@1550 1@1850 2@2150"
check "drops inverted segments and segments outside the ayah" equals "$(recited "$scratch/timings.db" 2 1)" "1@0"
check "drops a word that trails the ayah out of order" equals "$(recited "$scratch/timings.db" 2 2)" "1@1000 3@1350"
check "drops a stray word before the recitation starts over" equals "$(recited "$scratch/timings.db" 2 3)" "1@2350 2@2550 3@2750"
check "starts a late ayah when the previous one ended" equals "$(start_of "$scratch/timings.db" 2 4)" "3200"
check "keeps the late ayah's own words" equals "$(recited "$scratch/timings.db" 2 4)" "2@4000"
check "drops a word number the ayah doesn't have" equals "$(recited "$scratch/timings.db" 2 5)" "1@8200 2@8750 3@8850"
check "starts an ayah inside the previous ayah's overlong last word" equals "$(start_of "$scratch/timings.db" 3 2)" "4000"
check "ends the overlong word where the next ayah starts" equals \
    "$(query "$scratch/timings.db" "SELECT \"end\" FROM word_timings WHERE sura = 3 AND ayah = 1 AND word = 2")" "4000"
check "keeps the overlapped ayah's words in order" equals "$(recited "$scratch/timings.db" 3 2)" "2@4000 3@4550"
check "writes the timing database version" equals \
    "$(query "$scratch/timings.db" "SELECT value FROM properties WHERE property = 'version'")" "2"
sqlite3 "$scratch/empty.db" "CREATE TABLE segments (surah_number INTEGER, ayah_number INTEGER, duration_sec INTEGER, timestamp_from INTEGER, timestamp_to INTEGER, segments TEXT);"
check "rejects a recitation without segments" fails python3 -I "$TOOL" timings "$scratch/empty.db" "$scratch/counts.db" "$scratch/empty-out.db"
sqlite3 "$scratch/extra.db" ".read /dev/stdin" <<'SQL'
CREATE TABLE segments (surah_number INTEGER, ayah_number INTEGER, duration_sec INTEGER, timestamp_from INTEGER, timestamp_to INTEGER, segments TEXT);
INSERT INTO segments VALUES (9, 9, 1, 0, 100, '[[1,0,100]]');
SQL
check "rejects an ayah the translation doesn't have" fails python3 -I "$TOOL" timings "$scratch/extra.db" "$scratch/counts.db" "$scratch/extra-out.db"

# MARK: - Quran.com words

# Raw API verses: (word text, glyph codes) pairs; the last word is the ayah-number glyph.
python3 -I - "$scratch/raw.json" <<'PY'
import json, sys
ayahs = {
    # A pause mark after word 2 is a glyph of its own.
    "2:2": [("ذَٰلِكَ", "a"), ("ٱلْكِتَـٰبُ ۛ", "bc"), ("لَا", "d"), ("رَيْبَ", "e")],
    # A leading rub el hizb sign, separated by a space in the glyph codes.
    "2:3": [("۞ ٱلَّذِينَ", "f g"), ("يُؤْمِنُونَ", "h")],
    # Two QUL words drawn as one glyph.
    "2:4": [("فَمَنۢ", "i"), ("بَعْدَ مَا", "j")],
    # One QUL word written in two parts, two glyphs.
    "2:5": [("سَلَـٰمٌ", "k"), ("إِلْ يَاسِينَ", "lm")],
    # The page database has one glyph fewer than these codes.
    "2:6": [("ٱللَّهُ", "n"), ("لَآ", "o")],
    # The bundled text writes Quran.com's words 1 and 2 as one token.
    "2:7": [("لَّوْ", "p"), ("مَا", "q"), ("تَأْتِينَا", "r")],
    # A sajdah sign followed by a right-to-left mark, then a pause mark written without a space.
    "2:8": [("ٱلْعَظِيمِ ۩\u200f", "st"), ("عِوَجَاۜ", "uv")],
}
verses = []
for key, words in ayahs.items():
    entries = [{"position": index, "char_type_name": "word", "text_uthmani": text, "code_v1": codes,
                "v1_page": 1, "line_number": 1, "translation": {"text": f"qc{index}"},
                "transliteration": {"text": "baʿda mā" if text == "بَعْدَ مَا" else f"t{index}"},
                "audio_url": f"wbw/{index}.mp3"} for index, (text, codes) in enumerate(words, start=1)]
    entries.append({"position": len(words) + 1, "char_type_name": "end", "text_uthmani": "١", "code_v1": "z",
                    "v1_page": 1, "line_number": 1})
    verses.append({"verse_key": key, "words": entries})
json.dump({"verses": verses}, open(sys.argv[1], "w"), ensure_ascii=False)
PY
check "normalizes the Quran.com download" python3 -I "$FETCH" normalize "$scratch/raw.json" "$scratch/quran-com.json"
check "keeps each word's glyph codes" equals \
    "$(python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['ayahs'][0]['words'][1]['code_v1'])" "$scratch/quran-com.json")" "bc"
python3 -I - "$scratch/raw.json" "$scratch/raw-pause.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["verses"][0]["words"][0]["char_type_name"] = "pause"
json.dump(data, open(sys.argv[2], "w"), ensure_ascii=False)
PY
check "rejects a word type it doesn't know" fails python3 -I "$FETCH" normalize "$scratch/raw-pause.json" "$scratch/bad.json"

# MARK: - words

for language in english bengali; do
    sqlite3 "$scratch/$language.db" "CREATE TABLE word_translation (surah_number INTEGER, ayah_number INTEGER, word_number TEXT, text TEXT);"
done
# QUL words per ayah: 2:2 4, 2:3 2, 2:4 3 (بَعْدَ and مَا), 2:5 2, 2:6 2, 2:7 3, 2:8 2.
for spec in 2:4 3:2 4:3 5:2 6:2 7:3 8:2; do
    IFS=: read -r ayah words <<< "$spec"
    for word in $(seq 1 "$words"); do
        if [ "$ayah:$word" != "4:3" ]; then
            sqlite3 "$scratch/english.db" "INSERT INTO word_translation VALUES (2, $ayah, '$word', 'e$ayah.$word')"
            sqlite3 "$scratch/bengali.db" "INSERT INTO word_translation VALUES (2, $ayah, '$word', 'b$ayah.$word')"
        fi
    done
    sqlite3 "$scratch/english.db" "INSERT INTO word_translation VALUES (2, $ayah, '$((words + 1))', '($ayah)')"
done
sqlite3 "$scratch/arabic.db" <<'SQL'
CREATE TABLE arabic_text (sura integer, ayah integer, text text, primary key(sura, ayah));
INSERT INTO arabic_text VALUES (2, 2, 'ذَٰلِكَ ٱلۡكِتَٰبُ لَا رَيۡبَ'), (2, 3, '۞ٱلَّذِينَ يُؤۡمِنُونَ'), (2, 4, 'فَمَنۢ بَعۡدَ مَا'),
    (2, 5, 'سَلَٰمٌ إِلۡ يَاسِينَ'), (2, 6, 'ٱللَّهُ لَآ'), (2, 7, 'لَّوۡمَا تَأۡتِينَا'), (2, 8, 'ٱلۡعَظِيمِ۩ عِوَجَاۜ');
SQL
# Glyphs per ayah: the codes above plus the ayah-number glyph; 2:6 is one short.
sqlite3 "$scratch/ayahinfo.db" "CREATE TABLE glyphs(glyph_id int, page_number int, line_number int, sura_number int, ayah_number int, position int, min_x int, max_x int, min_y int, max_y int);"
id=0
for spec in 2:6 3:4 4:3 5:4 6:2 7:4 8:5; do
    IFS=: read -r ayah glyphs <<< "$spec"
    for position in $(seq 1 "$glyphs"); do
        id=$((id + 1))
        sqlite3 "$scratch/ayahinfo.db" "INSERT INTO glyphs VALUES ($id, 2, 1, 2, $ayah, $position, 0, 100, 0, 10)"
    done
done
words() { python3 -I "$TOOL" words "$scratch/english.db" "$scratch/bengali.db" "$1" "$scratch/arabic.db" "$scratch/ayahinfo.db" "$2"; }
glyphs_of() {
    query "$scratch/words.db" "SELECT group_concat(word || '>' || glyph_position, ' ') FROM (SELECT * FROM hafs_1405_glyph_words WHERE sura = 2 AND ayah = $1 ORDER BY word, glyph_position)"
}
check "builds words" words "$scratch/quran-com.json" "$scratch/words.db"
check "maps words past a pause-mark glyph" equals "$(glyphs_of 2)" "1>1 2>2 3>4 4>5"
check "maps a word past a leading rub el hizb glyph" equals "$(glyphs_of 3)" "1>2 2>3"
check "maps two words drawn as one glyph to that glyph" equals "$(glyphs_of 4)" "1>1 2>2 3>2"
check "maps a word written in two parts to both glyphs" equals "$(glyphs_of 5)" "1>1 2>2 2>3"
check "leaves an ayah whose glyph count differs unmapped" equals "$(glyphs_of 6)" ""
check "maps words past a sajdah sign and an attached pause mark" equals "$(glyphs_of 8)" "1>1 2>3"
check "writes a row for every word, with each language" equals \
    "$(query "$scratch/words.db" "SELECT group_concat(word || '=' || english || '/' || bengali || '/' || transliteration, ' ') FROM word_meanings WHERE sura = 2 AND ayah = 2")" \
    "1=e2.1/b2.1/t1 2=e2.2/b2.2/t2 3=e2.3/b2.3/t3 4=e2.4/b2.4/t4"
check "gives the second of two QUL words in one Quran.com word the first's meaning" equals \
    "$(query "$scratch/words.db" "SELECT group_concat(word || '=' || english || '/' || transliteration, ' ') FROM word_meanings WHERE sura = 2 AND ayah = 4")" \
    "1=e4.1/t1 2=e4.2/baʿda 3=e4.2/mā"
check "regroups bundled tokens that hold two words" equals \
    "$(query "$scratch/words.db" "SELECT group_concat(token || ':' || first_word || '-' || last_word, ' ') FROM uthmani_tokens WHERE ayah = 7")" "1:1-2 2:3-3"
check "regroups bundled tokens that split one word" equals \
    "$(query "$scratch/words.db" "SELECT group_concat(token || ':' || first_word || '-' || last_word, ' ') FROM uthmani_tokens WHERE ayah = 5")" "1:1-1 2:2-2 3:2-2"
check "doesn't regroup ayahs whose tokens are the words" equals \
    "$(query "$scratch/words.db" "SELECT count(*) FROM uthmani_tokens WHERE ayah IN (2, 3, 4, 6, 8)")" "0"
cp "$scratch/arabic.db" "$scratch/arabic-good.db"
sqlite3 "$scratch/arabic.db" "UPDATE arabic_text SET text = 'كَلِمَةٌ أُخۡرَىٰ' WHERE ayah = 6"
check "rejects bundled text whose letters don't match the words" fails words "$scratch/quran-com.json" "$scratch/bad.db"
cp "$scratch/arabic-good.db" "$scratch/arabic.db"
python3 -I - "$scratch/quran-com.json" "$scratch/quran-com-short.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["ayahs"] = data["ayahs"][1:]
json.dump(data, open(sys.argv[2], "w"), ensure_ascii=False)
PY
check "rejects Quran.com words that miss an ayah" fails words "$scratch/quran-com-short.json" "$scratch/bad.db"
sqlite3 "$scratch/english.db" "UPDATE word_translation SET text = 'not a marker' WHERE ayah_number = 2 AND word_number = '5'"
check "rejects an ayah without an ayah-number word" fails words "$scratch/quran-com.json" "$scratch/bad.db"

# MARK: - bundled databases

check "the bundled timings cover every ayah" equals \
    "$(query "$RESOURCES/qul_afasy.db" "SELECT count(*) FROM timings WHERE ayah != 999")" "6236"
check "the bundled timings end every sura" equals \
    "$(query "$RESOURCES/qul_afasy.db" "SELECT count(*) FROM timings WHERE ayah = 999")" "114"
check "bundled ayah starts never go back in time" equals \
    "$(query "$RESOURCES/qul_afasy.db" "SELECT count(*) FROM timings a JOIN timings b ON a.sura = b.sura AND b.ayah = a.ayah + 1 WHERE b.time < a.time AND b.ayah != 999")" "0"
check "bundled word segments stay inside their ayah" equals \
    "$(query "$RESOURCES/qul_afasy.db" "SELECT count(*) FROM word_timings w JOIN timings a ON a.sura = w.sura AND a.ayah = w.ayah
        LEFT JOIN timings n ON n.sura = w.sura AND n.ayah = (SELECT min(ayah) FROM timings x WHERE x.sura = w.sura AND x.ayah > w.ayah)
        WHERE w.start < a.time - 300 OR (n.time IS NOT NULL AND w.start > n.time + 300)")" "0"
check "every bundled word has English and Bengali meanings and a transliteration" equals \
    "$(query "$RESOURCES/word_by_word.db" "SELECT count(*) || '/' || count(english) || '/' || count(bengali) || '/' || count(transliteration) FROM word_meanings")" \
    "77432/77432/77432/77432"
check "every bundled ayah has a page-image glyph mapping" equals \
    "$(query "$RESOURCES/word_by_word.db" "SELECT count(*) FROM (SELECT DISTINCT sura, ayah FROM hafs_1405_glyph_words)")" "6236"
check "every bundled word has a glyph" equals \
    "$(query "$RESOURCES/word_by_word.db" "SELECT count(*) FROM (SELECT DISTINCT sura, ayah, word FROM hafs_1405_glyph_words)")" "77432"
check "the bundled text is regrouped in exactly the six ayahs that split words differently" equals \
    "$(query "$RESOURCES/word_by_word.db" "SELECT group_concat(k, ' ') FROM (SELECT DISTINCT sura || ':' || ayah k FROM uthmani_tokens ORDER BY sura, ayah)")" \
    "15:7 27:20 36:22 37:130 37:164 41:47"
for name in qul_afasy word_by_word; do
    for table in $(query "$TEST_DATA/$name.db" "SELECT name FROM sqlite_master WHERE type = 'table' AND name != 'properties'"); do
        check "the test $name.db $table rows are the bundled ones" equals \
            "$(query "$TEST_DATA/$name.db" "ATTACH '$RESOURCES/$name.db' AS bundled; SELECT count(*) FROM (SELECT * FROM main.$table EXCEPT SELECT * FROM bundled.$table)")" "0"
    done
done

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
