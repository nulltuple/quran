#!/usr/bin/env python3
"""Build Quran's read-only H5 similarity index from the two QUL exports.

Inputs are the Similar Ayah SQLite ZIP (resource 74) and Mutashabihat JSON ZIP
(resource 73, served with a .bz2 filename). Keep the original downloads intact
for provenance. The canonical Uthmani database contributes only verse keys and
normalized n-grams. No Quran display text is copied into the output.

  python3 -I Tools/build-similar-verses.py <matching-ayah.db.zip> <mutashabihat.zip> <output.db>

Each unordered pair is stored once. Source bits are 1 for Similar Ayah and 2
for Mutashabihat. Zero marks candidates found only by the canonical 4-gram index.
The app can use pairs with a QUL source and at least one canonical bigram.
"""

import argparse
from collections import defaultdict
from contextlib import closing
from hashlib import sha256
from itertools import combinations
import json
from pathlib import Path
import re
import sqlite3
import tempfile
import zipfile

QURAN_DB = Path(__file__).resolve().parents[1] / "Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db"
NON_LETTER = re.compile(r"[^ء-غف-ي\s]")
ALEF_FORMS = str.maketrans("أإآٱ", "اااا")


def read_only(path):
    return closing(sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True))


def read_canonical(path):
    with read_only(path) as db:
        return {
            (sura, ayah): NON_LETTER.sub("", text.translate(ALEF_FORMS)).split()
            for sura, ayah, text in db.execute("SELECT sura, ayah, text FROM arabic_text WHERE ayah > 0")
        }


def read_similar(path, scratch, verse_key):
    database = scratch / "matching-ayah.db"
    with zipfile.ZipFile(path) as archive:
        database.write_bytes(archive.read(database.name))
    scores = {}
    with read_only(database) as db:
        for a, b, score in db.execute("SELECT verse_key, matched_ayah_key, score FROM similar_ayahs"):
            pair = tuple(sorted((verse_key(a), verse_key(b))))
            if pair[0] == pair[1]:
                raise ValueError(f"Similar Ayah links {a} to itself")
            scores[pair] = max(scores.get(pair, 0), score)
    return scores


def read_mutashabihat(path, verse_key):
    with zipfile.ZipFile(path) as archive:
        phrases = json.loads(archive.read("phrases.json"))
        verse_phrases = json.loads(archive.read("phrase_verses.json"))
    listed = {(verse_key(key), str(phrase)) for key, ids in verse_phrases.items() for phrase in ids}
    observed = set()
    pairs = set()
    for phrase, entry in phrases.items():
        verses = sorted(verse_key(key) for key in entry["ayah"])
        observed.update((verse, phrase) for verse in verses)
        pairs.update(combinations(verses, 2))
    if listed != observed:
        raise ValueError(
            f"phrase_verses.json disagrees with phrases.json ({len(listed ^ observed)} links)"
        )
    return pairs


def index_ngrams(canonical):
    verse_grams = {}
    four_gram_index = defaultdict(set)
    for verse, words in canonical.items():
        grams = {
            tuple(words[start : start + length])
            for length in (2, 3, 4)
            for start in range(len(words) - length + 1)
        }
        verse_grams[verse] = grams
        for gram in grams:
            if len(gram) == 4:
                four_gram_index[gram].add(verse)
    candidates = {
        pair
        for verses in four_gram_index.values()
        for pair in combinations(sorted(verses), 2)
    }
    return verse_grams, candidates


def build(args, scratch):
    canonical = read_canonical(args.quran_db)

    def verse_key(key):
        fields = key.split(":")
        if len(fields) == 2 and all(field.isdecimal() for field in fields):
            verse = tuple(map(int, fields))
            if verse in canonical:
                return verse
        raise ValueError(f"Unknown canonical verse {key!r}")

    scores = read_similar(args.similar_zip, scratch, verse_key)
    phrases = read_mutashabihat(args.mutashabihat_zip, verse_key)
    verse_grams, candidates = index_ngrams(canonical)
    sourced = scores.keys() | phrases
    rows = []
    for left, right in sorted(sourced | candidates):
        pair = (left, right)
        flags = int(pair in scores) + 2 * int(pair in phrases)
        shared = max(map(len, verse_grams[left] & verse_grams[right]), default=0)
        rows.append((*left, *right, flags, shared, scores.get(pair, 0)))

    properties = {
        "schema_version": "1",
        "similar_ayah_source": "https://qul.tarteel.ai/resources/similar-ayah/74",
        "mutashabihat_source": "https://qul.tarteel.ai/resources/mutashabihat/73",
        "similar_ayah_sha256": sha256(args.similar_zip.read_bytes()).hexdigest(),
        "mutashabihat_sha256": sha256(args.mutashabihat_zip.read_bytes()).hexdigest(),
        "canonical_sha256": sha256(args.quran_db.read_bytes()).hexdigest(),
    }
    output = scratch / "output.db"
    with closing(sqlite3.connect(output)) as db, db:
        db.executescript("""
            CREATE TABLE properties (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
            CREATE TABLE verse_pairs (
                sura INTEGER NOT NULL,
                ayah INTEGER NOT NULL,
                match_sura INTEGER NOT NULL,
                match_ayah INTEGER NOT NULL,
                sources INTEGER NOT NULL CHECK (sources BETWEEN 0 AND 3),
                shared_ngram INTEGER NOT NULL CHECK (shared_ngram IN (0, 2, 3, 4)),
                source_score INTEGER NOT NULL,
                PRIMARY KEY (sura, ayah, match_sura, match_ayah),
                CHECK ((sura, ayah) < (match_sura, match_ayah))
            ) WITHOUT ROWID;
            CREATE INDEX verse_pairs_reverse ON verse_pairs (match_sura, match_ayah);
        """)
        db.executemany("INSERT INTO properties VALUES (?, ?)", sorted(properties.items()))
        db.executemany("INSERT INTO verse_pairs VALUES (?, ?, ?, ?, ?, ?, ?)", rows)
    output.replace(args.output)
    supported = sum(sources != 0 and shared >= 2 for *_, sources, shared, _ in rows)
    print(f"{len(canonical)} canonical verses; {len(scores)} Similar Ayah pairs; {len(phrases)} Mutashabihat pairs")
    print(f"{supported} corroborated pairs; {len(sourced) - supported} QUL-only; {len(candidates - sourced)} index-only")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("similar_zip", type=Path)
    parser.add_argument("mutashabihat_zip", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--quran-db", type=Path, default=QURAN_DB)
    args = parser.parse_args()
    try:
        with tempfile.TemporaryDirectory(dir=args.output.parent) as scratch:
            build(args, Path(scratch))
    except (OSError, ValueError, TypeError, KeyError, sqlite3.Error, zipfile.BadZipFile) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
