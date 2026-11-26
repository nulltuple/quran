#!/usr/bin/env python3
"""Builds Arabican's vocabulary data (milestone L5) from Quranic Arabic Corpus morphology.

Arabican is the Arabic learning app (App Store Connect "Arabican"), not the Quran reader. Inputs
(downloaded once; the trail entry records URLs, commits and SHA-256):

- quran-morphology.txt, QAC morphology v0.4 as github.com/mustafa0x/quran-morphology publishes it
  (one line per segment: `sura:ayah:word:segment<TAB>text<TAB>N|V|P<TAB>features`)
- words.json from github.com/rmrashahriar/QuranicWords `dataset/` (lemma glosses in English and
  Bengali, and its own occurrence counts, which we diff against ours)
- Tools/learning/content/glosses.toml: authored glosses for lemmas QuranicWords lacks (they win)
- the reader's word data, Example/QuranEngineApp/Resources/word_by_word.db, to check that QAC
  numbers words exactly as the app does

Outputs, committed and read by compile.py:

- content/lemmas.tsv: every lemma in the top TOP_LEMMAS by occurrences, and every lemma used in the
  covered suras, with our count and rank, QuranicWords' count (the diff), and glosses
- content/word_segments.tsv: every segment of every word of the covered suras (Al-Fatihah and
  Juz Amma), with its role (prefix, stem, suffix), lemma, root and a part-of-speech label

Counts are QAC segment occurrences over the whole Quran. Ranks break ties by lemma text.

Usage:
  python3 -I Tools/learning/morphology.py --qac <quran-morphology.txt> --quranic-words <words.json>
"""

import argparse
import collections
import json
import os
import re
import sqlite3
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CONTENT = os.path.join(HERE, "content")
WORDS_DB = os.path.join(ROOT, "Example/QuranEngineApp/Resources/word_by_word.db")
TOP_LEMMAS = 300
# Al-Fatihah and Juz Amma: every sura the curriculum uses now, with room to change the bridge and
# check suras without re-running this tool.
COVERED_SURAS = (1,) + tuple(range(78, 115))
# The three ayahs Tools/build-qul-word-data.py realigned (2:181, 8:6, 13:37): QAC numbers one word
# fewer there. None is covered; the alignment check skips them.
REALIGNED_AYAHS = {(2, 181), (8, 6), (13, 37)}
LEMMA_COLUMNS = ("rank", "lemma", "root", "pos", "occurrences", "qw_occurrences", "gloss_en", "gloss_bn", "gloss_source")
SEGMENT_COLUMNS = ("sura", "ayah", "word", "segment", "text", "role", "lemma", "root", "pos")
MARKS = re.compile("[ـً-ٰٟۖ-ۭ]")


class MorphologyError(Exception):
    pass


def normalized(text):
    """Without marks and with every alif form as bare alif: QuranicWords and QAC vocalize some
    lemmas differently (مِن / مِنْ)."""
    text = MARKS.sub("", text)
    return re.sub("[آأإٱ]", "ا", text)


def pos_label(pos, tags):
    """A short English part-of-speech label for a QAC segment."""
    if pos == "V":
        aspect = {"PERF": "past", "IMPF": "present", "IMPV": "command"}.get(next((t for t in tags if t in ("PERF", "IMPF", "IMPV")), ""), "")
        form = tags.get("VF")
        label = f"verb, {aspect}" if aspect else "verb"
        if "PASS" in tags:
            label += ", passive"
        return f"{label}, form {roman(int(form))}" if form else label
    if pos == "N":
        for tag, label in (("PN", "proper noun"), ("PRON", "pronoun"), ("DEM", "demonstrative"),
                           ("REL", "relative pronoun"), ("ACT_PCPL", "active participle"),
                           ("PASS_PCPL", "passive participle"), ("VN", "verbal noun"), ("ADJ", "adjective"),
                           ("T", "time adverb"), ("LOC", "place adverb")):
            if tag in tags:
                return label
        return "noun"
    for tag, label in (("DET", "definite article"), ("P", "preposition"), ("CONJ", "conjunction"),
                       ("REM", "conjunction"), ("NEG", "negative particle"), ("VOC", "vocative particle"),
                       ("FUT", "future particle"), ("EMPH", "emphatic particle"), ("INTG", "question particle"),
                       ("COND", "conditional particle"), ("ACC", "particle")):
        if tag in tags:
            return label
    return "particle"


def roman(number):
    return ("I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII")[number - 1]


def parse_qac(path):
    """[(sura, ayah, word, segment, text, pos, tags)] where tags maps a feature to its value ('' for flags)."""
    segments = []
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, start=1):
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 4 or parts[2] not in ("N", "V", "P"):
                raise MorphologyError(f"{path}:{number}: expected location, text, N/V/P and features")
            location = tuple(int(x) for x in parts[0].split(":"))
            if len(location) != 4:
                raise MorphologyError(f"{path}:{number}: location must be sura:ayah:word:segment")
            tags = {}
            for feature in parts[3].split("|"):
                key, _, value = feature.partition(":")
                tags[key] = value
            segments.append(location + (parts[1], parts[2], tags))
    return segments


def check_alignment(segments, words_db):
    """QAC must number words exactly as word_by_word.db does, except the realigned ayahs."""
    qac = collections.Counter()
    for sura, ayah, word, *_ in segments:
        qac[(sura, ayah)] = max(qac[(sura, ayah)], word)
    db = sqlite3.connect(f"file:{words_db}?mode=ro", uri=True)
    app = {(s, a): n for s, a, n in db.execute("SELECT sura, ayah, MAX(word) FROM word_meanings GROUP BY sura, ayah")}
    db.close()
    errors = [f"{s}:{a}: QAC has {qac.get((s, a))} words, word_by_word.db {n}"
              for (s, a), n in sorted(app.items()) if qac.get((s, a)) != n and (s, a) not in REALIGNED_AYAHS]
    if errors:
        raise MorphologyError("\n".join(errors))
    return len(app)


CATEGORY = {"N": "noun", "V": "verb", "P": "particle"}
# Inflection that varies between a lemma's occurrences; a lemma's label leaves it out.
INFLECTION = ("PERF", "IMPF", "IMPV", "PASS")


def lemma_stats(segments):
    """{lemma: (occurrences, root, part-of-speech label, word class)}, the label and class from the
    lemma's first occurrence without inflection."""
    counts = collections.Counter()
    first = {}
    for sura, ayah, word, segment, text, pos, tags in segments:
        lemma = tags.get("LEM")
        if lemma:
            counts[lemma] += 1
            if lemma not in first:
                plain = {k: v for k, v in tags.items() if k not in INFLECTION}
                first[lemma] = (tags.get("ROOT", ""), pos_label(pos, plain), CATEGORY[pos])
    return {lemma: (count,) + first[lemma] for lemma, count in counts.items()}


def match_glosses(stats, quranic_words, authored):
    """{lemma: (qw occurrences or None, en, bn, source)}. Authored glosses win. Otherwise the
    QuranicWords entry of the same word class with the same root (or, for rootless particles and
    pronouns, the same normalized text) whose count is closest to ours, accepted only within a
    factor of two: QuranicWords spells some lemmas differently (ءَامَنَ / آمَنَ) and splits others
    by sense (ما: "what" and "not"), so text alone matches the wrong sense."""
    by_root, by_text = collections.defaultdict(list), collections.defaultdict(list)
    for entry in quranic_words:
        if entry.get("root"):
            by_root[(entry["root"].replace("-", ""), entry["category"])].append(entry)
        else:
            by_text[(normalized(entry["arabic"]), entry["category"])].append(entry)
    result = {}
    for lemma, (count, root, _, category) in stats.items():
        candidates = by_root.get((root, category), []) if root else by_text.get((normalized(lemma), category), [])
        candidates = [e for e in candidates if count / 2 <= e["occurrences"] <= count * 2]
        entry = min(candidates, key=lambda e: (abs(e["occurrences"] - count), e["arabic"] != lemma, e["rank"])) if candidates else None
        qw_count = entry["occurrences"] if entry else None
        if lemma in authored:
            result[lemma] = (qw_count, authored[lemma]["en"], authored[lemma]["bn"], "authored")
        elif entry:
            result[lemma] = (qw_count, entry["meaning"]["en"], entry["meaning"]["bn"], "quranic_words")
        else:
            result[lemma] = (None, "", "", "")
    return result


def load_authored(path):
    with open(path, "rb") as f:
        entries = tomllib.load(f).get("gloss", [])
    errors = [f"glosses.toml entry {i}: lemma, en and bn are required"
              for i, e in enumerate(entries, start=1) if not all(isinstance(e.get(k), str) and e[k].strip() for k in ("lemma", "en", "bn"))]
    if errors:
        raise MorphologyError("\n".join(errors))
    return {e["lemma"]: e for e in entries}


def build(segments, quranic_words, authored):
    """(lemma rows, segment rows), both sorted; raises when a top lemma has no gloss."""
    stats = lemma_stats(segments)
    ranked = sorted(stats, key=lambda lemma: (-stats[lemma][0], lemma))
    rank = {lemma: index for index, lemma in enumerate(ranked, start=1)}
    covered = set(COVERED_SURAS)
    segment_rows = []
    used = set()
    for sura, ayah, word, segment, text, pos, tags in segments:
        if sura not in covered:
            continue
        role = "prefix" if "PREF" in tags else "suffix" if "SUFF" in tags else "stem"
        lemma = tags.get("LEM", "")
        used.add(lemma)
        segment_rows.append((sura, ayah, word, segment, text, role, lemma, tags.get("ROOT", ""), pos_label(pos, tags)))
    glosses = match_glosses(stats, quranic_words, authored)
    keep = set(ranked[:TOP_LEMMAS]) | (used - {""})
    lemma_rows = []
    for lemma in sorted(keep, key=rank.get):
        count, root, pos, _ = stats[lemma]
        qw_count, en, bn, source = glosses[lemma]
        lemma_rows.append((rank[lemma], lemma, root, pos, count, "" if qw_count is None else qw_count, en, bn, source))
    missing = [row[1] for row in lemma_rows if row[0] <= TOP_LEMMAS and not row[6]]
    if missing:
        raise MorphologyError(f"top lemmas without a gloss (add them to glosses.toml): {' '.join(missing)}")
    return lemma_rows, sorted(segment_rows)


def write_tsv(path, columns, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(columns) + "\n")
        for row in rows:
            cells = [str(cell) for cell in row]
            if any("\t" in c or "\n" in c for c in cells):
                raise MorphologyError(f"{path}: a cell holds a tab or newline: {row}")
            f.write("\t".join(cells) + "\n")


def diff_summary(lemma_rows):
    top = [row for row in lemma_rows if row[0] <= TOP_LEMMAS]
    matched = [row for row in top if row[5] != ""]
    differ = [row for row in matched if row[5] != row[4]]
    return (f"top {TOP_LEMMAS}: {len(matched)} found in QuranicWords, {len(differ)} with a different count, "
            f"{len(top) - len(matched)} absent; {sum(1 for row in top if row[8] == 'authored')} authored glosses")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--qac", required=True, help="quran-morphology.txt")
    parser.add_argument("--quranic-words", required=True, help="QuranicWords dataset/words.json")
    parser.add_argument("--words-db", default=WORDS_DB)
    parser.add_argument("--content", default=CONTENT)
    args = parser.parse_args(argv)
    try:
        segments = parse_qac(args.qac)
        ayahs = check_alignment(segments, args.words_db)
        with open(args.quranic_words, encoding="utf-8") as f:
            quranic_words = json.load(f)
        lemma_rows, segment_rows = build(segments, quranic_words, load_authored(os.path.join(args.content, "glosses.toml")))
    except MorphologyError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    write_tsv(os.path.join(args.content, "lemmas.tsv"), LEMMA_COLUMNS, lemma_rows)
    write_tsv(os.path.join(args.content, "word_segments.tsv"), SEGMENT_COLUMNS, segment_rows)
    print(f"{len(segments)} segments over {ayahs} ayahs; wrote {len(lemma_rows)} lemmas, {len(segment_rows)} segments")
    print(diff_summary(lemma_rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
