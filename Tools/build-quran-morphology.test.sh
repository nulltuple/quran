#!/bin/bash
#
# Tests Tools/build-quran-morphology.py (Quran app, roadmap C2) on a small QAC-shaped fixture, then
# checks the committed Example/QuranEngineApp/Resources/quran_morphology.db against known QAC facts.
# Run: bash Tools/build-quran-morphology.test.sh (or make test-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/Tools/build-quran-morphology.py"
BUNDLED="$ROOT/Example/QuranEngineApp/Resources/quran_morphology.db"
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
contains() { grep -qF -- "$2" "$1" || { echo "'$2' not in:"; cat "$1"; return 1; }; }
q() { sqlite3 "$1" "$2"; }

# Canonical words: 1:2 has 2 words, 2:181 has 4 (QAC has 3: it keeps `بعد ما` as one word), 2:3 has 2.
words="$scratch/words.db"
sqlite3 "$words" "CREATE TABLE word_meanings(sura INTEGER, ayah INTEGER, word INTEGER, english TEXT, bengali TEXT, transliteration TEXT);
INSERT INTO word_meanings(sura, ayah, word) VALUES (1,2,1),(1,2,2),(2,181,1),(2,181,2),(2,181,3),(2,181,4),(2,3,1),(2,3,2);"

printf '%s\n' \
    $'1:2:1:1\tٱلْ\tP\tDET|PREF|LEM:ال' \
    $'1:2:1:2\tحَمْدُ\tN\tROOT:حمد|LEM:حَمْد|M|NOM' \
    $'1:2:2:1\tلِ\tP\tP|PREF|LEM:ل' \
    $'1:2:2:2\tلَّهِ\tN\tPN|ROOT:أله|LEM:اللَّه|GEN' \
    $'2:181:1:1\tفَ\tP\tREM|PREF|LEM:ف' \
    $'2:181:1:2\tمَنۢ\tN\tCOND|LEM:مَن' \
    $'2:181:2:1\tبَعْدَ\tN\tT|ROOT:بعد|LEM:بَعْد|ACC' \
    $'2:181:2:2\tمَا\tP\tSUP|LEM:ما' \
    $'2:181:3:1\tسَمِعَ\tV\tPERF|VF:1|ROOT:سمع|LEM:سَمِعَ|3MS' \
    $'2:3:1:1\tيُؤْمِنُ\tV\tIMPF|VF:4|PASS|ROOT:أمن|LEM:آمَنَ|3MP|MOOD:JUS' \
    $'2:3:1:2\tونَ\tN\tPRON|SUFF|3MP' \
    $'2:3:2:1\tيَ\tP\tVOC|PREF|LEM:ي' \
    $'2:3:2:2\tكَ\tP\tADDR|SUFF|M' \
    $'2:3:2:3\tحَمِيدٌ\tN\tROOT:حمد|LEM:حَمِيد|MS|INDEF|NOM|ADJ|ACT_PCPL' \
    > "$scratch/qac.txt"

db="$scratch/out.db"
grammar_of() {
    # grammar_of <sura> <ayah> <word> <segment>: the decoded grammar columns, `|`-separated.
    q "$db" "SELECT g.part, g.tag, ifnull(g.derivation, ''), g.role, ifnull(g.person, ''), ifnull(g.gender, ''),
        ifnull(g.number, ''), ifnull(g.verb_form, ''), ifnull(g.aspect, ''), ifnull(g.voice, ''), ifnull(g.mood, ''),
        ifnull(g.grammatical_case, ''), g.indefinite, ifnull(g.family, '')
        FROM segments s JOIN grammar g ON g.id = s.grammar_id WHERE sura = $1 AND ayah = $2 AND word = $3 AND segment = $4"
}

check "builds from a fixture" python3 -I "$TOOL" "$scratch/qac.txt" "$db" --words-db "$words"
python3 -I "$TOOL" "$scratch/qac.txt" "$db" --words-db "$words" > "$scratch/report" 2>&1 || true
check "reports coverage" contains "$scratch/report" "ayahs 3, words 8, segments 14, roots 5, lemmas 12, grammar 14, split_words 1"
check "reports the split word" contains "$scratch/report" "split 2:181 QAC word 2 (بعد ما) into canonical words 2 and 3"
check "splits بعد ما into two canonical words" equals "$(q "$db" "SELECT word || ':' || segment || ':' || text FROM segments WHERE sura = 2 AND ayah = 181 ORDER BY word, segment" | tr '\n' ' ')" \
    "1:1:فَ 1:2:مَنۢ 2:1:بَعْدَ 3:1:مَا 4:1:سَمِعَ "
check "renumbers words after the split" equals "$(q "$db" "SELECT max(word) FROM segments WHERE sura = 2 AND ayah = 181")" "4"
check "counts root occurrences by segment" equals "$(q "$db" "SELECT occurrences FROM roots WHERE root = 'حمد'")" "2"
check "keeps lemmas of a root apart" equals "$(q "$db" "SELECT group_concat(lemma, ',') FROM (SELECT l.lemma || '=' || l.occurrences AS lemma FROM lemmas l JOIN roots r ON r.id = l.root_id WHERE r.root = 'حمد' ORDER BY l.id)")" "حَمِيد=1,حَمْد=1"
check "a rootless lemma has no root" equals "$(q "$db" "SELECT ifnull(root_id, 'none') FROM lemmas WHERE lemma = 'ال'")" "none"
check "decodes a definite article prefix" equals "$(grammar_of 1 2 1 1)" "P|DET||prefix|||||||||0|"
check "decodes a nominative noun" equals "$(grammar_of 1 2 1 2)" "N|N||stem||M||||||NOM|0|"
check "decodes a passive jussive form IV verb" equals "$(grammar_of 2 3 1 1)" "V|V||stem|3|M|P|4|IMPF|passive|JUS||0|"
check "decodes an active perfect verb" equals "$(grammar_of 2 181 4 1)" "V|V||stem|3|M|S|1|PERF|active|||0|"
check "decodes a pronoun suffix" equals "$(grammar_of 2 3 1 2)" "N|PRON||suffix|3|M|P||||||0|"
check "decodes an indefinite adjective participle" equals "$(grammar_of 2 3 2 3)" "N|ADJ|ACT_PCPL|stem||M|S|||||NOM|1|"
check "a particle's gender is not its kind" equals "$(grammar_of 2 3 2 2)" "P|ADDR||suffix||M|||||||0|"
check "stores each grammar once" equals "$(q "$db" "SELECT count(*) FROM grammar")" "$(q "$db" "SELECT count(DISTINCT grammar_id) FROM segments")"
check "records the source pin" equals "$(q "$db" "SELECT value FROM properties WHERE property = 'sha256'")" \
    "742bfac59941b2cb09736d5b7aae694af50792261fb8450cbf6afafcc340645f"
check "records the coverage" equals "$(q "$db" "SELECT value FROM properties WHERE property = 'words'")" "8"

sed $'s/\tROOT:حمد|LEM:حَمْد|M|NOM/\tROOT:حمد|LEM:حَمْد|M|NOM|XYZ/' "$scratch/qac.txt" > "$scratch/unknown.txt"
check "rejects an unknown tag" fails python3 -I "$TOOL" "$scratch/unknown.txt" "$scratch/unknown.db" --words-db "$words"
python3 -I "$TOOL" "$scratch/unknown.txt" "$scratch/unknown.db" --words-db "$words" > "$scratch/err" 2>&1 || true
check "names the unknown tag and segment" contains "$scratch/err" "1:2:1:2: unknown tag XYZ for part N"

sed $'s/\tP\tSUP|LEM:ما/\tP\tSUP|PREV|LEM:ما/' "$scratch/qac.txt" > "$scratch/two-kinds.txt"
check "rejects a particle with two kinds" fails python3 -I "$TOOL" "$scratch/two-kinds.txt" "$scratch/two.db" --words-db "$words"

grep -v '^2:3:2:' "$scratch/qac.txt" > "$scratch/short.txt"
check "rejects an ayah with a word missing" fails python3 -I "$TOOL" "$scratch/short.txt" "$scratch/short.db" --words-db "$words"
python3 -I "$TOOL" "$scratch/short.txt" "$scratch/short.db" --words-db "$words" > "$scratch/err" 2>&1 || true
check "names the ayah it cannot map" contains "$scratch/err" "2:3: QAC has one word fewer and 0 words بعد ما to split"

grep -v '^2:3:' "$scratch/qac.txt" > "$scratch/missing.txt"
check "rejects a missing ayah" fails python3 -I "$TOOL" "$scratch/missing.txt" "$scratch/missing.db" --words-db "$words"

# The committed database: every canonical word mapped, and known QAC facts.
check "bundled: maps every canonical word" equals "$(q "$BUNDLED" "SELECT count(*) FROM (SELECT DISTINCT sura, ayah, word FROM segments)")" \
    "$(sqlite3 "$ROOT/Example/QuranEngineApp/Resources/word_by_word.db" "SELECT count(*) FROM word_meanings")"
check "bundled: has every QAC segment" equals "$(q "$BUNDLED" "SELECT count(*) FROM segments")" "130030"
check "bundled: root ح م د occurs 68 times" equals "$(q "$BUNDLED" "SELECT occurrences FROM roots WHERE root = 'حمد'")" "68"
check "bundled: lemma حَمْد occurs 43 times" equals "$(q "$BUNDLED" "SELECT occurrences FROM lemmas WHERE lemma = 'حَمْد'")" "43"
check "bundled: 1:2 word 1 is ال + حَمْدُ" equals "$(q "$BUNDLED" "SELECT group_concat(text, '+') FROM (SELECT text FROM segments WHERE sura = 1 AND ayah = 2 AND word = 1 ORDER BY segment)")" "ٱلْ+حَمْدُ"
check "bundled: 13:37 words 8 and 9 are بَعْدَ and مَا" equals "$(q "$BUNDLED" "SELECT group_concat(text, ' ') FROM (SELECT text FROM segments WHERE sura = 13 AND ayah = 37 AND word IN (8, 9) ORDER BY word)")" "بَعْدَ مَا"
check "bundled: records the pinned source" equals "$(q "$BUNDLED" "SELECT value FROM properties WHERE property = 'commit'")" "8f38b39016824284f9ed16ae15069ff9102c4acf"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
