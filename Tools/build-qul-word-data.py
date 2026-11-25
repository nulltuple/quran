#!/usr/bin/env python3
"""Builds the app's word-by-word databases from Quranic Universal Library (QUL) and Quran.com data.

QUL (https://qul.tarteel.ai) needs a signed-in account to download, so its inputs are files the
owner downloaded by hand. The Quran.com input comes from `fetch-quran-com-words.py`. The outputs
are bundled in the Example app. Run with `python3 -I` and pass every path explicitly, so nothing is
read from the current directory.

Usage:
  build-qul-word-data.py timings <qul-recitation.db> <qul-word-translation.db> <output.db>
  build-qul-word-data.py words <english-wbw.db> <bengali-wbw.db> <quran-com-words.json> \
      <quran.ar.uthmani.v2.db> <ayahinfo.db> <output.db>

Words are numbered as QUL numbers them (canonical word numbers: the recitation's word segments
and both translations use them). QUL's translations end every ayah with a pseudo-word holding the
ayah number; it is dropped.

`timings` writes the gapless timing format `GRDBAyahTimingPersistence` already reads
(`timings(sura, ayah, time)`, ayah 999 marking the end of the sura) plus `word_timings`, the
recited words in recitation order (a reciter may go back and repeat words). QUL's segments are
machine aligned and have defects; these rules drop or correct them, and the tool prints how many
times each rule fired:

  invalid     a segment that ends before it starts.
  range       a segment whose word number isn't a word of the ayah.
  late-start  an ayah whose own segments begin well before QUL's ayah start. Either they begin
              after the previous ayah ended (QUL gave the first words to no ayah; 2:199): the ayah
              starts when the previous one ended plus QUL's usual 0.2 s gap. Or they begin inside
              the previous ayah's last word, whose segment then runs on through this ayah's
              recitation (6:79's last word lasts 25 s): the ayah starts at its first segment, and
              the previous ayah's last word ends there.
  outside     a segment starting outside its ayah's time span (with 0.3 s of tolerance).
  leading     segments before the ayah's first word that the recitation then starts over from,
              such as `2, 1, 2, 3`: a reciter doesn't recite word 2 and start again at word 1.
  backward    a segment going back to an earlier word without reciting on from there to where it
              left off, such as the trailing `3` in `1, 2, 4, 5, 3`. A genuine repetition
              (`1, 2, 3, 2, 3, 4`) recites on from the word it went back to.

`words` writes `word_meanings(sura, ayah, word, english, bengali, transliteration)` with a row
for every word (a missing meaning is NULL), `hafs_1405_glyph_words(sura, ayah, word,
glyph_position)` mapping each word to its glyphs in the Madani 1405 page images, and
`uthmani_tokens(sura, ayah, token, first_word, last_word)` for the ayahs whose bundled Uthmani
text splits words differently from QUL.

The glyph mapping is exact, not inferred: Quran.com gives each word's KFGQPC v1 glyph codes, one
per glyph of the font the page images were drawn with, so a word followed by a pause mark has two.
The tool checks that every ayah's glyph count matches the page database and that the Quran.com
words line up with QUL's, and leaves an ayah unmapped (whole-ayah highlighting) when they don't.
"""

import json
import os
import sqlite3
import sys
import unicodedata

# The marks that are glyphs of their own in the page images: pause marks, the rub el hizb sign
# and the sajdah sign.
MARKS = {chr(code) for code in range(0x06D6, 0x06DD)} | {"۞", "۩"}
# A segment may start this many milliseconds outside its ayah's span.
SEGMENT_TOLERANCE = 300
# QUL leaves this gap between one ayah's end and the next ayah's start.
AYAH_GAP = 200


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def fresh_database(path):
    if os.path.exists(path):
        os.remove(path)
    return sqlite3.connect(path)


def read_only(path):
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def word_translations(path):
    """QUL word texts by ayah and word number, with the ayah count of words."""
    db = read_only(path)
    result = {}
    for sura, ayah, word, text in db.execute(
        "SELECT surah_number, ayah_number, CAST(word_number AS INTEGER), text FROM word_translation"
    ):
        result.setdefault((sura, ayah), {})[word] = text
    return result


def qul_word_counts(translations):
    counts = {}
    for (sura, ayah), words in translations.items():
        last = max(words)
        marker = words[last]
        if not (marker.startswith("(") and marker.endswith(")")):
            fail(f"{sura}:{ayah} doesn't end with an ayah-number word: {marker!r}")
        counts[(sura, ayah)] = last - 1
    return counts


# MARK: - Timings


def clean_segments(segments, words, start, end, stats):
    """The segments a highlight can follow, sorted by start; counts each dropped one in `stats`."""
    valid = []
    for segment in segments:
        if len(segment) < 3 or segment[1] > segment[2]:
            stats["invalid"] += 1
        elif not 1 <= segment[0] <= words:
            stats["range"] += 1
        elif segment[1] < start - SEGMENT_TOLERANCE or segment[1] > end + SEGMENT_TOLERANCE:
            stats["outside"] += 1
        else:
            valid.append((segment[0], segment[1], segment[2]))
    valid.sort(key=lambda segment: segment[1])

    # Drop what precedes the first word when the recitation starts over from it.
    first = next((index for index, segment in enumerate(valid) if segment[0] == 1), None)
    if first and first + 1 < len(valid) and valid[first + 1][0] == 2:
        stats["leading"] += first
        valid = valid[first:]

    kept = []
    frontier = 0
    index = 0
    while index < len(valid):
        word = valid[index][0]
        if word > frontier:
            kept.append(valid[index])
            frontier = word
            index += 1
            continue
        # Going back: keep it only as the start of a run that recites on to where it left off.
        run_end = index
        while run_end + 1 < len(valid) and valid[run_end][0] < frontier and valid[run_end + 1][0] == valid[run_end][0] + 1:
            run_end += 1
        if valid[run_end][0] >= frontier:
            kept.extend(valid[index : run_end + 1])
            index = run_end + 1
        else:
            stats["backward"] += 1
            index += 1
    return kept


def build_timings(source_path, translation_path, output_path):
    counts = qul_word_counts(word_translations(translation_path))
    source = read_only(source_path)
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
    out.execute("INSERT INTO properties VALUES('version', '2')")

    stats = {name: 0 for name in ("invalid", "range", "late-start", "outside", "leading", "backward")}
    ayahs = []
    for sura, ayah, start, end, segments in rows:
        if (sura, ayah) not in counts:
            fail(f"{sura}:{ayah} has no words in the translation")
        ayahs.append([sura, ayah, start, end, json.loads(segments or "[]")])

    # Correct late ayah starts first: cleaning an ayah needs the start of the next one.
    for previous, current in zip(ayahs, ayahs[1:]):
        if previous[0] != current[0]:
            continue
        starts = [segment[1] for segment in current[4] if len(segment) >= 3 and segment[1] <= segment[2]]
        if not starts or min(starts) >= current[2] - SEGMENT_TOLERANCE:
            continue
        earliest = min(starts)
        previous_starts = [segment[1] for segment in previous[4] if len(segment) >= 3 and segment[1] <= segment[2]]
        if earliest >= previous[3]:
            stats["late-start"] += 1
            current[2] = min(earliest, previous[3] + AYAH_GAP)
        elif previous_starts and earliest > max(previous_starts):
            stats["late-start"] += 1
            current[2] = earliest
            previous[3] = earliest
            previous[4] = [segment[:1] + [segment[1], min(segment[2], earliest)] + segment[3:]
                           if len(segment) >= 3 else segment for segment in previous[4]]

    last_ayah_end = {}
    unhighlighted = 0
    for sura, ayah, start, end, segments in ayahs:
        words = counts[(sura, ayah)]
        kept = clean_segments(segments, words, start, end, stats)
        unhighlighted += words - len({segment[0] for segment in kept})
        out.execute("INSERT INTO timings VALUES(?, ?, ?)", (sura, ayah, start))
        out.executemany(
            "INSERT INTO word_timings VALUES(?, ?, ?, ?, ?, ?)",
            [(sura, ayah, seq, word, word_start, word_end) for seq, (word, word_start, word_end) in enumerate(kept)],
        )
        last_ayah_end[sura] = end
    for sura, end in last_ayah_end.items():
        out.execute("INSERT INTO timings VALUES(?, 999, ?)", (sura, end))
    out.commit()
    out.execute("VACUUM")
    out.close()
    summary = ", ".join(f"{name} {count}" for name, count in stats.items())
    print(f"timings: {len(rows)} ayahs, {len(last_ayah_end)} suras; corrections: {summary};"
          f" {unhighlighted} words without a segment of their own")


# MARK: - Quran.com words


def visible(text):
    """`text` without format characters, such as the right-to-left mark after ۩."""
    return "".join(character for character in text if unicodedata.category(character) != "Cf")


def is_mark(part):
    return all(character in MARKS for character in part)


def word_parts(text, glyph_count):
    """Splits a Quran.com word into letter parts and mark parts, one per glyph where possible."""
    parts = visible(text).split()
    # A mark can follow its word without a space (`عِوَجَاۜ`); give it a part of its own.
    if len(parts) < glyph_count:
        split = []
        for part in parts:
            if len(part) > 1 and part[-1] in MARKS and not is_mark(part):
                split.extend([part[:-1], part[-1]])
            else:
                split.append(part)
        parts = split
    return parts


def letter_tokens(record):
    """The ayah's letter tokens: (Quran.com word, text, glyph positions), in order."""
    tokens = []
    position = 1
    for word in record["words"]:
        glyphs = [character for character in word["code_v1"] if not character.isspace()]
        parts = word_parts(word["text_uthmani"], len(glyphs))
        marks = [part for part in parts if is_mark(part)]
        letters = [part for part in parts if not is_mark(part)]
        letter_glyphs = len(glyphs) - len(marks)
        if letter_glyphs < 1:
            fail(f"{record['sura']}:{record['ayah']} word {word['position']} has no letter glyph")
        # Glyphs follow the parts' order: a leading ۞, the word, then any pause marks.
        word_glyphs = []
        glyph = position
        for part in parts:
            if is_mark(part):
                glyph += 1
            else:
                word_glyphs.append(glyph)
                glyph += 1
        if len(letters) == letter_glyphs:
            pairs = [(text, [glyph]) for text, glyph in zip(letters, word_glyphs)]
        elif letter_glyphs == 1:
            # Two words drawn as one glyph (`بَعْدَ مَا` in 13:37) share it.
            first = position + (1 if parts and is_mark(parts[0]) else 0)
            pairs = [(text, [first]) for text in letters]
        else:
            # One word written in several parts (`دَآئِرَ ةٌۭ` in 5:52) is one token.
            pairs = [(" ".join(letters), list(range(position, position + letter_glyphs)))]
        tokens.extend({"qc_word": word, "text": text, "glyphs": glyph_list} for text, glyph_list in pairs)
        position += len(glyphs)
    return tokens, position - 1 + len([c for c in record["end_code_v1"] if not c.isspace()])


def align_to_qul(tokens, qul_words):
    """Groups letter tokens into QUL words, or None when that can't be done unambiguously."""
    if len(tokens) == qul_words:
        return [[token] for token in tokens]
    if len(tokens) < qul_words:
        return None
    # QUL counts a Quran.com word written in two parts as one word (`إِلْ يَاسِينَ` in 37:130).
    excess = len(tokens) - qul_words
    multi = {}
    for index, token in enumerate(tokens):
        multi.setdefault(id(token["qc_word"]), []).append(index)
    candidates = [indices for indices in multi.values() if len(indices) == excess + 1]
    if len(candidates) != 1:
        return None
    merged = set(candidates[0])
    groups = []
    for index, token in enumerate(tokens):
        if index in merged and index != candidates[0][0]:
            groups[-1].append(token)
        else:
            groups.append([token])
    return groups


# MARK: - Arabic text alignment


def skeleton(text):
    """Letters only, with spelling variants folded, so two Uthmani encodings compare equal."""
    folded = {"ٱ": "ا", "أ": "ا", "إ": "ا", "آ": "ا",
              "ى": "ي", "ی": "ي", "ؤ": "و", "ئ": "ي"}
    letters = []
    for character in unicodedata.normalize("NFC", text):
        if unicodedata.category(character) in ("Mn", "Me", "Cf", "Lm", "So", "Zs") or character in MARKS:
            continue
        if character in ("ـ", "ء"):  # Tatweel, and a hamza whose seat encodings differ.
            continue
        letters.append(folded.get(character, character))
    return "".join(letters)


def token_groups(app_tokens, qul_words):
    """Maps the bundled text's tokens to QUL word ranges, matching their letters.

    Returns [(first_word, last_word)] per token, or None when the letters don't line up. A token
    can cover several words (`لَّوۡمَا`) and several tokens one word (`إِلۡ يَاسِينَ`)."""
    token_letters = [skeleton(token) for token in app_tokens]
    word_letters = [skeleton(word) for word in qul_words]
    if "".join(token_letters) != "".join(word_letters):
        return None
    word_ends = []
    total = 0
    for letters in word_letters:
        total += len(letters)
        word_ends.append(total)
    groups = []
    offset = 0
    for letters in token_letters:
        token_start, token_end = offset, offset + len(letters)
        offset = token_end
        covered = [index + 1 for index, word_end in enumerate(word_ends)
                   if word_end - len(word_letters[index]) < token_end and word_end > token_start]
        if not covered:
            return None
        groups.append((covered[0], covered[-1]))
    # Every boundary must be shared or nested: a token may not end inside a word that another
    # token also covers partly, unless the tokens together make up exactly that word.
    for (first, last), (next_first, next_last) in zip(groups, groups[1:]):
        if next_first < last or (next_first == last and not (first == last == next_last)):
            return None
    return groups


def build_words(english_path, bengali_path, quran_com_path, arabic_path, ayahinfo_path, output_path):
    english = word_translations(english_path)
    bengali = word_translations(bengali_path)
    counts = qul_word_counts(english)
    with open(quran_com_path, encoding="utf-8") as file:
        quran_com = {(record["sura"], record["ayah"]): record for record in json.load(file)["ayahs"]}
    arabic = read_only(arabic_path)
    texts = {(sura, ayah): text for sura, ayah, text in arabic.execute("SELECT sura, ayah, text FROM arabic_text")}
    ayahinfo = read_only(ayahinfo_path)
    glyph_counts = dict(ayahinfo.execute("SELECT sura_number || ':' || ayah_number, count(*) FROM glyphs GROUP BY 1"))

    if len(counts) != len(texts):
        fail(f"the translation has {len(counts)} ayahs, the Arabic text has {len(texts)}")
    if set(quran_com) != set(counts):
        fail("the Quran.com words don't cover the same ayahs as the translation")

    out = fresh_database(output_path)
    out.executescript(
        """
        CREATE TABLE properties(property TEXT, value TEXT);
        CREATE TABLE word_meanings(
            sura INTEGER, ayah INTEGER, word INTEGER, english TEXT, bengali TEXT, transliteration TEXT,
            PRIMARY KEY(sura, ayah, word));
        CREATE TABLE hafs_1405_glyph_words(
            sura INTEGER, ayah INTEGER, word INTEGER, glyph_position INTEGER,
            PRIMARY KEY(sura, ayah, word, glyph_position));
        CREATE TABLE uthmani_tokens(
            sura INTEGER, ayah INTEGER, token INTEGER, first_word INTEGER, last_word INTEGER,
            PRIMARY KEY(sura, ayah, token));
        """
    )
    out.execute("INSERT INTO properties VALUES('version', '2')")

    unaligned = []
    glyph_mismatches = []
    text_mismatches = []
    agreeing = 0
    compared = 0
    regrouped = []
    for key in sorted(counts):
        sura, ayah = key
        words = counts[key]
        tokens, glyph_count = letter_tokens(quran_com[key])
        groups = align_to_qul(tokens, words)
        if groups is None:
            unaligned.append(f"{sura}:{ayah}")
        transliterations = {}
        if groups is not None:
            if glyph_count != glyph_counts.get(f"{sura}:{ayah}"):
                glyph_mismatches.append(f"{sura}:{ayah}")
            else:
                rows = {(word, glyph) for word, group in enumerate(groups, start=1)
                        for token in group for glyph in token["glyphs"]}
                out.executemany("INSERT INTO hafs_1405_glyph_words VALUES(?, ?, ?, ?)",
                                [(sura, ayah, word, glyph) for word, glyph in sorted(rows)])
            transliterations = word_transliterations(groups)
            # QUL's and Quran.com's English meanings come from one source, so they agree on a word
            # when both number it the same way: an independent check of the word identities.
            for word, group in enumerate(groups, start=1):
                qul_text = english[key].get(word)
                quran_com_text = group[0]["qc_word"].get("translation")
                if qul_text is not None and quran_com_text is not None:
                    compared += 1
                    agreeing += qul_text.strip() == quran_com_text.strip()
            qul_texts = [" ".join(token["text"] for token in group) for group in groups]
            app_tokens = texts[key].split()
            mapping = token_groups(app_tokens, qul_texts)
            if mapping is None and len(app_tokens) == words:
                # One spelling variant (`ٱفۡتَرَىٰهُ`/`افْتَرَاهُ` in 11:13) doesn't move any boundary.
                differing = sum(skeleton(token) != skeleton(word) for token, word in zip(app_tokens, qul_texts))
                if differing <= 1:
                    text_mismatches.append(f"{sura}:{ayah}")
                    mapping = [(index, index) for index in range(1, words + 1)]
            if mapping is None:
                fail(f"{sura}:{ayah}: the bundled Uthmani text doesn't line up with QUL's words")
            if mapping != [(index, index) for index in range(1, len(app_tokens) + 1)] or len(app_tokens) != words:
                regrouped.append(f"{sura}:{ayah}")
                out.executemany("INSERT INTO uthmani_tokens VALUES(?, ?, ?, ?, ?)",
                                [(sura, ayah, token, first, last) for token, (first, last) in enumerate(mapping, start=1)])
        shared = shared_words(groups) if groups is not None else set()
        previous = None
        for word in range(1, words + 1):
            row = (english[key].get(word), bengali.get(key, {}).get(word), transliterations.get(word))
            # QUL gives `بَعْدَ مَا` (one Quran.com word, two QUL words) one meaning, on its first
            # word; the second shows it too, as upstream's word pointer data does.
            if word in shared and previous is not None and row[0] is None and row[1] is None:
                row = (previous[0], previous[1], row[2] or previous[2])
            out.execute("INSERT INTO word_meanings VALUES(?, ?, ?, ?, ?, ?)", (sura, ayah, word, *row))
            previous = row
    out.commit()
    out.execute("VACUUM")
    out.close()
    mapped = len(counts) - len(unaligned) - len(glyph_mismatches)
    print(f"words: {sum(counts.values())} words in {len(counts)} ayahs")
    print(f"glyphs mapped for {mapped} of {len(counts)} ayahs; unaligned with QUL: {unaligned or 'none'};"
          f" glyph count differs: {glyph_mismatches or 'none'}")
    print(f"English meanings agree with Quran.com on {agreeing} of {compared} words")
    print(f"bundled Uthmani text regrouped in {regrouped or 'none'}; one-word spelling variants in {text_mismatches or 'none'}")


def shared_words(groups):
    """QUL words that continue the Quran.com word of the word before them."""
    return {word for word, (group, previous) in enumerate(zip(groups[1:], groups), start=2)
            if group[0]["qc_word"] is previous[-1]["qc_word"]}


def word_transliterations(groups):
    """Each QUL word's Quran.com transliteration; a Quran.com word split in two splits its own."""
    result = {}
    by_quran_com_word = {}
    for word, group in enumerate(groups, start=1):
        by_quran_com_word.setdefault(id(group[0]["qc_word"]), []).append((word, group))
    for entries in by_quran_com_word.values():
        text = entries[0][1][0]["qc_word"].get("transliteration")
        if not text:
            continue
        if len(entries) == 1:
            result[entries[0][0]] = text
        elif len(text.split()) == len(entries):
            for (word, _), part in zip(entries, text.split()):
                result[word] = part
        else:
            result[entries[0][0]] = text
    return result


def main(argv):
    if len(argv) == 5 and argv[1] == "timings":
        build_timings(argv[2], argv[3], argv[4])
    elif len(argv) == 8 and argv[1] == "words":
        build_words(*argv[2:8])
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
