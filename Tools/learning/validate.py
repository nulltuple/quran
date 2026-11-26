"""Validation rules for Arabican's learning content (milestone L1).

Imported by compile.py; every rule returns error strings rather than raising, so one run reports
every problem. Rules cover: the letter inventory, contrast sets, skill ids, lesson structure and
ordering, the skill prerequisite graph, authored Unicode, and Quran word references.
"""

import re
import unicodedata

LESSON_ID = re.compile(r"^u(\d+)\.l(\d{2})$")
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
        if match and previous and (int(match.group(1)), int(match.group(2))) <= previous:
            errors.append(f"{where}: lessons must be listed in id order")
        if match:
            previous = (int(match.group(1)), int(match.group(2)))
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
