#!/usr/bin/env python3
"""Builds the Quran app's bundled word-study database (roadmap v2 C2), quran_morphology.db.

App: Quran (the reader). Input, downloaded once (not in git; the C2 trail entry records the URL):

- quran-morphology.txt, Quranic Arabic Corpus morphology v0.4 as github.com/mustafa0x/quran-morphology
  publishes it at commit 8f38b39016824284f9ed16ae15069ff9102c4acf, SHA-256
  742bfac59941b2cb09736d5b7aae694af50792261fb8450cbf6afafcc340645f. One line per segment:
  `sura:ayah:word:segment<TAB>text<TAB>N|V|P<TAB>features`.
- the reader's word data, Example/QuranEngineApp/Resources/word_by_word.db, whose word numbers
  (canonical word ids, M1) the output uses.

QAC numbers words like word_by_word.db in 6,233 of 6,236 ayahs. In 2:181, 8:6 and 13:37 QAC keeps
`بَعْدَ مَا` as one word of two segments where the canonical words (QUL's recitation and
Quran.com) are two words; the tool splits that QAC word, one segment per canonical word, and
fails on any other difference. Every QAC feature must decode into a known column, or the tool
fails: it never guesses grammar.

Output tables:

- properties: source, commit, sha256, schema_version and the coverage counts
- roots(id, root, occurrences): root letters as QAC writes them (حمد); occurrences counts
  segments, as the QAC website does (ح م د: 68)
- lemmas(id, lemma, root_id, occurrences): a lemma is its text and root (QAC spells seven lemmas
  the same under two roots); occurrences counts segments
- grammar(id, part, tag, derivation, role, person, gender, number, verb_form, aspect, voice, mood,
  grammatical_case, indefinite, family): each distinct decoded feature set once (about 1,070)
- segments(sura, ayah, word, segment, text, grammar_id, lemma_id, root_id): every segment of every
  canonical word; indexed by lemma and root for occurrence lists

Usage:
  python3 -I Tools/build-quran-morphology.py <quran-morphology.txt> <output.db> [--words-db <word_by_word.db>]
"""

import argparse
import collections
import os
import re
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORDS_DB = os.path.join(ROOT, "Example/QuranEngineApp/Resources/word_by_word.db")
SOURCE = "Quranic Arabic Corpus morphology v0.4 (github.com/mustafa0x/quran-morphology)"
COMMIT = "8f38b39016824284f9ed16ae15069ff9102c4acf"
SHA256 = "742bfac59941b2cb09736d5b7aae694af50792261fb8450cbf6afafcc340645f"
SCHEMA_VERSION = "1"

# Word classes (one at most per noun segment) and derivations (one at most), as QAC tags them.
NOUN_CLASSES = ("PN", "PRON", "DEM", "REL", "INTG", "COND", "NV", "T", "LOC", "ADJ", "ADDR")
NOUN_DERIVATIONS = ("ACT_PCPL", "PASS_PCPL", "VN")
# Particle kinds: exactly one per particle segment.
PARTICLE_TAGS = (
    "P", "CONJ", "DET", "REM", "NEG", "ACC", "EMPH", "ADDR", "SUB", "RES", "DIST", "ATT", "CERT",
    "VOC", "RSLT", "PRO", "PRP", "CIRC", "SUP", "PREV", "FUT", "RET", "EXP", "INTG", "CAUS", "IMPV",
    "EXL", "AMD", "ANS", "INC", "INT", "EXH", "SUR", "AVR", "INL", "EQ", "COM", "COND",
)
ASPECTS = ("PERF", "IMPF", "IMPV")
CASES = ("NOM", "ACC", "GEN")
MOODS = ("IND", "SUBJ", "JUS")
FAMILIES = {"كَان": "kana", "إِنّ": "inna", "كَاد": "kada"}
PGN = re.compile("^([123]?)([MF]?)([SDP]?)$")
MARKS = re.compile("[ـً-ٰٟۖ-ۭ]")
GRAMMAR_COLUMNS = (
    "part", "tag", "derivation", "role", "person", "gender", "number", "verb_form", "aspect", "voice", "mood",
    "grammatical_case", "indefinite", "family",
)


class MorphologyError(Exception):
    pass


def parse(path):
    """[(sura, ayah, word, segment, text, part, features)], features as [(key, value)] in order."""
    segments = []
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, start=1):
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 4 or parts[2] not in ("N", "V", "P"):
                raise MorphologyError(f"line {number}: expected location, text, N/V/P and features")
            location = parts[0].split(":")
            if len(location) != 4 or not all(x.isdigit() for x in location):
                raise MorphologyError(f"line {number}: location must be sura:ayah:word:segment")
            features = [f.partition(":")[::2] for f in parts[3].split("|") if f]
            segments.append(tuple(int(x) for x in location) + (parts[1], parts[2], features))
    return segments


def decode(part, features, where):
    """The segment's columns after the location and text, minus lemma_id and root_id, plus its
    lemma and root texts: (tag, derivation, role, person, gender, number, verb_form, aspect, voice,
    mood, case, indefinite, family, lemma, root)."""
    tag = derivation = person = gender = number = verb_form = aspect = mood = case = family = None
    lemma = root = None
    role, voice, indefinite = "stem", None, 0
    if part == "V":
        tag, voice = "V", "active"
    for key, value in features:
        if key == "LEM":
            lemma = value
        elif key == "ROOT":
            root = value
        elif key == "FAM":
            if value not in FAMILIES:
                raise MorphologyError(f"{where}: unknown family {value}")
            family = FAMILIES[value]
        elif key == "MOOD" and part == "V" and value in MOODS:
            mood = value
        elif key == "VF" and value.isdigit():
            verb_form = int(value)
        elif value:
            raise MorphologyError(f"{where}: unknown feature {key}:{value}")
        elif key == "PREF":
            role = "prefix"
        elif key == "SUFF":
            role = "suffix"
        elif part == "N" and key in NOUN_CLASSES:
            if tag:
                raise MorphologyError(f"{where}: two word classes {tag} and {key}")
            tag = key
        elif part == "N" and key in NOUN_DERIVATIONS:
            if derivation:
                raise MorphologyError(f"{where}: two derivations {derivation} and {key}")
            derivation = key
        elif part == "P" and key in PARTICLE_TAGS:
            if tag:
                raise MorphologyError(f"{where}: two particle kinds {tag} and {key}")
            tag = key
        elif part == "N" and key in CASES:
            case = key
        elif part == "N" and key == "INDEF":
            indefinite = 1
        elif part in ("V", "N") and key in ASPECTS:
            # Verbs, and the verb-like nouns (NV) QAC marks with the aspect they act as.
            aspect = key
        elif part == "V" and key == "PASS":
            voice = "passive"
        elif PGN.match(key) and not (part == "P" and key == "P"):
            person, gender, number = (g or None for g in PGN.match(key).groups())
            person = int(person) if person else None
        else:
            raise MorphologyError(f"{where}: unknown tag {key} for part {part}")
    if part == "N" and tag is None:
        tag = "N"
    if part == "P" and tag is None:
        raise MorphologyError(f"{where}: particle without a kind")
    return (tag, derivation, role, person, gender, number, verb_form, aspect, voice, mood, case, indefinite, family,
            lemma, root)


def canonical_word_counts(words_db):
    db = sqlite3.connect(f"file:{words_db}?mode=ro", uri=True)
    counts = {(s, a): n for s, a, n in db.execute("SELECT sura, ayah, MAX(word) FROM word_meanings GROUP BY sura, ayah")}
    db.close()
    return counts


def normalized(text):
    return MARKS.sub("", text)


def align(segments, canonical):
    """Segments renumbered to canonical words: [(sura, ayah, word, segment, text, part, features)], and
    the split words as [(sura, ayah, qac word)]. Fails on any ayah it cannot map exactly."""
    by_ayah = collections.defaultdict(lambda: collections.defaultdict(list))
    for segment in segments:
        by_ayah[segment[:2]][segment[2]].append(segment)
    errors = sorted(f"{s}:{a}: missing from QAC" for s, a in set(canonical) - set(by_ayah))
    errors += sorted(f"{s}:{a}: not in word_by_word.db" for s, a in set(by_ayah) - set(canonical))
    aligned, splits = [], []
    for (sura, ayah), words in sorted(by_ayah.items()):
        expected = canonical.get((sura, ayah))
        if expected is None:
            continue
        numbers = sorted(words)
        if numbers != list(range(1, len(numbers) + 1)):
            errors.append(f"{sura}:{ayah}: QAC word numbers are not 1...{len(numbers)}")
            continue
        split = None
        if len(numbers) == expected - 1:
            candidates = [w for w in numbers if [normalized(s[4]) for s in words[w]] == ["بعد", "ما"]]
            if len(candidates) != 1:
                errors.append(f"{sura}:{ayah}: QAC has one word fewer and {len(candidates)} words بعد ما to split")
                continue
            split = candidates[0]
            splits.append((sura, ayah, split))
        elif len(numbers) != expected:
            errors.append(f"{sura}:{ayah}: QAC has {len(numbers)} words, word_by_word.db {expected}")
            continue
        canonical_word = 0
        for qac_word in numbers:
            parts = [[s] for s in words[qac_word]] if qac_word == split else [words[qac_word]]
            for group in parts:
                canonical_word += 1
                for index, s in enumerate(group, start=1):
                    aligned.append((sura, ayah, canonical_word, index) + s[4:])
    if errors:
        raise MorphologyError("\n".join(errors))
    return aligned, splits


def build(segments, canonical, output):
    """Writes output; returns the coverage counts."""
    aligned, splits = align(segments, canonical)
    decoded = [s[:5] + (s[5],) + decode(s[5], s[6], f"{s[0]}:{s[1]}:{s[2]}:{s[3]}") for s in aligned]
    root_counts = collections.Counter(d[-1] for d in decoded if d[-1])
    lemma_counts = collections.Counter((d[-2], d[-1] or "") for d in decoded if d[-2])
    roots = {root: i for i, root in enumerate(sorted(root_counts), start=1)}
    lemmas = {key: i for i, key in enumerate(sorted(lemma_counts), start=1)}
    if os.path.exists(output):
        os.remove(output)
    db = sqlite3.connect(output)
    db.executescript(f"""
        CREATE TABLE properties(property TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE roots(id INTEGER PRIMARY KEY, root TEXT NOT NULL UNIQUE, occurrences INTEGER NOT NULL);
        CREATE TABLE lemmas(id INTEGER PRIMARY KEY, lemma TEXT NOT NULL, root_id INTEGER REFERENCES roots(id),
            occurrences INTEGER NOT NULL);
        CREATE TABLE grammar(id INTEGER PRIMARY KEY, part TEXT NOT NULL, tag TEXT NOT NULL, derivation TEXT,
            role TEXT NOT NULL, person INTEGER, gender TEXT, number TEXT, verb_form INTEGER, aspect TEXT, voice TEXT,
            mood TEXT, grammatical_case TEXT, indefinite INTEGER NOT NULL, family TEXT);
        CREATE TABLE segments(
            sura INTEGER NOT NULL, ayah INTEGER NOT NULL, word INTEGER NOT NULL, segment INTEGER NOT NULL,
            text TEXT NOT NULL, grammar_id INTEGER NOT NULL REFERENCES grammar(id),
            lemma_id INTEGER REFERENCES lemmas(id), root_id INTEGER REFERENCES roots(id),
            PRIMARY KEY(sura, ayah, word, segment)) WITHOUT ROWID;
    """)
    db.executemany("INSERT INTO roots VALUES (?, ?, ?)", [(i, r, root_counts[r]) for r, i in roots.items()])
    db.executemany("INSERT INTO lemmas VALUES (?, ?, ?, ?)",
                   [(i, lemma, roots.get(root), lemma_counts[(lemma, root)]) for (lemma, root), i in lemmas.items()])
    grammar, rows = {}, []
    for d in decoded:
        lemma, root = d[-2], d[-1]
        lemma_id = lemmas[(lemma, root or "")] if lemma else None
        features = d[5:-2]
        grammar_id = grammar.setdefault(features, len(grammar) + 1)
        rows.append(d[:5] + (grammar_id, lemma_id, roots.get(root) if root else None))
    db.executemany(f"INSERT INTO grammar VALUES ({', '.join('?' * (len(GRAMMAR_COLUMNS) + 1))})",
                   [(i,) + features for features, i in grammar.items()])
    db.executemany("INSERT INTO segments VALUES (?, ?, ?, ?, ?, ?, ?, ?)", rows)
    db.executescript("""
        CREATE INDEX segments_lemma ON segments(lemma_id) WHERE lemma_id IS NOT NULL;
        CREATE INDEX segments_root ON segments(root_id) WHERE root_id IS NOT NULL;
    """)
    coverage = {
        "ayahs": len(canonical),
        "words": len({d[:3] for d in decoded}),
        "segments": len(decoded),
        "roots": len(roots),
        "lemmas": len(lemmas),
        "grammar": len(grammar),
        "split_words": len(splits),
    }
    properties = {"source": SOURCE, "commit": COMMIT, "sha256": SHA256, "schema_version": SCHEMA_VERSION}
    properties.update({k: str(v) for k, v in coverage.items()})
    db.executemany("INSERT INTO properties VALUES (?, ?)", sorted(properties.items()))
    db.commit()
    db.execute("VACUUM")
    db.close()
    expected_words = sum(canonical.values())
    if coverage["words"] != expected_words:
        raise MorphologyError(f"mapped {coverage['words']} words, word_by_word.db has {expected_words}")
    return coverage, splits


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("qac", help="quran-morphology.txt")
    parser.add_argument("output", help="the database to write")
    parser.add_argument("--words-db", default=WORDS_DB)
    args = parser.parse_args(argv)
    try:
        coverage, splits = build(parse(args.qac), canonical_word_counts(args.words_db), args.output)
    except MorphologyError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(", ".join(f"{k} {v}" for k, v in coverage.items()))
    for sura, ayah, word in splits:
        print(f"split {sura}:{ayah} QAC word {word} (بعد ما) into canonical words {word} and {word + 1}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
