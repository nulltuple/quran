"""Validation rules for Arabican's learning content (milestone L1).

Imported by compile.py; every rule returns error strings rather than raising, so one run reports
every problem. Rules cover: the letter inventory, contrast sets, skill ids, lesson structure and
ordering, the skill prerequisite graph, authored Unicode, Quran word references, and (L3) lesson
coverage of every letter skill, letter audio clips, stroke guides and find-in-word coverage, and
(L6) tajweed rules and spans.
"""

import re
import unicodedata

from tajweed import graphemes

# Authored lessons are u<unit>.l<NN>; the compiler adds u<unit>.check after a checked unit's lessons.
LESSON_ID = re.compile(r"^u(\d+)\.(?:l(\d{2})|check)$")
SKILL_ID = re.compile(r"^[a-z]+(\.[^\s.]+)+$")
ARABIC_LETTER_RANGE = range(0x0621, 0x064B)
# The 28 letters in hija'i order and the standalone hamza; ArabicScript's ArabicLetter lists the
# same (LearningContentTests compares the compiled table with it).
ALPHABET = "ابتثجحخدذرزسشصضطظعغفقكلمنهويء"
LETTER_COUNT = len(ALPHABET)


def validate_letters(letters):
    errors = []
    if len(letters) != LETTER_COUNT:
        errors.append(f"letters: expected {LETTER_COUNT}, found {len(letters)}")
    seen = set()
    for index, letter in enumerate(letters, start=1):
        char = letter.get("char", "")
        where = f"letters[{index}] {char!r}"
        if len(char) != 1 or ord(char) not in ARABIC_LETTER_RANGE:
            errors.append(f"{where}: char must be one Arabic letter (U+0621-U+064A)")
        if char in seen:
            errors.append(f"{where}: duplicate letter")
        seen.add(char)
        for key in ("name", "sound", "family"):
            if not isinstance(letter.get(key), str) or not letter[key].strip():
                errors.append(f"{where}: {key} is required")
        if not isinstance(letter.get("joins_next"), bool):
            errors.append(f"{where}: joins_next must be true or false")
    chars = "".join(letter.get("char", "") for letter in letters)
    if chars != ALPHABET:
        errors.append(f"letters: must be exactly {ALPHABET} in this order, found {chars}")
    return errors


def validate_contrasts(contrasts, letter_chars):
    errors = []
    seen = set()
    for index, contrast in enumerate(contrasts, start=1):
        group = contrast.get("letters", [])
        if len(group) < 2 or len(set(group)) != len(group):
            errors.append(f"contrast[{index}]: needs two or more different letters")
        for char in group:
            if char not in letter_chars:
                errors.append(f"contrast[{index}]: {char!r} is not a letter")
        key = frozenset(group)
        if key in seen:
            errors.append(f"contrast[{index}]: duplicate set")
        seen.add(key)
    return errors


def validate_authored_text(label, text):
    if not isinstance(text, str) or not text.strip():
        return [f"{label}: text is required"]
    if unicodedata.normalize("NFC", text) != text:
        return [f"{label}: authored text must be NFC"]
    return []


def validate_units(units, lessons):
    errors = []
    ids = [unit.get("id") for unit in units]
    if len(set(ids)) != len(ids):
        errors.append("units: duplicate unit id")
    for unit in units:
        if not re.match(r"^U\d+$", unit.get("id") or ""):
            errors.append(f"unit {unit.get('id')!r}: id must look like U2")
        errors += validate_authored_text(f"unit {unit.get('id')} title", unit.get("title"))
    used = [lesson.get("unit") for lesson in lessons]
    for unit in sorted(set(used) - set(ids), key=str):
        errors.append(f"unit {unit}: lessons use it but no [[unit]] defines it")
    for unit in sorted(set(ids) - set(used), key=str):
        errors.append(f"unit {unit}: has no lessons")
    return errors


def validate_lessons(lessons, skills):
    """skills: the full catalog {id: ...}. Lessons must be ordered so a lesson only requires skills
    taught by earlier lessons, which also makes the lesson graph acyclic."""
    errors = []
    taught_by = {}
    ids = set()
    previous = None
    for index, lesson in enumerate(lessons, start=1):
        lesson_id = lesson.get("id", "")
        where = f"lesson {lesson_id or index}"
        match = LESSON_ID.match(lesson_id)
        if not match:
            errors.append(f"{where}: id must look like u2.l01")
        elif lesson.get("unit") != f"U{int(match.group(1))}":
            errors.append(f"{where}: unit must be U{int(match.group(1))}")
        if lesson_id in ids:
            errors.append(f"{where}: duplicate lesson id")
        ids.add(lesson_id)
        order = (int(match.group(1)), int(match.group(2) or 100)) if match else None
        if order and previous and order <= previous:
            errors.append(f"{where}: lessons must be listed in id order")
        if order:
            previous = order
        errors += validate_authored_text(f"{where} title", lesson.get("title"))
        teaches = lesson.get("teaches", [])
        if not teaches:
            errors.append(f"{where}: teaches no skill")
        for skill in teaches:
            if skill not in skills:
                errors.append(f"{where}: teaches unknown skill {skill}")
            elif skill in taught_by:
                errors.append(f"{where}: {skill} is already taught by {taught_by[skill]}")
            else:
                taught_by[skill] = lesson_id
        for skill in lesson.get("requires", []):
            if skill not in skills:
                errors.append(f"{where}: requires unknown skill {skill}")
            elif taught_by.get(skill) in (None, lesson_id):
                errors.append(f"{where}: requires {skill}, which no earlier lesson teaches")
    return errors


def validate_prerequisite_order(lessons, edges):
    """Every prerequisite of a taught skill must be taught by the same or an earlier lesson."""
    position = {}
    for index, lesson in enumerate(lessons):
        for skill in lesson.get("teaches", []):
            position.setdefault(skill, (index, lesson.get("id")))
    errors = []
    for skill, prerequisite in sorted(set(edges)):
        if skill not in position:
            continue
        if prerequisite not in position:
            errors.append(f"{skill} (lesson {position[skill][1]}) needs {prerequisite}, which no lesson teaches")
        elif position[prerequisite][0] > position[skill][0]:
            errors.append(f"{skill} (lesson {position[skill][1]}) needs {prerequisite}, taught later in {position[prerequisite][1]}")
    return errors


def validate_skill_graph(skills, edges):
    """edges: (skill, prerequisite) pairs. Fails on unknown ids, bad ids and cycles."""
    errors = []
    for skill in skills:
        if not SKILL_ID.match(skill):
            errors.append(f"skill {skill!r}: malformed id")
    graph = {skill: set() for skill in skills}
    for skill, prerequisite in edges:
        if skill not in graph or prerequisite not in graph:
            errors.append(f"skill edge {skill} -> {prerequisite}: unknown skill")
            continue
        graph[skill].add(prerequisite)
    state = {}

    def visit(node, path):
        if state.get(node) == "done":
            return
        if state.get(node) == "active":
            errors.append("skill cycle: " + " -> ".join(path + [node]))
            return
        state[node] = "active"
        for prerequisite in sorted(graph[node]):
            visit(prerequisite, path + [node])
        state[node] = "done"

    for node in sorted(graph):
        visit(node, [])
    return errors


def validate_quran_words(words, expected_counts):
    """words: (sura, ayah, word, text) rows; expected_counts: {(sura, ayah): word count} from the
    word database. Every canonical word must appear exactly once, in order."""
    errors = []
    by_ayah = {}
    for sura, ayah, word, text in words:
        by_ayah.setdefault((sura, ayah), []).append(word)
        if not text or text != text.strip() or " " in text:
            errors.append(f"{sura}:{ayah}:{word}: word text must be one non-empty token")
    for key, count in sorted(expected_counts.items()):
        found = by_ayah.get(key, [])
        if found != list(range(1, count + 1)):
            errors.append(f"{key[0]}:{key[1]}: words {found} do not match the {count} canonical words")
    for key in sorted(set(by_ayah) - set(expected_counts)):
        errors.append(f"{key[0]}:{key[1]}: not in the word database")
    return errors


AUDIO_KINDS = ("name", "fatha", "kasra", "damma", "sukun")
STROKE_KINDS = ("curve", "line", "dot")


def validate_coverage(lessons, skills, families=("letter", "sound")):
    """Every generated skill of `families` must be taught by some lesson (spec 03, L3 exit gate:
    every letter and form covered; L4: every reading skill)."""
    taught = {skill for lesson in lessons for skill in lesson.get("teaches", [])}
    return [f"skill {skill} is taught by no lesson" for skill, (family, _) in sorted(skills.items())
            if family in families and skill not in taught]


def validate_audio(clips, letter_chars):
    """clips: audio.toml [[clip]] entries with the sha256 of their file (None when missing). Every
    letter needs its name; every letter but alif needs its fatha syllable (the sound exercises)."""
    errors = []
    ids = set()
    for clip in clips:
        clip_id = f"{clip.get('letter')}.{clip.get('kind')}"
        if clip.get("letter") not in letter_chars:
            errors.append(f"audio clip {clip_id}: unknown letter")
        if clip.get("kind") not in AUDIO_KINDS:
            errors.append(f"audio clip {clip_id}: kind must be one of {', '.join(AUDIO_KINDS)}")
        if clip_id in ids:
            errors.append(f"audio clip {clip_id}: listed twice")
        ids.add(clip_id)
        if not clip.get("source_file"):
            errors.append(f"audio clip {clip_id}: missing source_file")
        if clip.get("sha256") is None:
            errors.append(f"audio clip {clip_id}: file {clip.get('file')} not found")
    for char in sorted(letter_chars):
        if f"{char}.name" not in ids:
            errors.append(f"letter {char}: no name recording")
        if char != "ا" and f"{char}.fatha" not in ids:
            errors.append(f"letter {char}: no fatha recording")
    return errors


def validate_strokes(strokes, forms):
    """strokes: {letter: {form: [{kind, points}]}}; forms: {letter: forms it has}. Every form of
    every letter needs a guide; points are fractions of the canvas."""
    errors = []
    for char, letter_forms in sorted(forms.items()):
        for form in letter_forms:
            guide = strokes.get(char, {}).get(form)
            if not guide:
                errors.append(f"strokes {char} {form}: missing")
                continue
            for index, stroke in enumerate(guide, start=1):
                where = f"strokes {char} {form} #{index}"
                points = stroke.get("points", [])
                kind = stroke.get("kind")
                if kind not in STROKE_KINDS:
                    errors.append(f"{where}: kind must be one of {', '.join(STROKE_KINDS)}")
                elif (kind == "dot") != (len(points) == 1) or not points:
                    errors.append(f"{where}: a dot has one point, a curve or line at least two")
                if any(len(p) != 2 or not all(0 <= v <= 1 for v in p) for p in points):
                    errors.append(f"{where}: points must be [x, y] fractions from 0 to 1")
    for char, guide_forms in sorted(strokes.items()):
        for form in guide_forms:
            if form not in forms.get(char, ()):
                errors.append(f"strokes {char} {form}: the letter has no such form")
    return errors


def validate_word_letters(rows, letter_chars):
    """rows: (sura, ayah, word, letter, exact). Every letter needs a word that plainly writes it."""
    exact = {letter for *_, letter, is_exact in rows if is_exact}
    return [f"letter {char}: no compiled Quran word writes it (add a sura to [quran] suras)"
            for char in sorted(letter_chars - exact)]


def validate_morphology(word_keys, segments, lemmas, top):
    """(L5) Every compiled word has QAC segments numbered from 1; every segment lemma is a kept
    lemma; the top `top` lemmas have glosses and contiguous ranks."""
    errors = []
    by_word = {}
    for segment in segments:
        by_word.setdefault((segment["sura"], segment["ayah"], segment["word"]), []).append(segment["segment"])
        if segment["role"] not in ("prefix", "stem", "suffix"):
            errors.append(f"word_segments {segment['sura']}:{segment['ayah']}:{segment['word']}: unknown role {segment['role']}")
    for key in sorted(word_keys):
        found = sorted(by_word.get(key, []))
        if found != list(range(1, len(found) + 1)) or not found:
            errors.append(f"word_segments: {key[0]}:{key[1]}:{key[2]} has segments {found}; run Tools/learning/morphology.py")
    names = {row["lemma"] for row in lemmas}
    for lemma in sorted({s["lemma"] for s in segments if s["lemma"]} - names):
        errors.append(f"word_segments: lemma {lemma} is not in lemmas.tsv")
    ranked = sorted(row["rank"] for row in lemmas if row["rank"] <= top)
    if ranked != list(range(1, top + 1)):
        errors.append(f"lemmas.tsv: expected ranks 1-{top}")
    for row in lemmas:
        if row["rank"] <= top and not (row["gloss_en"].strip() and row["gloss_bn"].strip()):
            errors.append(f"lemmas.tsv: top lemma {row['lemma']} needs English and Bengali glosses")
        if "." in row["lemma"] or any(c.isspace() for c in row["lemma"]):
            errors.append(f"lemmas.tsv: lemma {row['lemma']!r} cannot be part of a skill id")
    return errors


def validate_timings(ayahs, words, word_keys, suras):
    """(L5) Recitation timings for the bridge suras: increasing ayah spans covering every ayah, and
    word segments that lie inside their ayah, with every compiled word recited at least once."""
    errors = []
    spans = {(s, a): (start, end) for s, a, start, end in ayahs}
    for sura, ayah, start, end in ayahs:
        if not 0 <= start < end:
            errors.append(f"timings {sura}:{ayah}: span {start}-{end} is empty")
    recited = set()
    for sura, ayah, seq, word, start, end in words:
        span = spans.get((sura, ayah))
        if span is None:
            errors.append(f"word timing {sura}:{ayah}:{word}: ayah has no span")
            continue
        if not span[0] <= start < end <= span[1] + 1000:
            errors.append(f"word timing {sura}:{ayah}:{word}: {start}-{end} is outside the ayah {span[0]}-{span[1]}")
        recited.add((sura, ayah, word))
    for key in sorted({k[:2] for k in word_keys} - set(spans)):
        errors.append(f"timings {key[0]}:{key[1]}: no ayah span")
    for key in sorted(word_keys - recited):
        errors.append(f"word timing {key[0]}:{key[1]}:{key[2]}: the word is never recited")
    for key in sorted(set(k for k in recited) - word_keys):
        errors.append(f"word timing {key[0]}:{key[1]}:{key[2]}: not a compiled word")
    return errors


TAJWEED_RULE_ID = re.compile(r"^[a-z][A-Za-z]+$")
TAJWEED_AGREEMENTS = ("both", "phonetizer", "reviewed")


def validate_tajweed(tajweed, spans, words):
    """(L6) Every rule has an id usable in a skill id, a group, a name and an explanation, belongs
    to exactly one lesson, and has an example; every span lies inside a bridge word's graphemes.
    words: {(sura, ayah, word): canonical text} of the bridge suras."""
    errors = []
    rules = tajweed.get("rule", [])
    ids = [rule.get("id") for rule in rules]
    if len(set(ids)) != len(ids):
        errors.append("tajweed.toml: duplicate rule id")
    for rule in rules:
        if not TAJWEED_RULE_ID.match(rule.get("id") or ""):
            errors.append(f"tajweed rule {rule.get('id')!r}: id must be camelCase letters")
        for key in ("group", "name", "explanation"):
            errors += validate_authored_text(f"tajweed rule {rule.get('id')} {key}", rule.get(key))
    taught = [r for lesson in tajweed.get("lesson", []) for r in lesson.get("rules", [])]
    for lesson in tajweed.get("lesson", []):
        errors += validate_authored_text("tajweed lesson title", lesson.get("title"))
    for rule in sorted(set(ids) - set(taught), key=str):
        errors.append(f"tajweed rule {rule}: no lesson teaches it")
    for rule in sorted({r for r in taught if taught.count(r) > 1} | (set(taught) - set(ids)), key=str):
        errors.append(f"tajweed lesson rule {rule}: unknown, or taught twice")
    instances = {}
    for span in spans:
        where = f"tajweed.tsv {span['sura']}:{span['ayah']}:{span['word']} {span['rule']}"
        text = words.get((span["sura"], span["ayah"], span["word"]))
        if span["rule"] not in ids:
            errors.append(f"{where}: unknown rule")
        if span["agreement"] not in TAJWEED_AGREEMENTS:
            errors.append(f"{where}: agreement must be one of {', '.join(TAJWEED_AGREEMENTS)}")
        if text is None:
            errors.append(f"{where}: not a word of a bridge sura")
        elif not 0 <= span["first"] <= span["last"] < len(graphemes(text)):
            errors.append(f"{where}: graphemes {span['first']}-{span['last']} are outside {text}")
        instances.setdefault((span["sura"], span["ayah"], span["instance"]), set()).add(span["rule"])
    for key, found in sorted(instances.items()):
        if len(found) != 1:
            errors.append(f"tajweed.tsv {key[0]}:{key[1]} instance {key[2]}: rows name different rules")
    for rule in sorted(set(ids) - {s["rule"] for s in spans}, key=str):
        errors.append(f"tajweed rule {rule}: no example in the bridge suras (run Tools/learning/tajweed.py)")
    return errors
