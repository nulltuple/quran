#!/usr/bin/env python3
"""Compiles Arabican's learning content into a read-only SQLite database.

Arabican is the Arabic learning app (App Store Connect "Arabican"), not the Quran reader. Inputs:

- Tools/learning/content/letters.toml, curriculum.toml (authored, in git)
- Tools/learning/content/audio.toml and the clips it lists (Tools/learning/audio.py writes both)
- Tools/learning/content/strokes.json, letter stroke guides (Tools/learning/strokes.py writes it)
- the canonical Uthmani text, Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db
- the reader's word data, Example/QuranEngineApp/Resources/word_by_word.db (word counts, the six
  ayahs whose tokens don't map one to one onto canonical words, and EN/BN meanings and
  transliteration)
- (L5) Tools/learning/content/lemmas.tsv and word_segments.tsv (Tools/learning/morphology.py writes
  both), content/recitation.toml and the recordings it lists, and the word timings measured on them,
  Example/QuranEngineApp/Resources/qul_afasy.db
- (L6) Tools/learning/content/tajweed.toml (rules, explanations, lessons; authored) and tajweed.tsv
  (rule spans in the bridge suras; Tools/learning/tajweed.py writes it)

Output: ArabicLearning/Sources/LearningContent/Resources/learning-content.sqlite and a manifest.
The build is deterministic: the same inputs give the same content hash (a SHA-256 of every row,
table by table, in primary-key order), so the committed database can be checked against a fresh
build with --check. Quran word text is copied byte for byte from the canonical text, never edited.

Usage:
  python3 -I Tools/learning/compile.py            # rebuild the committed database
  python3 -I Tools/learning/compile.py --check    # fail if the committed database is stale
"""

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import tempfile
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import validate  # noqa: E402  (after the path tweak; -I drops the script directory)

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULTS = {
    "content": os.path.join(HERE, "content"),
    "quran_db": os.path.join(ROOT, "Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db"),
    "words_db": os.path.join(ROOT, "Example/QuranEngineApp/Resources/word_by_word.db"),
    "timings_db": os.path.join(ROOT, "Example/QuranEngineApp/Resources/qul_afasy.db"),
    "recitation_dir": os.path.join(ROOT, "ArabicLearning/Sources/LearningContent/Resources/Recitation"),
    "out": os.path.join(ROOT, "ArabicLearning/Sources/LearningContent/Resources/learning-content.sqlite"),
    "audio_dir": os.path.join(ROOT, "ArabicLearning/Sources/LearningContent/Resources/Audio"),
}
SCHEMA_VERSION = 5
FORMS = ("isolated", "initial", "medial", "final")
SHORT_VOWELS = (("fatha", "َ"), ("kasra", "ِ"), ("damma", "ُ"))

SCHEMA = """
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE source(name TEXT PRIMARY KEY, path TEXT NOT NULL, sha256 TEXT NOT NULL, note TEXT NOT NULL);
CREATE TABLE letter(letter TEXT PRIMARY KEY, ordinal INTEGER NOT NULL UNIQUE, name TEXT NOT NULL,
    sound TEXT NOT NULL, family TEXT NOT NULL, joins_next INTEGER NOT NULL);
CREATE TABLE letter_form(letter TEXT NOT NULL REFERENCES letter(letter), form TEXT NOT NULL,
    PRIMARY KEY(letter, form));
CREATE TABLE contrast(id TEXT PRIMARY KEY, letters TEXT NOT NULL);
CREATE TABLE syllable(id TEXT PRIMARY KEY, letter TEXT NOT NULL REFERENCES letter(letter),
    vowel TEXT NOT NULL, text TEXT NOT NULL);
CREATE TABLE skill(id TEXT PRIMARY KEY, family TEXT NOT NULL, title TEXT);
CREATE TABLE skill_prereq(skill TEXT NOT NULL REFERENCES skill(id), prereq TEXT NOT NULL REFERENCES skill(id),
    PRIMARY KEY(skill, prereq));
CREATE TABLE unit(id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL UNIQUE, title TEXT NOT NULL);
CREATE TABLE lesson(id TEXT PRIMARY KEY, unit TEXT NOT NULL REFERENCES unit(id), ordinal INTEGER NOT NULL UNIQUE,
    title TEXT NOT NULL);
CREATE TABLE lesson_skill(lesson TEXT NOT NULL REFERENCES lesson(id), skill TEXT NOT NULL REFERENCES skill(id),
    role TEXT NOT NULL CHECK(role IN ('teaches', 'requires')), PRIMARY KEY(lesson, skill, role));
CREATE TABLE quran_word_ref(sura INTEGER NOT NULL, ayah INTEGER NOT NULL, word INTEGER NOT NULL,
    text TEXT NOT NULL, token_shared INTEGER NOT NULL, pool TEXT NOT NULL CHECK(pool IN ('practice', 'check')),
    meaning_en TEXT NOT NULL, meaning_bn TEXT NOT NULL, transliteration TEXT NOT NULL,
    PRIMARY KEY(sura, ayah, word));
CREATE TABLE word_letter(sura INTEGER NOT NULL, ayah INTEGER NOT NULL, word INTEGER NOT NULL,
    letter TEXT NOT NULL REFERENCES letter(letter), exact INTEGER NOT NULL, PRIMARY KEY(sura, ayah, word, letter),
    FOREIGN KEY(sura, ayah, word) REFERENCES quran_word_ref(sura, ayah, word));
CREATE TABLE audio_clip(id TEXT PRIMARY KEY, letter TEXT NOT NULL REFERENCES letter(letter), kind TEXT NOT NULL,
    file TEXT NOT NULL UNIQUE, sha256 TEXT NOT NULL, source_file TEXT NOT NULL);
CREATE TABLE lemma(lemma TEXT PRIMARY KEY, rank INTEGER NOT NULL UNIQUE, root TEXT NOT NULL, pos TEXT NOT NULL,
    occurrences INTEGER NOT NULL, gloss_en TEXT NOT NULL, gloss_bn TEXT NOT NULL);
CREATE TABLE word_segment(sura INTEGER NOT NULL, ayah INTEGER NOT NULL, word INTEGER NOT NULL, segment INTEGER NOT NULL,
    text TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('prefix', 'stem', 'suffix')), lemma TEXT REFERENCES lemma(lemma),
    root TEXT NOT NULL, pos TEXT NOT NULL, PRIMARY KEY(sura, ayah, word, segment),
    FOREIGN KEY(sura, ayah, word) REFERENCES quran_word_ref(sura, ayah, word));
CREATE TABLE bridge(sura INTEGER PRIMARY KEY, ordinal INTEGER NOT NULL UNIQUE, title TEXT NOT NULL,
    file TEXT NOT NULL UNIQUE, sha256 TEXT NOT NULL);
CREATE TABLE ayah_timing(sura INTEGER NOT NULL REFERENCES bridge(sura), ayah INTEGER NOT NULL,
    start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, PRIMARY KEY(sura, ayah));
CREATE TABLE word_timing(sura INTEGER NOT NULL REFERENCES bridge(sura), ayah INTEGER NOT NULL, seq INTEGER NOT NULL,
    word INTEGER NOT NULL, start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, PRIMARY KEY(sura, ayah, seq),
    FOREIGN KEY(sura, ayah, word) REFERENCES quran_word_ref(sura, ayah, word));
CREATE TABLE tajweed_rule(id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL UNIQUE, grp TEXT NOT NULL, name TEXT NOT NULL,
  explanation TEXT NOT NULL);
CREATE TABLE tajweed_span(sura INTEGER NOT NULL REFERENCES bridge(sura), ayah INTEGER NOT NULL, instance INTEGER NOT NULL,
  word INTEGER NOT NULL, rule TEXT NOT NULL REFERENCES tajweed_rule(id), first INTEGER NOT NULL, last INTEGER NOT NULL,
  agreement TEXT NOT NULL, PRIMARY KEY(sura, ayah, instance, word));
CREATE TABLE stroke(letter TEXT NOT NULL, form TEXT NOT NULL, ordinal INTEGER NOT NULL, kind TEXT NOT NULL,
    points TEXT NOT NULL, PRIMARY KEY(letter, form, ordinal), FOREIGN KEY(letter, form) REFERENCES letter_form(letter, form));
"""

# Spellings in which a word holds a letter without writing its plain base character: hamza carriers,
# alif wasla, ta marbuta, alif maqsura and the small letters and marks of the Uthmani text. A word
# with one of these never gets that letter as a find-in-word answer (it is not plainly visible),
# and never as a distractor either (it would be arguably present).
IMPLIED_LETTERS = {
    "\u0622": "اء", "\u0623": "اء", "\u0625": "اء", "\u0671": "ا", "\u0624": "وء", "\u0626": "يء",
    "\u0629": "ته", "\u0649": "يا", "\u06E5": "و", "\u06E6": "ي", "\u0670": "ا", "\u06E7": "ي",
    "\u06E8": "ن", "\u06E2": "م", "\u06ED": "م", "\u06D8": "م", "\u0654": "ء", "\u0655": "ء",
    "\u06DC": "س", "\u06DA": "ج",
}


# Reading skills (milestone L4), taught in units U4-U7. ExerciseKit's generator builds their
# exercises from the compiled letters, clips and words; ArabicScript.ReadableWord decides which
# words each stage may use. family -> (ability, subjects).
READING_SKILLS = {
    "vowel": [("listen", ("fatha", "kasra", "damma", "sukun")), ("read", ("fatha", "kasra", "damma", "sukun"))],
    "mark": [("spot", ("longVowel", "sukun", "shadda", "tanwin", "silentLetter"))],
    "decode": [("words", ("short", "long", "marks", "full"))],
}
# Families whose every skill a lesson must teach (validate_coverage).
COVERED_FAMILIES = ("letter", "sound", "vowel", "mark", "decode", "bridge", "lemma", "tajweed")
# Bridge and vocabulary lessons (L5) start after this check.
BRIDGE_REQUIRES = "check.U7"
LEMMA_COLUMNS = ("rank", "lemma", "root", "pos", "occurrences", "qw_occurrences", "gloss_en", "gloss_bn", "gloss_source")
SEGMENT_COLUMNS = ("sura", "ayah", "word", "segment", "text", "role", "lemma", "root", "pos")
TAJWEED_COLUMNS = ("sura", "ayah", "instance", "rule", "word", "first", "last", "agreement")
# (L6) Each tajweed rule is two skills: see it in the text and hear it in the recitation.
TAJWEED_ABILITIES = ("spot", "listen")


class ContentError(Exception):
    def __init__(self, errors):
        super().__init__("\n".join(errors))
        self.errors = errors


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_toml(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def letter_forms(letter):
    """Mirrors ArabicLetter.forms in the ArabicScript module (LearningContentTests compares them)."""
    if letter["char"] == "ء":
        return ("isolated",)
    if not letter["joins_next"]:
        return ("isolated", "final")
    return FORMS


def generated_skills(letters, contrasts, orientation):
    """Returns ({skill id: (family, title)}, [(skill, prerequisite)])."""
    skills = {}
    edges = []
    for topic in orientation:
        skills[topic["id"]] = ("orientation", topic["title"])
    for letter in letters:
        char = letter["char"]
        recognize = f"letter.recognize.{char}"
        sound = f"letter.sound.{char}"
        skills[recognize] = ("letter", None)
        skills[sound] = ("letter", None)
        edges.append((sound, recognize))
        for ability in ("inword", "write"):
            skills[f"letter.{ability}.{char}"] = ("letter", None)
            edges.append((f"letter.{ability}.{char}", recognize))
        for form in letter_forms(letter):
            if form == "isolated":
                continue
            form_skill = f"letter.form.{char}.{form}"
            skills[form_skill] = ("letter", None)
            edges.append((form_skill, recognize))
    for contrast in contrasts:
        group = contrast["letters"]
        skill = "sound.discriminate." + "-".join(group)
        skills[skill] = ("sound", None)
        edges += [(skill, f"letter.sound.{char}") for char in group]
    for family, abilities in READING_SKILLS.items():
        for ability, subjects in abilities:
            for subject in subjects:
                skills[f"{family}.{ability}.{subject}"] = (family, None)
    return skills, edges


def with_unit_checks(lessons, units, skills):
    """Appends a check lesson after the last lesson of every unit with `check = true`. It teaches
    `check.<unit>` and requires every skill the unit teaches except explanations (orientation) and
    tracing (`letter.write.*`, practice only). Its exercises use only words the learner never
    practices (check suras). Returns (lessons, new skills)."""
    checked = {unit["id"] for unit in units if unit.get("check")}
    result, added = [], {}
    for index, lesson in enumerate(lessons):
        result.append(lesson)
        unit = lesson.get("unit")
        is_last = index + 1 == len(lessons) or lessons[index + 1].get("unit") != unit
        if unit not in checked or not is_last:
            continue
        taught = [skill for other in lessons if other.get("unit") == unit for skill in other.get("teaches", [])
                  if skills.get(skill, ("",))[0] != "orientation" and not skill.startswith("letter.write.")]
        skill = f"check.{unit}"
        added[skill] = ("check", None)
        title = next(u["title"] for u in units if u["id"] == unit)
        result.append({"id": f"u{unit[1:]}.check", "unit": unit, "title": f"Check: {title}",
                       "teaches": [skill], "requires": taught})
    return result, added


def bridge_and_vocabulary(bridges, vocabulary, lemmas, units):
    """Skills and lessons of the Quran bridge unit (U8, one lesson per bridge sura) and the
    vocabulary unit (`vocabulary.unit`, the top `vocabulary.lemmas` lemmas, `per_lesson` each).
    Returns ({skill: (family, None)}, [lesson])."""
    skills, lessons = {}, []
    unit_ids = [unit["id"] for unit in units]
    bridge_unit = "U8"
    vocabulary_unit = vocabulary.get("unit", "U10")
    for index, bridge in enumerate(bridges, start=1):
        sura = bridge["sura"]
        taught = [f"bridge.listen.{sura}", f"bridge.meaning.{sura}"]
        skills.update({skill: ("bridge", None) for skill in taught})
        lessons.append({"id": f"u{bridge_unit[1:]}.l{index:02d}", "unit": bridge_unit,
                        "title": f"{bridge['title']}: listen and understand", "teaches": taught,
                        "requires": [BRIDGE_REQUIRES]})
    top = [row for row in lemmas if row["rank"] <= vocabulary.get("lemmas", 0)]
    size = vocabulary.get("per_lesson", 10)
    for index in range(0, len(top), size):
        group = top[index:index + size]
        taught = [f"lemma.meaning.{row['lemma']}" for row in group]
        skills.update({skill: ("lemma", None) for skill in taught})
        lessons.append({"id": f"u{vocabulary_unit[1:]}.l{index // size + 1:02d}", "unit": vocabulary_unit,
                        "title": f"Quran words {group[0]['rank']}–{group[-1]['rank']}", "teaches": taught,
                        "requires": [BRIDGE_REQUIRES]})
    if bridges and bridge_unit not in unit_ids or top and vocabulary_unit not in unit_ids:
        raise ContentError([f"units: define {bridge_unit} and {vocabulary_unit} for the bridge and vocabulary lessons"])
    return skills, lessons


def tajweed_lessons(tajweed):
    """(L6) Skills and lessons of the tajweed unit: each [[lesson]] of tajweed.toml teaches
    tajweed.spot.<rule> and tajweed.listen.<rule> for its rules, after `requires`.
    Returns ({skill: (family, None)}, [lesson])."""
    unit = tajweed.get("tajweed", {}).get("unit", "")
    requires = tajweed.get("tajweed", {}).get("requires", BRIDGE_REQUIRES)
    skills, lessons = {}, []
    for index, lesson in enumerate(tajweed.get("lesson", []), start=1):
        taught = [f"tajweed.{ability}.{rule}" for rule in lesson.get("rules", []) for ability in TAJWEED_ABILITIES]
        skills.update({skill: ("tajweed", None) for skill in taught})
        lessons.append({"id": f"u{unit[1:]}.l{index:02d}", "unit": unit, "title": lesson.get("title"),
                        "teaches": taught, "requires": [requires]})
    return skills, lessons


def load_tsv(path, columns, numeric):
    with open(path, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        if tuple(header) != columns:
            raise ContentError([f"{os.path.basename(path)}: expected columns {', '.join(columns)}"])
        rows = []
        for number, line in enumerate(f, start=2):
            cells = line.rstrip("\n").split("\t")
            if len(cells) != len(columns):
                raise ContentError([f"{os.path.basename(path)}:{number}: expected {len(columns)} cells"])
            row = dict(zip(columns, cells))
            for key in numeric:
                row[key] = int(row[key])
            rows.append(row)
    return rows


def load_recitations(content_dir, recitation_dir, bridges, suras):
    """{sura: (file, sha256)} for the bridge suras; errors for a missing or different recording."""
    data = load_toml(os.path.join(content_dir, "recitation.toml")).get("recitation", [])
    listed = {entry.get("sura"): entry for entry in data}
    result, errors = {}, []
    for bridge in bridges:
        sura = bridge.get("sura")
        errors += validate.validate_authored_text(f"bridge {sura} title", bridge.get("title"))
        if sura not in suras:
            errors.append(f"bridge {sura}: a bridge sura must be a practice sura ([quran] suras)")
            continue
        entry = listed.get(sura)
        if not entry:
            errors.append(f"bridge {sura}: recitation.toml lists no recording")
            continue
        path = os.path.join(recitation_dir, entry.get("file", ""))
        if not os.path.isfile(path):
            errors.append(f"bridge {sura}: recording {entry.get('file')} is missing")
        elif sha256_file(path) != entry.get("sha256"):
            errors.append(f"bridge {sura}: {entry.get('file')} is not the recording its timings were measured on")
        else:
            result[sura] = (entry["file"], entry["sha256"])
    if len({b.get("sura") for b in bridges}) != len(bridges):
        errors.append("bridge: a sura is listed twice")
    return result, errors


def recitation_timings(timings_db, suras, words):
    """(ayah rows, word rows) for `suras` from the QUL timing database: ayah spans from the gapless
    `timings` table (ayah 999 marks the sura's end) and every word segment, repeats included."""
    db = sqlite3.connect(f"file:{timings_db}?mode=ro", uri=True)
    marks = ",".join("?" * len(suras))
    starts = {}
    for sura, ayah, time in db.execute(f"SELECT sura, ayah, time FROM timings WHERE sura IN ({marks}) ORDER BY sura, ayah", suras):
        starts.setdefault(sura, []).append((ayah, time))
    ayahs = []
    for sura, rows in sorted(starts.items()):
        for (ayah, start), (_, end) in zip(rows, rows[1:]):
            ayahs.append((sura, ayah, start, end))
    word_rows = [tuple(r) for r in db.execute(
        f"SELECT sura, ayah, seq, word, start, \"end\" FROM word_timings WHERE sura IN ({marks}) ORDER BY sura, ayah, seq", suras)]
    db.close()
    errors = validate.validate_timings(ayahs, word_rows, {(w[0], w[1], w[2]) for w in words if w[0] in suras}, suras)
    return ayahs, word_rows, errors


def word_letters(words, letter_chars):
    """(sura, ayah, word, letter, exact) for every letter a word holds: exact when the word writes
    the letter's own character, not exact when it holds it only through IMPLIED_LETTERS."""
    rows = []
    for sura, ayah, word, text, *_ in words:
        found = {}
        for char in text:
            if char in letter_chars:
                found[char] = 1
            for implied in IMPLIED_LETTERS.get(char, ""):
                found.setdefault(implied, 0)
        rows += [(sura, ayah, word, letter, exact) for letter, exact in sorted(found.items())]
    return rows


def load_audio(content_dir, audio_dir):
    data = load_toml(os.path.join(content_dir, "audio.toml"))
    clips = data.get("clip", [])
    for clip in clips:
        path = os.path.join(audio_dir, clip.get("file", ""))
        clip["sha256"] = sha256_file(path) if os.path.isfile(path) else None
    return clips


def load_strokes(content_dir):
    with open(os.path.join(content_dir, "strokes.json"), encoding="utf-8") as f:
        return json.load(f).get("letters", {})


def quran_words(quran_db, words_db, suras):
    """(sura, ayah, word, text, token_shared, meaning_en, meaning_bn, transliteration) for every
    canonical word of `suras`, and the expected
    word count per ayah. Text is the canonical token, byte for byte; a word written as two tokens
    joins them with one space; two words written as one token both get that token."""
    quran = sqlite3.connect(f"file:{quran_db}?mode=ro", uri=True)
    words = sqlite3.connect(f"file:{words_db}?mode=ro", uri=True)
    marks = ",".join("?" * len(suras))
    counts = {(s, a): n for s, a, n in words.execute(
        f"SELECT sura, ayah, MAX(word) FROM word_meanings WHERE sura IN ({marks}) GROUP BY sura, ayah", suras)}
    mapping = {}
    for s, a, token, first, last in words.execute(
            f"SELECT sura, ayah, token, first_word, last_word FROM uthmani_tokens WHERE sura IN ({marks})", suras):
        mapping.setdefault((s, a), {})[token] = (first, last)
    meanings = {(s, a, w): (en or "", bn or "", tr or "") for s, a, w, en, bn, tr in words.execute(
        f"SELECT sura, ayah, word, english, bengali, transliteration FROM word_meanings WHERE sura IN ({marks})", suras)}
    rows = []
    for sura, ayah, text in quran.execute(
            f"SELECT sura, ayah, text FROM arabic_text WHERE sura IN ({marks}) ORDER BY sura, ayah", suras):
        tokens = text.split(" ")
        layout = mapping.get((sura, ayah)) or {i: (i, i) for i in range(1, len(tokens) + 1)}
        by_word = {}
        for index, token in enumerate(tokens, start=1):
            if index not in layout:
                raise ContentError([f"{sura}:{ayah}: token {index} has no word mapping"])
            first, last = layout[index]
            for word in range(first, last + 1):
                by_word.setdefault(word, []).append((token, last > first))
        for word in sorted(by_word):
            parts = by_word[word]
            rows.append((sura, ayah, word, " ".join(t for t, _ in parts), int(any(s for _, s in parts)))
                        + meanings.get((sura, ayah, word), ("", "", "")))
    quran.close()
    words.close()
    return rows, counts


def load_content(paths):
    letters_toml = load_toml(os.path.join(paths["content"], "letters.toml"))
    curriculum = load_toml(os.path.join(paths["content"], "curriculum.toml"))
    letters = letters_toml.get("letter", [])
    contrasts = letters_toml.get("contrast", [])
    orientation = curriculum.get("orientation", [])
    lessons = curriculum.get("lesson", [])
    units = curriculum.get("unit", [])
    suras = curriculum.get("quran", {}).get("suras", [])
    check_suras = curriculum.get("quran", {}).get("check_suras", [])
    bridges = curriculum.get("bridge", [])
    vocabulary = curriculum.get("vocabulary", {})
    lemmas = load_tsv(os.path.join(paths["content"], "lemmas.tsv"), LEMMA_COLUMNS, ("rank", "occurrences"))
    tajweed = load_toml(os.path.join(paths["content"], "tajweed.toml"))
    spans = load_tsv(os.path.join(paths["content"], "tajweed.tsv"), TAJWEED_COLUMNS,
                     ("sura", "ayah", "instance", "word", "first", "last"))
    segments = load_tsv(os.path.join(paths["content"], "word_segments.tsv"), SEGMENT_COLUMNS,
                        ("sura", "ayah", "word", "segment"))

    errors = validate.validate_letters(letters)
    errors += validate.validate_contrasts(contrasts, {letter.get("char") for letter in letters})
    for topic in orientation:
        errors += validate.validate_authored_text(f"orientation {topic.get('id')}", topic.get("title"))
    if errors:
        raise ContentError(errors)

    skills, edges = generated_skills(letters, contrasts, orientation)
    lessons, check_skills = with_unit_checks(lessons, units, skills)
    skills.update(check_skills)
    later_skills, later_lessons = bridge_and_vocabulary(bridges, vocabulary, lemmas, units)
    skills.update(later_skills)
    rule_skills, rule_lessons = tajweed_lessons(tajweed)
    skills.update(rule_skills)
    # Tajweed follows the bridge (its examples are the bridge suras) and comes before vocabulary.
    bridge_lessons = [lesson for lesson in later_lessons if lesson["unit"] == "U8"]
    lessons += bridge_lessons + rule_lessons + later_lessons[len(bridge_lessons):]
    errors += validate.validate_lessons(lessons, skills)
    errors += validate.validate_units(units, lessons)
    for lesson in lessons:
        for skill in lesson.get("teaches", []):
            edges += [(skill, required) for required in lesson.get("requires", [])]
    errors += validate.validate_skill_graph(skills, edges)
    errors += validate.validate_prerequisite_order(lessons, edges)
    for key, listed in (("suras", suras), ("check_suras", check_suras)):
        if not listed or any(not isinstance(s, int) or not 1 <= s <= 114 for s in listed):
            errors.append(f"quran.{key}: list sura numbers from 1 to 114")
    if set(suras) & set(check_suras):
        errors.append("quran.check_suras: a check sura must not also be a practice sura (check words stay unseen)")
    if errors:
        raise ContentError(errors)

    errors += validate.validate_coverage(lessons, skills, COVERED_FAMILIES)
    letter_chars = {letter["char"] for letter in letters}
    forms = {letter["char"]: letter_forms(letter) for letter in letters}
    clips = load_audio(paths["content"], paths["audio_dir"])
    errors += validate.validate_audio(clips, letter_chars)
    strokes = load_strokes(paths["content"])
    errors += validate.validate_strokes(strokes, forms)
    if errors:
        raise ContentError(errors)

    recordings, recitation_errors = load_recitations(paths["content"], paths["recitation_dir"], bridges, suras)
    errors += recitation_errors
    if errors:
        raise ContentError(errors)

    practice, counts = quran_words(paths["quran_db"], paths["words_db"], suras)
    check, check_counts = quran_words(paths["quran_db"], paths["words_db"], check_suras)
    errors += validate.validate_quran_words([w[:4] for w in practice + check], {**counts, **check_counts})
    errors += validate.validate_word_letters(word_letters(practice, letter_chars), letter_chars)
    words = sorted([w[:5] + ("practice",) + w[5:] for w in practice] + [w[:5] + ("check",) + w[5:] for w in check])
    found = word_letters(words, letter_chars)
    word_keys = {(w[0], w[1], w[2]) for w in words}
    segments = [s for s in segments if (s["sura"], s["ayah"], s["word"]) in word_keys]
    top = vocabulary.get("lemmas", 0)
    kept = {row["lemma"] for row in lemmas if row["rank"] <= top} | {s["lemma"] for s in segments if s["lemma"]}
    lemmas = [row for row in lemmas if row["lemma"] in kept]
    errors += validate.validate_morphology(word_keys, segments, lemmas, top)
    bridge_words = {(w[0], w[1], w[2]): w[3] for w in words if w[0] in {b.get("sura") for b in bridges}}
    errors += validate.validate_tajweed(tajweed, spans, bridge_words)
    ayah_timings, word_timings, timing_errors = recitation_timings(paths["timings_db"], sorted(recordings), words)
    errors += timing_errors
    if errors:
        raise ContentError(errors)
    return {
        "letters": letters, "contrasts": contrasts, "skills": skills, "edges": sorted(set(edges)),
        "lessons": lessons, "units": units, "words": words, "word_letters": found, "clips": clips,
        "strokes": strokes, "lemmas": lemmas, "segments": segments, "bridges": bridges, "recordings": recordings,
        "ayah_timings": ayah_timings, "word_timings": word_timings, "tajweed_rules": tajweed.get("rule", []),
        "tajweed_spans": spans,
    }


def write_database(content, paths, out):
    if os.path.exists(out):
        os.remove(out)
    db = sqlite3.connect(out)
    db.execute("PRAGMA page_size = 4096")
    db.executescript(SCHEMA)
    db.executemany("INSERT INTO meta VALUES(?, ?)", [("schema_version", str(SCHEMA_VERSION))])
    sources = [
        ("letters", "Tools/learning/content/letters.toml", "authored for Arabican"),
        ("curriculum", "Tools/learning/content/curriculum.toml", "authored for Arabican; needs teacher review"),
        ("quran_text", "Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db", "canonical Uthmani text (QuranEngine)"),
        ("word_data", "Example/QuranEngineApp/Resources/word_by_word.db", "QUL word identities (Tools/build-qul-word-data.py)"),
        ("letter_audio", "Tools/learning/content/audio.toml",
         "Antura letter recordings (CC-BY-4.0); audition log Documentation/ArabicLearning/04-audio-audition.md"),
        ("strokes", "Tools/learning/content/strokes.json", "Noorine stroke guides (MIT)"),
        ("lemmas", "Tools/learning/content/lemmas.tsv",
         "QAC morphology v0.4 (mustafa0x/quran-morphology) counts; glosses from QuranicWords and glosses.toml"),
        ("word_segments", "Tools/learning/content/word_segments.tsv", "QAC morphology v0.4 segments"),
        ("recitation", "Tools/learning/content/recitation.toml", "Mishary al-Afasy, QUL recitation 411"),
        ("word_timings", "Example/QuranEngineApp/Resources/qul_afasy.db", "QUL word segments (Tools/build-qul-word-data.py)"),
        ("tajweed_rules", "Tools/learning/content/tajweed.toml", "authored for Arabican; needs teacher review"),
        ("tajweed_spans", "Tools/learning/content/tajweed.tsv",
         "quran-transcript e30c100 (Hafs phonetizer) cross-checked with Quran.com uthmani_tajweed; "
         "disagreements decided in tajweed_review.toml"),
    ]
    key = {"letters": "content", "curriculum": "content", "quran_text": "quran_db", "word_data": "words_db",
           "letter_audio": "content", "strokes": "content", "lemmas": "content", "word_segments": "content",
           "recitation": "content", "word_timings": "timings_db", "tajweed_rules": "content", "tajweed_spans": "content"}
    for name, rel, note in sources:
        path = paths[key[name]]
        if key[name] == "content":
            path = os.path.join(path, os.path.basename(rel))
        db.execute("INSERT INTO source VALUES(?, ?, ?, ?)", (name, rel, sha256_file(path), note))
    for ordinal, letter in enumerate(content["letters"], start=1):
        db.execute("INSERT INTO letter VALUES(?, ?, ?, ?, ?, ?)", (
            letter["char"], ordinal, letter["name"], letter["sound"], letter["family"], int(letter["joins_next"])))
        db.executemany("INSERT INTO letter_form VALUES(?, ?)", [(letter["char"], f) for f in letter_forms(letter)])
        for vowel, mark in SHORT_VOWELS:
            db.execute("INSERT INTO syllable VALUES(?, ?, ?, ?)",
                       (f"{letter['char']}.{vowel}", letter["char"], vowel, letter["char"] + mark))
    for contrast in content["contrasts"]:
        db.execute("INSERT INTO contrast VALUES(?, ?)", ("-".join(contrast["letters"]), "".join(contrast["letters"])))
    db.executemany("INSERT INTO skill VALUES(?, ?, ?)",
                   [(skill, family, title) for skill, (family, title) in sorted(content["skills"].items())])
    db.executemany("INSERT INTO skill_prereq VALUES(?, ?)", content["edges"])
    db.executemany("INSERT INTO unit VALUES(?, ?, ?)",
                   [(unit["id"], ordinal, unit["title"]) for ordinal, unit in enumerate(content["units"], start=1)])
    for ordinal, lesson in enumerate(content["lessons"], start=1):
        db.execute("INSERT INTO lesson VALUES(?, ?, ?, ?)", (lesson["id"], lesson["unit"], ordinal, lesson["title"]))
        rows = [(lesson["id"], s, "teaches") for s in lesson["teaches"]]
        rows += [(lesson["id"], s, "requires") for s in lesson.get("requires", [])]
        db.executemany("INSERT INTO lesson_skill VALUES(?, ?, ?)", rows)
    db.executemany("INSERT INTO quran_word_ref VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)", content["words"])
    db.executemany("INSERT INTO lemma VALUES(?, ?, ?, ?, ?, ?, ?)", [
        (r["lemma"], r["rank"], r["root"], r["pos"], r["occurrences"], r["gloss_en"], r["gloss_bn"]) for r in content["lemmas"]])
    db.executemany("INSERT INTO word_segment VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)", [
        (s["sura"], s["ayah"], s["word"], s["segment"], s["text"], s["role"], s["lemma"] or None, s["root"], s["pos"])
        for s in content["segments"]])
    db.executemany("INSERT INTO bridge VALUES(?, ?, ?, ?, ?)", [
        (b["sura"], ordinal, b["title"]) + content["recordings"][b["sura"]]
        for ordinal, b in enumerate(content["bridges"], start=1)])
    db.executemany("INSERT INTO ayah_timing VALUES(?, ?, ?, ?)", content["ayah_timings"])
    db.executemany("INSERT INTO word_timing VALUES(?, ?, ?, ?, ?, ?)", content["word_timings"])
    db.executemany("INSERT INTO word_letter VALUES(?, ?, ?, ?, ?)", content["word_letters"])
    db.executemany("INSERT INTO tajweed_rule VALUES(?, ?, ?, ?, ?)", [
        (r["id"], ordinal, r["group"], r["name"], r["explanation"]) for ordinal, r in enumerate(content["tajweed_rules"], start=1)])
    db.executemany("INSERT INTO tajweed_span VALUES(?, ?, ?, ?, ?, ?, ?, ?)", [
        (s["sura"], s["ayah"], s["instance"], s["word"], s["rule"], s["first"], s["last"], s["agreement"])
        for s in content["tajweed_spans"]])
    db.executemany("INSERT INTO audio_clip VALUES(?, ?, ?, ?, ?, ?)", [
        (f"{c['letter']}.{c['kind']}", c["letter"], c["kind"], c["file"], c["sha256"], c["source_file"])
        for c in content["clips"]])
    for char, forms in content["strokes"].items():
        for form, strokes in forms.items():
            db.executemany("INSERT INTO stroke VALUES(?, ?, ?, ?, ?)", [
                (char, form, ordinal, stroke["kind"], json.dumps(stroke["points"], separators=(",", ":")))
                for ordinal, stroke in enumerate(strokes, start=1)])
    db.commit()
    db.execute("VACUUM")
    db.close()


def content_hash(path):
    """SHA-256 over every table's rows in primary-key order; independent of SQLite's file layout."""
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    digest = hashlib.sha256()
    tables = [name for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")]
    for table in tables:
        digest.update(f"table {table}\n".encode())
        schema = db.execute("SELECT sql FROM sqlite_master WHERE name = ?", (table,)).fetchone()[0]
        digest.update(schema.encode() + b"\n")
        columns = len(db.execute(f"SELECT * FROM {table} LIMIT 0").description)
        order = ", ".join(str(i) for i in range(1, columns + 1))
        for row in db.execute(f"SELECT * FROM {table} ORDER BY {order}"):
            digest.update(json.dumps(row, ensure_ascii=False).encode() + b"\n")
    db.close()
    return digest.hexdigest()


def manifest_path(out):
    return os.path.splitext(out)[0] + ".manifest.json"


def manifest(path, content):
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    sources = {name: {"path": rel, "sha256": sha} for name, rel, sha, _ in db.execute("SELECT * FROM source ORDER BY name")}
    db.close()
    return {
        "schema_version": SCHEMA_VERSION,
        "content_hash": content_hash(path),
        "counts": {"letters": len(content["letters"]), "skills": len(content["skills"]),
                   "lessons": len(content["lessons"]), "quran_words": len(content["words"]),
                   "check_words": sum(1 for w in content["words"] if w[5] == "check"),
                   "lemmas": len(content["lemmas"]), "word_segments": len(content["segments"]),
                   "bridge_suras": len(content["bridges"]), "word_timings": len(content["word_timings"]),
                   "audio_clips": len(content["clips"]),
                   "tajweed_spans": len({(s["sura"], s["ayah"], s["instance"]) for s in content["tajweed_spans"]}),
                   "strokes": sum(len(s) for forms in content["strokes"].values() for s in forms.values())},
        "sources": sources,
    }


def build(paths, out):
    content = load_content(paths)
    write_database(content, paths, out)
    data = manifest(out, content)
    with open(manifest_path(out), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    return data


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--content", default=DEFAULTS["content"])
    parser.add_argument("--quran-db", default=DEFAULTS["quran_db"])
    parser.add_argument("--words-db", default=DEFAULTS["words_db"])
    parser.add_argument("--out", default=DEFAULTS["out"])
    parser.add_argument("--audio-dir", default=DEFAULTS["audio_dir"])
    parser.add_argument("--timings-db", default=DEFAULTS["timings_db"])
    parser.add_argument("--recitation-dir", default=DEFAULTS["recitation_dir"])
    parser.add_argument("--check", action="store_true", help="fail if --out differs from a fresh build")
    args = parser.parse_args(argv)
    paths = {"content": args.content, "quran_db": args.quran_db, "words_db": args.words_db, "audio_dir": args.audio_dir,
             "timings_db": args.timings_db, "recitation_dir": args.recitation_dir}
    try:
        if args.check:
            with tempfile.TemporaryDirectory() as scratch:
                fresh = build(paths, os.path.join(scratch, "learning-content.sqlite"))
            committed = content_hash(args.out) if os.path.exists(args.out) else None
            if committed != fresh["content_hash"]:
                print(f"error: {args.out} is stale; run python3 -I Tools/learning/compile.py", file=sys.stderr)
                return 1
            print(f"ok: {args.out} matches a fresh build ({fresh['content_hash'][:12]})")
            return 0
        data = build(paths, args.out)
    except ContentError as error:
        for line in error.errors:
            print(f"error: {line}", file=sys.stderr)
        return 1
    print(f"wrote {args.out}: {data['counts']} content {data['content_hash'][:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
