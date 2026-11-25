#!/usr/bin/env python3
"""Builds the app's word-by-word databases from Quranic Universal Library (QUL) downloads.

QUL (https://qul.tarteel.ai) needs a signed-in account to download, so the inputs are files the
owner downloaded by hand; the outputs are bundled in the Example app. Run with `python3 -I` and pass
every path explicitly, so nothing is read from the current directory.

Usage:
  build-qul-word-data.py timings <qul-recitation.db> <output.db>
  build-qul-word-data.py words <english-wbw.db> <bengali-wbw.db> <quran.ar.uthmani.v2.db> \
      <ayahinfo.db> <output.db>

`timings` writes the gapless timing format `GRDBAyahTimingPersistence` already reads
(`timings(sura, ayah, time)`, ayah 999 marking the end of the sura) plus `word_timings`, the
recited words in recitation order (a reciter may repeat a word, so a word can appear twice).

`words` writes `word_meanings(sura, ayah, word, english, bengali)` keyed by QUL word number
(QUL's trailing ayah-number pseudo-word is dropped) and `hafs_1405_glyph_words`, which maps a QUL
word to its glyph position in the Madani 1405 page images, where pause marks, the rub el hizb
sign and the sajdah sign are glyphs of their own. Ayahs whose glyphs cannot be matched word for
word get no mapping rows, so the app falls back to highlighting the whole ayah there.
"""

import json
import os
import sqlite3
import sys

# Glyphs narrower than this, in 1920-pixel-wide page units, are marks (pause signs), not words.
MARK_MAX_WIDTH = 30
RUB_EL_HIZB = "۞"
SAJDAH = "۩"


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def fresh_database(path):
    if os.path.exists(path):
        os.remove(path)
    return sqlite3.connect(path)


def build_timings(source_path, output_path):
    source = sqlite3.connect(f"file:{source_path}?mode=ro", uri=True)
    rows = source.execute(
        "SELECT surah_number, ayah_number, timestamp_from, timestamp_to, segments"
        " FROM segments ORDER BY surah_number, ayah_number"
    ).fetchall()
    if not rows:
        fail("the recitation database has no segments")

    out = fresh_database(output_path)
    out.executescript(
        """
        CREATE TABLE properties(property TEXT, value TEXT);
        CREATE TABLE timings(sura INTEGER, ayah INTEGER, time INTEGER, PRIMARY KEY(sura, ayah));
        CREATE TABLE word_timings(
            sura INTEGER, ayah INTEGER, seq INTEGER, word INTEGER, start INTEGER, "end" INTEGER,
            PRIMARY KEY(sura, ayah, seq));
        """
    )
    out.execute("INSERT INTO properties VALUES('version', '1')")

    dropped = 0
    last_ayah_end = {}
    for sura, ayah, start, end, segments in rows:
        out.execute("INSERT INTO timings VALUES(?, ?, ?)", (sura, ayah, start))
        last_ayah_end[sura] = end
        seq = 0
        for segment in json.loads(segments or "[]"):
            # QUL has a few segments whose end precedes their start; their timing is unusable.
            if len(segment) < 3 or segment[1] > segment[2]:
                dropped += 1
                continue
            word, word_start, word_end = segment[0], segment[1], segment[2]
            out.execute(
                "INSERT INTO word_timings VALUES(?, ?, ?, ?, ?, ?)",
                (sura, ayah, seq, word, word_start, word_end),
            )
            seq += 1
    for sura, end in last_ayah_end.items():
        out.execute("INSERT INTO timings VALUES(?, 999, ?)", (sura, end))
    out.commit()
    out.execute("VACUUM")
    out.close()
    print(f"timings: {len(rows)} ayahs, {len(last_ayah_end)} suras, {dropped} invalid segments dropped")


def word_translations(path):
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    result = {}
    for sura, ayah, word, text in db.execute(
        "SELECT surah_number, ayah_number, CAST(word_number AS INTEGER), text FROM word_translation"
    ):
        result.setdefault((sura, ayah), {})[word] = text
    return result


def glyph_positions(words, text, glyph_widths):
    """Glyph position of each word, or None when the glyphs can't be matched word for word."""
    body = list(glyph_widths[:-1])  # The last glyph is the ayah-number marker.
    if text.startswith(RUB_EL_HIZB) and body:
        body = body[1:]
        first_position = 2
    else:
        first_position = 1
    positions = [first_position + index for index, width in enumerate(body) if width >= MARK_MAX_WIDTH]
    if SAJDAH in text and len(positions) == words + 1:
        positions = positions[:-1]
    if len(positions) != words:
        return None
    return positions


def build_words(english_path, bengali_path, arabic_path, ayahinfo_path, output_path):
    english = word_translations(english_path)
    bengali = word_translations(bengali_path)
    arabic = sqlite3.connect(f"file:{arabic_path}?mode=ro", uri=True)
    texts = {(sura, ayah): text for sura, ayah, text in arabic.execute("SELECT sura, ayah, text FROM arabic_text")}
    ayahinfo = sqlite3.connect(f"file:{ayahinfo_path}?mode=ro", uri=True)
    glyphs = {}
    for sura, ayah, width in ayahinfo.execute(
        "SELECT sura_number, ayah_number, max_x - min_x FROM glyphs ORDER BY sura_number, ayah_number, position"
    ):
        glyphs.setdefault((sura, ayah), []).append(width)

    if len(english) != len(texts):
        fail(f"English has {len(english)} ayahs, the Arabic text has {len(texts)}")

    out = fresh_database(output_path)
    out.executescript(
        """
        CREATE TABLE properties(property TEXT, value TEXT);
        CREATE TABLE word_meanings(
            sura INTEGER, ayah INTEGER, word INTEGER, english TEXT, bengali TEXT,
            PRIMARY KEY(sura, ayah, word));
        CREATE TABLE hafs_1405_glyph_words(
            sura INTEGER, ayah INTEGER, word INTEGER, glyph_position INTEGER,
            PRIMARY KEY(sura, ayah, word));
        """
    )
    out.execute("INSERT INTO properties VALUES('version', '1')")

    meanings = 0
    missing = 0
    mapped_ayahs = 0
    for key in sorted(english):
        sura, ayah = key
        english_words = english[key]
        # QUL ends every ayah with a pseudo-word holding the ayah number, such as "(7)".
        words = max(english_words) - 1
        marker = english_words[words + 1]
        if not (marker.startswith("(") and marker.endswith(")")):
            fail(f"{sura}:{ayah} doesn't end with an ayah-number word: {marker!r}")
        bengali_words = bengali.get(key, {})
        for word in range(1, words + 1):
            # A few QUL words carry no meaning of their own (2:181 folds word 4 into word 3).
            english_text = english_words.get(word)
            bengali_text = bengali_words.get(word)
            if english_text is None and bengali_text is None:
                missing += 1
                continue
            out.execute(
                "INSERT INTO word_meanings VALUES(?, ?, ?, ?, ?)",
                (sura, ayah, word, english_text, bengali_text),
            )
            meanings += 1
        positions = glyph_positions(words, texts[key], glyphs.get(key, []))
        if positions is not None:
            mapped_ayahs += 1
            out.executemany(
                "INSERT INTO hafs_1405_glyph_words VALUES(?, ?, ?, ?)",
                [(sura, ayah, word, position) for word, position in enumerate(positions, start=1)],
            )
    out.commit()
    out.execute("VACUUM")
    out.close()
    print(f"words: {meanings} word meanings ({missing} words without one), glyphs mapped for {mapped_ayahs} of {len(english)} ayahs")


def main(argv):
    if len(argv) == 4 and argv[1] == "timings":
        build_timings(argv[2], argv[3])
    elif len(argv) == 7 and argv[1] == "words":
        build_words(*argv[2:7])
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
