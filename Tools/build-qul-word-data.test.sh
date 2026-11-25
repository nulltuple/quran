#!/bin/bash
#
# Tests Tools/build-qul-word-data.py on small QUL-shaped fixtures, and checks the databases it
# built for the Example app. Run: bash Tools/build-qul-word-data.test.sh (or make test-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/Tools/build-qul-word-data.py"
RESOURCES="$ROOT/Example/QuranEngineApp/Resources"
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

# MARK: - timings

sqlite3 "$scratch/recitation.db" <<'SQL'
CREATE TABLE segments (surah_number INTEGER, ayah_number INTEGER, duration_sec INTEGER, timestamp_from INTEGER, timestamp_to INTEGER, segments TEXT);
INSERT INTO segments VALUES (1, 1, 1, 0, 1000, '[[1,0,400],[2,450,1000]]');
INSERT INTO segments VALUES (1, 2, 1, 1200, 2500, '[[1,1200,1500],[2,1550,1800],[1,1850,2100],[2,2150,2500]]');
INSERT INTO segments VALUES (2, 1, 1, 0, 900, '[[1,0,500],[2,900,600]]');
SQL
check "builds timings" python3 -I "$TOOL" timings "$scratch/recitation.db" "$scratch/timings.db"
check "writes ayah starts and sura ends" equals \
    "$(query "$scratch/timings.db" "SELECT group_concat(sura || ':' || ayah || '=' || time, ' ') FROM (SELECT * FROM timings ORDER BY sura, ayah)")" \
    "1:1=0 1:2=1200 1:999=2500 2:1=0 2:999=900"
check "keeps repeated words in recitation order" equals \
    "$(query "$scratch/timings.db" "SELECT group_concat(word || '@' || start, ' ') FROM (SELECT * FROM word_timings WHERE sura = 1 AND ayah = 2 ORDER BY seq)")" \
    "1@1200 2@1550 1@1850 2@2150"
check "drops segments that end before they start" equals \
    "$(query "$scratch/timings.db" "SELECT count(*) FROM word_timings WHERE sura = 2")" "1"
check "writes the timing database version" equals \
    "$(query "$scratch/timings.db" "SELECT value FROM properties WHERE property = 'version'")" "1"
sqlite3 "$scratch/empty.db" "CREATE TABLE segments (surah_number INTEGER, ayah_number INTEGER, duration_sec INTEGER, timestamp_from INTEGER, timestamp_to INTEGER, segments TEXT);"
check "rejects a recitation without segments" fails python3 -I "$TOOL" timings "$scratch/empty.db" "$scratch/empty-out.db"

# MARK: - words

for language in english bengali; do
    sqlite3 "$scratch/$language.db" "CREATE TABLE word_translation (surah_number INTEGER, ayah_number INTEGER, word_number TEXT, text TEXT);"
done
sqlite3 "$scratch/english.db" <<'SQL'
INSERT INTO word_translation VALUES (2, 2, '1', 'That'), (2, 2, '2', 'the book'), (2, 2, '3', 'no'), (2, 2, '4', '(2)');
INSERT INTO word_translation VALUES (2, 3, '1', 'Those who'), (2, 3, '3', 'in the unseen'), (2, 3, '4', '(3)');
SQL
sqlite3 "$scratch/bengali.db" <<'SQL'
INSERT INTO word_translation VALUES (2, 2, '1', 'সেই'), (2, 2, '2', 'গ্রন্থ'), (2, 2, '4', '(২)');
INSERT INTO word_translation VALUES (2, 3, '1', 'যারা'), (2, 3, '3', 'অদৃশ্যে'), (2, 3, '4', '(৩)');
SQL
sqlite3 "$scratch/arabic.db" <<'SQL'
CREATE TABLE arabic_text (sura integer, ayah integer, text text, primary key(sura, ayah));
INSERT INTO arabic_text VALUES (2, 2, 'ذَٰلِكَ ٱلۡكِتَٰبُ لَا'), (2, 3, 'ٱلَّذِينَ يُؤۡمِنُونَ بِٱلۡغَيۡبِ');
SQL
# 2:2: word, word, a 9-pixel pause mark, word, ayah marker. 2:3: two glyphs short of its three words.
sqlite3 "$scratch/ayahinfo.db" <<'SQL'
CREATE TABLE glyphs(glyph_id int, page_number int, line_number int, sura_number int, ayah_number int, position int, min_x int, max_x int, min_y int, max_y int);
INSERT INTO glyphs VALUES (1, 2, 1, 2, 2, 1, 900, 1000, 0, 10), (2, 2, 1, 2, 2, 2, 700, 890, 0, 10),
    (3, 2, 1, 2, 2, 3, 690, 699, 0, 10), (4, 2, 1, 2, 2, 4, 600, 680, 0, 10), (5, 2, 1, 2, 2, 5, 500, 590, 0, 10);
INSERT INTO glyphs VALUES (6, 2, 2, 2, 3, 1, 900, 1000, 0, 10), (7, 2, 2, 2, 3, 2, 500, 590, 0, 10);
SQL
check "builds words" python3 -I "$TOOL" words "$scratch/english.db" "$scratch/bengali.db" "$scratch/arabic.db" "$scratch/ayahinfo.db" "$scratch/words.db"
check "drops the ayah-number pseudo-word" equals \
    "$(query "$scratch/words.db" "SELECT count(*) FROM word_meanings WHERE sura = 2 AND ayah = 2")" "3"
check "keeps a word missing in one language" equals \
    "$(query "$scratch/words.db" "SELECT english || '|' || ifnull(bengali, 'NULL') FROM word_meanings WHERE sura = 2 AND ayah = 2 AND word = 3")" "no|NULL"
check "skips a word missing in every language" equals \
    "$(query "$scratch/words.db" "SELECT group_concat(word) FROM word_meanings WHERE sura = 2 AND ayah = 3")" "1,3"
check "maps words past a narrow pause-mark glyph" equals \
    "$(query "$scratch/words.db" "SELECT group_concat(word || '>' || glyph_position, ' ') FROM (SELECT * FROM hafs_1405_glyph_words WHERE sura = 2 AND ayah = 2 ORDER BY word)")" \
    "1>1 2>2 3>4"
check "leaves an unmatched ayah unmapped" equals \
    "$(query "$scratch/words.db" "SELECT count(*) FROM hafs_1405_glyph_words WHERE sura = 2 AND ayah = 3")" "0"
sqlite3 "$scratch/english.db" "UPDATE word_translation SET text = 'not a marker' WHERE ayah_number = 2 AND word_number = '4'"
check "rejects an ayah without an ayah-number word" fails python3 -I "$TOOL" words "$scratch/english.db" "$scratch/bengali.db" "$scratch/arabic.db" "$scratch/ayahinfo.db" "$scratch/bad.db"

# MARK: - bundled databases

check "the bundled timings cover every ayah" equals \
    "$(query "$RESOURCES/qul_afasy.db" "SELECT count(*) FROM timings WHERE ayah != 999")" "6236"
check "the bundled timings end every sura" equals \
    "$(query "$RESOURCES/qul_afasy.db" "SELECT count(*) FROM timings WHERE ayah = 999")" "114"
check "every bundled ayah has recited words" equals \
    "$(query "$RESOURCES/qul_afasy.db" "SELECT count(*) FROM (SELECT DISTINCT sura, ayah FROM word_timings)")" "6236"
check "every bundled ayah has word meanings" equals \
    "$(query "$RESOURCES/word_by_word.db" "SELECT count(*) FROM (SELECT DISTINCT sura, ayah FROM word_meanings)")" "6236"
# words.db (upstream's word pointer data) numbers Madani 1405 glyphs and leaves marks untranslated,
# so its translated positions are an independent record of where the words are.
check "the glyph mapping agrees with upstream's words.db" equals \
    "$(query "$RESOURCES/word_by_word.db" "ATTACH '$RESOURCES/words.db' AS upstream;
        WITH up AS (SELECT sura, ayah, group_concat(word_position) p FROM (SELECT * FROM upstream.words
                WHERE translation != '' ORDER BY sura, ayah, word_position) GROUP BY sura, ayah),
            mine AS (SELECT sura, ayah, group_concat(glyph_position) p FROM (SELECT * FROM hafs_1405_glyph_words
                ORDER BY sura, ayah, word) GROUP BY sura, ayah)
        SELECT count(*) || '/' || sum(up.p = mine.p) FROM up JOIN mine USING (sura, ayah)")" "857/857"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
