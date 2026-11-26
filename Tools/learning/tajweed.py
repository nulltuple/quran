#!/usr/bin/env python3
"""Builds Arabican's tajweed spans (milestone L6) for the Quran bridge suras.

Arabican is the Arabic learning app (App Store Connect "Arabican"), not the Quran reader. Two
independent sources mark the rules; this tool maps both onto the canonical words and cross-checks
them (spec 03 §5.2 L6):

- quran-transcript (github.com/obadx/quran-transcript, MIT), a deterministic Hafs phonetizer, run
  here with MOSHAF (recorded in the trail entry). It runs in its own virtualenv; it never ships in the
  app. Each ayah is phonetized alone, so its last word is read with a stop (waqf), as learners read.
- Quran.com's `uthmani_tajweed` markup (`api.quran.com/api/v4/quran/verses/uthmani_tajweed`), one
  saved JSON file per sura (`tajweed_<sura>.json`).
- Tools/learning/content/tajweed_review.toml: a decision (teach or exclude, and why) for every place
  where the sources disagree. A disagreement without a decision fails the tool.

Both sources use the Tanzil encoding; the canonical text (KFGQPC) spells marks differently, so spans
are moved onto canonical graphemes by aligning each word's letters. Graphemes split as
`ArabicScript.graphemes` does: a base character and the marks after it (MARKS).

Output, committed and read by compile.py: content/tajweed.tsv, one row per word a taught rule
instance touches: sura, ayah, instance (per ayah), rule, word, first and last grapheme (0-based,
inclusive), and agreement (`both`: both sources mark it; `phonetizer`: Quran.com never marks this
rule, `UNMARKED_BY_QURANCOM`; `reviewed`: the sources disagree and the review says teach).

Usage (quran-transcript installed in a virtualenv):
  <venv>/bin/python -I Tools/learning/tajweed.py --qurancom <dir with tajweed_<sura>.json>
"""

import argparse
import difflib
import json
import os
import re
import sqlite3
import sys
import tomllib
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CONTENT = os.path.join(HERE, "content")
QURAN_DB = os.path.join(ROOT, "Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db")
COLUMNS = ("sura", "ayah", "instance", "rule", "word", "first", "last", "agreement")
# Hafs 'an 'Asim, murattal; madd lengths are the four-count choice of the quran-transcript README.
# Every other attribute keeps the library's default (its Hafs reading).
MOSHAF = {"rewaya": "hafs", "madd_monfasel_len": 4, "madd_mottasel_len": 4, "madd_mottasel_waqf": 4,
          "madd_aared_len": 4}

# ArabicScript.ArabicMark, plus the Tanzil marks the sources use instead (sukun U+0652 as a sukun,
# open tanwin U+08F0-08F2, U+06DF and U+06E3).
MARKS = set(range(0x064B, 0x0660)) | {0x0670} | set(range(0x06D6, 0x06DD)) | set(range(0x06DF, 0x06E5)) \
    | {0x06E7, 0x06E8} | set(range(0x06EA, 0x06EE)) | {0x08F0, 0x08F1, 0x08F2}
TANWIN = {0x064B, 0x064C, 0x064D, 0x0656, 0x0657, 0x065E, 0x08F0, 0x08F1, 0x08F2}
TATWEEL = "ـ"
# Letters that are one letter for alignment: hamza carriers and alif forms.
SAME_LETTER = str.maketrans({"آ": "ا", "أ": "ا", "إ": "ا", "ٱ": "ا",
                             "ى": "ي", "ۦ": "ي", "ۥ": "و"})

# quran-transcript rule type -> our rule id. IDGHAM_KAMEL is resolved in `classify` (only the noon
# case, idgham without ghunnah, is a T1 rule; the article's assimilation is U6's sun letters).
PHONETIZER_RULES = {
    "IZHAR_NOON": "noonIzhar", "IDGHAM_GONNAH_NOON": "noonIdghamGhunnah", "IQLAB_NOON": "noonIqlab",
    "IKHFAA_NOON": "noonIkhfa", "IZHAR_MEEM": "meemIzhar", "IDGHAM_MEEM": "meemIdgham",
    "IKHFAA_MEEM": "meemIkhfa", "MOSHADAD_NOON": "ghunnah", "MOSHADAD_MEEM": "ghunnah",
    "QALQALAH": "qalqalah", "NORMAL_MADD": "maddNatural", "MOTTASEL_MADD": "maddMuttasil",
    "MONFASEL_MADD": "maddMunfasil", "AARED_MADD": "maddAarid", "LAZIM_MADD": "maddLazim",
    "LEEN_MADD": "maddLeen", "ELEWAD_MADD": "maddIwad",
}
# Quran.com class -> the rules it covers. Classes not listed (ham_wasl, laam_shamsiyah, slnt,
# idgham_mutajanisayn, idgham_mutaqaribayn) are outside T1 and ignored.
QURANCOM_RULES = {
    "idgham_ghunnah": {"noonIdghamGhunnah"}, "idgham_wo_ghunnah": {"noonIdghamNoGhunnah"},
    "iqlab": {"noonIqlab"}, "ikhafa": {"noonIkhfa"}, "ikhfa_shafawi": {"meemIkhfa"},
    "idgham_shafawi": {"meemIdgham"}, "ghunnah": {"ghunnah"}, "qalaqah": {"qalqalah"},
    # Quran.com groups madds by length: obligatory (4-5) holds the separated madd too, which Hafs
    # also lengthens to 4-5 (MOSHAF).
    "madda_normal": {"maddNatural"}, "madda_obligatory": {"maddMuttasil", "maddMunfasil"},
    "madda_permissible": {"maddMunfasil", "maddAarid", "maddLeen"}, "madda_necessary": {"maddLazim"},
}
# Quran.com never colors izhar, nor the alif read after tanwin fath at a stop (madd.iwad).
UNMARKED_BY_QURANCOM = {"noonIzhar", "meemIzhar", "maddIwad"}
# Quran.com marks a natural madd only where a small letter or dagger alif writes it, never on a full
# alif, waw or ya.
FULL_MADD_LETTERS = set("اوىي")
# A madd is taught only where a letter or mark writes it (ٱللَّهِ's lengthened lam has neither).
WRITTEN_MADD = FULL_MADD_LETTERS | set("ۥۦٰٓۧ")
RULES = sorted(set(PHONETIZER_RULES.values()) | {"noonIdghamNoGhunnah"})


class TajweedError(Exception):
    pass


# MARK: Text


def is_mark(char):
    return ord(char) in MARKS


def graphemes(text):
    """[(start, end)] character ranges, as ArabicScript.graphemes splits (a base and its marks)."""
    ranges = []
    for index, char in enumerate(text):
        if is_mark(char) and ranges:
            ranges[-1] = (ranges[-1][0], index + 1)
        else:
            ranges.append((index, index + 1))
    return ranges


def words_with_offsets(text):
    """[(start, word)] for the space-separated words of an ayah."""
    result, start = [], 0
    for word in text.split(" "):
        result.append((start, word))
        start += len(word) + 1
    return result


def letter_key(word, grapheme):
    return word[grapheme[0]].translate(SAME_LETTER)


def align(source_word, canonical_word):
    """{source grapheme index: canonical grapheme index}. A source grapheme with no canonical letter
    maps where the letter before it maps: a tatweel carries that letter's marks, and a long vowel
    the source writes as a letter (Quran.com's ٲ in 1:6) is a mark on it in the canonical text."""
    source, canonical = graphemes(source_word), graphemes(canonical_word)
    keyed = [(i, letter_key(source_word, g)) for i, g in enumerate(source) if source_word[g[0]] != TATWEEL]
    target = [letter_key(canonical_word, g) for g in canonical]
    matcher = difflib.SequenceMatcher(a=[k for _, k in keyed], b=target, autojunk=False)
    mapping = {}
    for tag, a0, a1, b0, b1 in matcher.get_opcodes():
        if tag in ("equal", "replace") and a1 - a0 == b1 - b0:
            for offset in range(a1 - a0):
                mapping[keyed[a0 + offset][0]] = b0 + offset
    previous = None
    for index, g in enumerate(source):
        if index not in mapping and previous is not None:
            mapping[index] = previous
        previous = mapping.get(index, previous)
    return mapping


def span_graphemes(source_text, span):
    """{source word index: set of source grapheme indexes} that a character span covers: a grapheme
    whose base is inside, or, in a word where the span holds only marks, the graphemes of those marks."""
    start, end = span
    result = {}
    for word_index, (offset, word) in enumerate(words_with_offsets(source_text)):
        if end <= offset or start >= offset + len(word):
            continue
        bases, marks = set(), set()
        for g_index, (g0, g1) in enumerate(graphemes(word)):
            if start <= offset + g0 < end:
                bases.add(g_index)
            elif any(start <= offset + c < end for c in range(g0, g1)):
                marks.add(g_index)
        found = bases or marks
        if found:
            result[word_index] = found
    return result


def to_canonical(source_text, canonical_text, located):
    """{word number (1-based): set of canonical grapheme indexes} for {source word: graphemes}."""
    source_words = [w for _, w in words_with_offsets(source_text)]
    canonical_words = canonical_text.split(" ")
    if len(source_words) != len(canonical_words):
        raise TajweedError(f"{len(source_words)} source words, {len(canonical_words)} canonical")
    result = {}
    for word_index, found in located.items():
        mapping = align(source_words[word_index], canonical_words[word_index])
        mapped = {mapping[g] for g in found if g in mapping}
        if not mapped:
            raise TajweedError(f"word {word_index + 1}: {source_words[word_index]} does not align with "
                               f"{canonical_words[word_index]}")
        result[word_index + 1] = mapped
    return result


# MARK: Sources


def grapheme_at(text, index):
    """(start, end) of the grapheme holding character `index`."""
    start = index
    while start > 0 and is_mark(text[start]):
        start -= 1
    end = start + 1
    while end < len(text) and is_mark(text[end]):
        end += 1
    return (start, end)


def previous_grapheme(text, index):
    """(start, end) of the grapheme before the one at `index`, skipping spaces."""
    position = grapheme_at(text, index)[0] - 1 if index < len(text) else index - 1
    while position >= 0 and text[position] == " ":
        position -= 1
    return grapheme_at(text, position) if position >= 0 else None


def next_letter(text, grapheme):
    """The grapheme of the next letter that is read: spaces are skipped, and so is the silent alif
    (or alif maqsura) written after tanwin fath."""
    position = grapheme[1]
    while position < len(text) and (text[position] == " " or text[position] in "اى" and position == grapheme[1]):
        position += 1
    return grapheme_at(text, position) if position < len(text) else None


def is_noon_carrier(text, grapheme):
    """A noon with no vowel, or a letter with tanwin."""
    chars = text[grapheme[0]:grapheme[1]]
    return chars[0] == "ن" and not any(c in chars for c in "َُِّ") or any(ord(c) in TANWIN for c in chars)


def noon_carrier(text, index):
    """The noon sakinah or tanwin a noon rule at `index` belongs to: the grapheme at `index`, or the
    one before it (the phonetizer places some rules on the next letter, or between the two)."""
    if index < len(text) and text[index] != " ":
        here = grapheme_at(text, index)
        if is_noon_carrier(text, here):
            return here
    before = previous_grapheme(text, index)
    return before if before and is_noon_carrier(text, before) else None


def classify(rule_type, pivot, deps, text):
    """(our rule id, [character spans to show]) for a quran-transcript rule, or None if it is not a
    T1 rule. Spans are the rule's letter (pivot) and the letters that cause it (dependencies); a
    zero-width span (a stop) adds nothing. The phonetizer's spans are not exact for every rule
    (111:5 merges مِّن مَّسَدٍ into one span), so noon rules and ghunnah are anchored on the letters
    themselves: the noon or tanwin and the letter read after it, or the doubled noon or meem."""
    if rule_type == "IDGHAM_KAMEL":
        if pivot[1] - pivot[0] != 1 or text[pivot[0]] not in "لر":
            return None
        carrier = noon_carrier(text, pivot[0])
        return ("noonIdghamNoGhunnah", [carrier, grapheme_at(text, pivot[0])]) if carrier else None
    rule = PHONETIZER_RULES.get(rule_type)
    if rule is None:
        return None
    if rule.startswith("noon"):
        carrier = noon_carrier(text, pivot[0])
        following = carrier and next_letter(text, carrier)
        return (rule, [carrier, following]) if following else None
    if rule == "ghunnah":
        last = max(range(pivot[0], max(pivot[1], pivot[0] + 1)), key=lambda i: (text[i] in "نم", i))
        doubled = grapheme_at(text, last)
        return (rule, [doubled]) if text[doubled[0]] in "نم" and "\u0651" in text[doubled[0]:doubled[1]] else None
    spans = [s for s in [pivot] + list(deps) if s[1] > s[0]]
    return (rule, spans) if spans else None


def phonetizer_rules(sura, ayah):
    """(Tanzil text, [(rule type name, pivot, deps)]) from quran-transcript."""
    from quran_transcript import Aya, MoshafAttributes, quran_phonetizer  # the virtualenv only

    text = Aya(sura, ayah).get().uthmani
    out = quran_phonetizer(text, MoshafAttributes(**MOSHAF), sura_idx=sura)
    rules, seen = [], set()
    for metas in out.mappings.get_ph_to_tajweed_rules(out.phonemes):
        for _, meta in metas:
            key = (meta.rule_type.name, tuple(meta.uth_pivot), tuple(map(tuple, meta.uth_deps)))
            if key not in seen:
                seen.add(key)
                rules.append(key)
    return text, rules


TAG = re.compile(r"<tajweed class=([a-z_]+)>(.*?)</tajweed>|<span class=end>.*?</span>|<[^>]+>", re.S)


def parse_qurancom(markup):
    """(plain text, [(class, start, end)]) of Quran.com's uthmani_tajweed markup."""
    text, spans, position = [], [], 0
    for match in TAG.finditer(markup):
        text.append(markup[position:match.start()])
        if match.group(1):
            start = sum(len(t) for t in text)
            text.append(match.group(2))
            spans.append((match.group(1), start, start + len(match.group(2))))
        position = match.end()
    text.append(markup[position:])
    plain = "".join(text)
    stripped = plain.rstrip()
    leading = len(plain) - len(plain.lstrip())
    return stripped.strip(), [(c, s - leading, e - leading) for c, s, e in spans]


# MARK: Cross-check


def cross_check(sura, ayah, canonical, phonetizer, qurancom):
    """(instances, disagreements). Each instance is (rule, {word: graphemes}, agreement); each
    disagreement is (kind, rule or class, {word: graphemes})."""
    p_text, p_rules = phonetizer
    q_text, q_spans = qurancom
    marked = []
    for cls, start, end in q_spans:
        if cls in QURANCOM_RULES:
            marked.append([cls, to_canonical(q_text, canonical, span_graphemes(q_text, (start, end))), False])
    instances, disagreements, seen = [], [], set()
    for rule_type, pivot, deps in p_rules:
        classified = classify(rule_type, pivot, deps, p_text)
        if classified is None:
            continue
        rule, spans = classified
        where = {}
        for span in spans:
            for word, found in to_canonical(p_text, canonical, span_graphemes(p_text, span)).items():
                where.setdefault(word, set()).update(found)
        if (rule, describe(where, canonical)) in seen:
            continue
        seen.add((rule, describe(where, canonical)))
        if rule == "maddIwad":
            where = with_following_alif(where, canonical)
        shown = written(where, canonical)
        if rule.startswith("madd") and not set(shown) & WRITTEN_MADD:
            continue
        if rule in UNMARKED_BY_QURANCOM:
            instances.append((rule, where, "phonetizer"))
            continue
        match = [m for m in marked if rule in QURANCOM_RULES[m[0]] and overlaps(m[1], where)]
        for m in match:
            m[2] = True
        if match:
            instances.append((rule, where, "both"))
        elif rule == "maddNatural" and set(shown) & FULL_MADD_LETTERS and not set(shown) & (WRITTEN_MADD - FULL_MADD_LETTERS):
            instances.append((rule, where, "phonetizer"))
        else:
            disagreements.append(("phonetizer only", rule, where))
    for cls, where, used in marked:
        if not used:
            disagreements.append(("Quran.com only", cls, where))
    # The phonetizer also counts the stop's alif after tanwin (madd.iwad) as a natural madd.
    iwad = [i[1] for i in instances if i[0] == "maddIwad"]
    instances = [i for i in instances if not (i[0] == "maddNatural" and any(overlaps(i[1], w) for w in iwad))]
    return instances, disagreements


def written(where, canonical):
    """The canonical text of the graphemes in `where`."""
    words = canonical.split(" ")
    text = ""
    for word in sorted(where):
        g = graphemes(words[word - 1])
        text += "".join(words[word - 1][g[i][0]:g[i][1]] for i in sorted(where[word]))
    return text


def with_following_alif(where, canonical):
    """`where` plus the alif after its last grapheme: the letter a stop reads after tanwin fath."""
    words = canonical.split(" ")
    word = max(where)
    g = graphemes(words[word - 1])
    following = max(where[word]) + 1
    if following < len(g) and words[word - 1][g[following][0]] == "ا":
        return {**where, word: where[word] | {following}}
    return where


def overlaps(a, b):
    return any(a.get(word, set()) & found for word, found in b.items())


def describe(where, canonical):
    """`word:grapheme text` for a review key, such as `4:ن+5:ل`."""
    words = canonical.split(" ")
    parts = []
    for word in sorted(where):
        g = graphemes(words[word - 1])
        parts.append(f"{word}:" + "".join(words[word - 1][g[i][0]:g[i][1]] for i in sorted(where[word])))
    return "+".join(parts)


def load_review(path):
    """{(sura, ayah, rule or class, where): (decision, reason)}."""
    if not os.path.exists(path):
        return {}
    with open(path, "rb") as f:
        entries = tomllib.load(f).get("review", [])
    result = {}
    for entry in entries:
        sura, ayah = (int(x) for x in entry["ayah"].split(":"))
        if entry.get("decision") not in ("teach", "exclude") or not entry.get("reason"):
            raise TajweedError(f"review {entry}: decision must be teach or exclude, with a reason")
        # Editors may reorder marks (shadda and fatha); compare canonically ordered text.
        where = unicodedata.normalize("NFC", entry["where"])
        result[(sura, ayah, entry["rule"], where)] = (entry["decision"], entry.get("teach_as"))
    return result


def build(suras, canonical_text, phonetizer, qurancom, review):
    """(rows, report lines). `canonical_text`, `phonetizer` and `qurancom` map (sura, ayah) to the
    canonical text, (text, rules) and (text, spans). Raises if a disagreement has no review."""
    rows, report, missing, used = [], [], [], set()
    for sura in suras:
        for (s, ayah) in sorted(k for k in canonical_text if k[0] == sura):
            canonical = canonical_text[(s, ayah)]
            instances, disagreements = cross_check(sura, ayah, canonical, phonetizer[(s, ayah)], qurancom[(s, ayah)])
            for kind, label, where in disagreements:
                key = (sura, ayah, label, unicodedata.normalize("NFC", describe(where, canonical)))
                decision = review.get(key)
                report.append(f"{sura}:{ayah}\t{kind}\t{label}\t{key[3]}\t{decision[0] if decision else 'UNREVIEWED'}")
                if decision is None:
                    missing.append(f'[[review]]\nayah = "{sura}:{ayah}"\nrule = "{label}"\nwhere = "{key[3]}"  # {kind}')
                    continue
                used.add(key)
                if decision[0] == "teach":
                    rule = decision[1] or label
                    if rule not in RULES:
                        raise TajweedError(f"review {key}: teach_as must name a rule ({', '.join(RULES)})")
                    instances.append((rule, where, "reviewed"))
            instances.sort(key=lambda i: (min(i[1]), min(i[1][min(i[1])]), i[0]))
            for number, (rule, where, agreement) in enumerate(instances, start=1):
                for word in sorted(where):
                    found = where[word]
                    rows.append((sura, ayah, number, rule, word, min(found), max(found), agreement))
    if missing:
        raise TajweedError("disagreements without a review (add to tajweed_review.toml):\n" + "\n\n".join(missing))
    stale = set(review) - used
    if stale:
        raise TajweedError(f"reviews that match no disagreement: {sorted(stale)}")
    return rows, report


def summary(rows):
    counts = {}
    for row in rows:
        if row[4] == min(r[4] for r in rows if r[:3] == row[:3]):
            counts.setdefault(row[3], {}).setdefault(row[7], 0)
            counts[row[3]][row[7]] += 1
    return "\n".join(f"{rule}\t" + ", ".join(f"{k} {v}" for k, v in sorted(by.items())) for rule, by in sorted(counts.items()))


def write_tsv(path, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(COLUMNS) + "\n")
        for row in rows:
            f.write("\t".join(str(cell) for cell in row) + "\n")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--qurancom", required=True, help="directory with tajweed_<sura>.json")
    parser.add_argument("--quran-db", default=QURAN_DB)
    parser.add_argument("--content", default=CONTENT)
    parser.add_argument("--report", help="write every disagreement and its decision here (TSV)")
    args = parser.parse_args(argv)
    with open(os.path.join(args.content, "curriculum.toml"), "rb") as f:
        suras = [b["sura"] for b in tomllib.load(f).get("bridge", [])]
    db = sqlite3.connect(f"file:{args.quran_db}?mode=ro", uri=True)
    marks = ",".join("?" * len(suras))
    canonical = {(s, a): t for s, a, t in db.execute(f"SELECT sura, ayah, text FROM arabic_text WHERE sura IN ({marks})", suras)}
    db.close()
    qurancom = {}
    for sura in suras:
        with open(os.path.join(args.qurancom, f"tajweed_{sura}.json"), encoding="utf-8") as f:
            for verse in json.load(f)["verses"]:
                s, a = (int(x) for x in verse["verse_key"].split(":"))
                qurancom[(s, a)] = parse_qurancom(verse["text_uthmani_tajweed"])
    try:
        phonetizer = {key: phonetizer_rules(*key) for key in canonical}
        rows, report = build(suras, canonical, phonetizer, qurancom, load_review(os.path.join(args.content, "tajweed_review.toml")))
    except TajweedError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    write_tsv(os.path.join(args.content, "tajweed.tsv"), rows)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            f.write("ayah\tkind\trule\twhere\tdecision\n" + "\n".join(report) + "\n")
    print(f"{len(canonical)} ayahs; {len(report)} disagreements reviewed; wrote {len(rows)} rows")
    print(summary(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
