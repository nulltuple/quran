#!/usr/bin/env python3
"""Tests for Tools/learning/compile.py and validate.py (Arabican content compiler).

Run: python3 -I Tools/learning/compile.test.py (or make test-learning-tools / make test-tools).
"""

import os
import shutil
import sqlite3
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import compile as compiler  # noqa: E402

REAL_CURRICULUM = os.path.join(HERE, "content", "curriculum.toml")
REAL_LETTERS = os.path.join(HERE, "content", "letters.toml")


def real_paths():
    return {key: compiler.DEFAULTS[key] for key in ("content", "quran_db", "words_db", "audio_dir")}


class Scratch(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.dir)

    def path(self, name):
        return os.path.join(self.dir, name)


class RealContentTests(Scratch):
    def test_build_is_deterministic(self):
        first = compiler.build(real_paths(), self.path("a.sqlite"))
        second = compiler.build(real_paths(), self.path("b.sqlite"))
        self.assertEqual(first["content_hash"], second["content_hash"])
        with open(self.path("a.sqlite"), "rb") as a, open(self.path("b.sqlite"), "rb") as b:
            self.assertEqual(a.read(), b.read(), "same inputs, same SQLite bytes on one machine")

    def test_committed_database_is_fresh(self):
        self.assertEqual(compiler.main(["--check"]), 0, "run python3 -I Tools/learning/compile.py")

    def test_quran_words_are_byte_identical_to_the_canonical_text(self):
        compiler.build(real_paths(), self.path("c.sqlite"))
        content = sqlite3.connect(self.path("c.sqlite"))
        quran = sqlite3.connect(f"file:{compiler.DEFAULTS['quran_db']}?mode=ro", uri=True)
        refs = content.execute("SELECT sura, ayah, word, text FROM quran_word_ref ORDER BY 1, 2, 3").fetchall()
        self.assertEqual(sum(1 for r in refs if r[0] == 1), 29, "Al-Fatihah has 29 words (bismillah counted as 1:1)")
        for sura, ayah, word, text in refs:
            (ayah_text,) = quran.execute("SELECT text FROM arabic_text WHERE sura = ? AND ayah = ?", (sura, ayah)).fetchone()
            self.assertEqual(text.encode(), ayah_text.split(" ")[word - 1].encode(), f"{sura}:{ayah}:{word}")

    def test_counts_and_generated_skills(self):
        data = compiler.build(real_paths(), self.path("d.sqlite"))
        self.assertEqual(data["counts"]["letters"], 29)
        db = sqlite3.connect(self.path("d.sqlite"))
        forms = dict(db.execute("SELECT letter, COUNT(*) FROM letter_form GROUP BY letter"))
        self.assertEqual(forms["ب"], 4)
        self.assertEqual(forms["د"], 2)
        self.assertEqual(forms["ء"], 1)
        self.assertEqual(db.execute("SELECT COUNT(*) FROM syllable").fetchone()[0], 29 * 3)
        prereqs = {row for row in db.execute("SELECT * FROM skill_prereq WHERE skill = 'sound.discriminate.ح-ه'")}
        self.assertEqual(prereqs, {("sound.discriminate.ح-ه", "letter.sound.ح"), ("sound.discriminate.ح-ه", "letter.sound.ه"),
                                   ("sound.discriminate.ح-ه", "letter.sound.م")})
        sources = {name for (name,) in db.execute("SELECT name FROM source")}
        self.assertEqual(sources, {"letters", "curriculum", "quran_text", "word_data", "letter_audio", "strokes"})
        self.assertEqual(db.execute("SELECT COUNT(*) FROM audio_clip").fetchone()[0], 140)
        self.assertEqual(db.execute("SELECT file FROM audio_clip WHERE id = 'ب.fatha'").fetchone()[0], "beh_fathah.caf")
        stroke_forms = db.execute("SELECT COUNT(DISTINCT letter || form) FROM stroke").fetchone()[0]
        self.assertEqual(stroke_forms, db.execute("SELECT COUNT(*) FROM letter_form").fetchone()[0], "a guide per form")
        self.assertEqual(db.execute("SELECT COUNT(DISTINCT letter) FROM word_letter WHERE exact = 1").fetchone()[0], 29)
        for ability in ("inword", "write"):
            self.assertIn(("letter.recognize.ب",), db.execute(
                "SELECT prereq FROM skill_prereq WHERE skill = ?", (f"letter.{ability}.ب",)).fetchall())

    def test_every_letter_skill_is_taught(self):
        compiler.build(real_paths(), self.path("e.sqlite"))
        db = sqlite3.connect(self.path("e.sqlite"))
        untaught = db.execute("SELECT id FROM skill WHERE family IN ('letter', 'sound') AND id NOT IN "
                              "(SELECT skill FROM lesson_skill WHERE role = 'teaches')").fetchall()
        self.assertEqual(untaught, [])


class WordLetterTests(unittest.TestCase):
    def test_plain_letters_are_exact_and_spelling_variants_are_implied(self):
        letters = set("ابتثجحخدذرزسشصضطظعغفقكلمنهويء")
        # ٱلۡحَمۡدُ (1:2:1): alif wasla implies alif; لِلَّهِ: dagger alif implies alif.
        rows = compiler.word_letters([(1, 2, 1, "ٱلۡحَمۡدُ", 0), (1, 2, 2, "لِلَّهِ", 0), (1, 1, 1, "أَحَدٌ", 0)], letters)
        by_word = {}
        for sura, ayah, word, letter, exact in rows:
            by_word.setdefault((sura, ayah, word), {})[letter] = exact
        self.assertEqual(by_word[(1, 2, 1)], {"ا": 0, "ل": 1, "ح": 1, "م": 1, "د": 1})
        self.assertEqual(by_word[(1, 2, 2)], {"ل": 1, "ه": 1})
        self.assertEqual(by_word[(1, 1, 1)], {"ا": 0, "ء": 0, "ح": 1, "د": 1})


class MalformedContentTests(Scratch):
    """Each test edits a copy of the real content and expects the compiler to refuse it."""

    def content_dir(self, curriculum=None, letters=None, audio=None, strokes=None):
        content = self.path("content")
        shutil.copytree(compiler.DEFAULTS["content"], content, dirs_exist_ok=True)
        for name, edit in (("audio.toml", audio), ("strokes.json", strokes)):
            if edit:
                with open(os.path.join(content, name), encoding="utf-8") as f:
                    text = f.read()
                with open(os.path.join(content, name), "w", encoding="utf-8") as f:
                    f.write(edit(text))
        with open(REAL_CURRICULUM, encoding="utf-8") as f:
            curriculum_text = f.read()
        with open(REAL_LETTERS, encoding="utf-8") as f:
            letters_text = f.read()
        with open(os.path.join(content, "curriculum.toml"), "w", encoding="utf-8") as f:
            f.write(curriculum(curriculum_text) if curriculum else curriculum_text)
        with open(os.path.join(content, "letters.toml"), "w", encoding="utf-8") as f:
            f.write(letters(letters_text) if letters else letters_text)
        return dict(real_paths(), content=content)

    def assertRejected(self, paths, fragment):
        with self.assertRaises(compiler.ContentError) as raised:
            compiler.build(paths, self.path("out.sqlite"))
        self.assertTrue(any(fragment in e for e in raised.exception.errors), raised.exception.errors)

    def test_unedited_copy_builds(self):
        compiler.build(self.content_dir(), self.path("ok.sqlite"))

    def test_rejects_a_duplicate_lesson_id(self):
        paths = self.content_dir(curriculum=lambda s: s.replace('id = "u2.l02"', 'id = "u2.l01"'))
        self.assertRejected(paths, "duplicate lesson id")

    def test_rejects_an_unknown_skill(self):
        paths = self.content_dir(curriculum=lambda s: s.replace('"letter.recognize.ج", ', '"letter.recognize.X", ', 1))
        self.assertRejected(paths, "unknown skill letter.recognize.X")

    def test_rejects_a_requirement_no_earlier_lesson_teaches(self):
        paths = self.content_dir(curriculum=lambda s: s.replace('requires = ["orientation.rtl"]', 'requires = ["letter.sound.م"]'))
        self.assertRejected(paths, "which no earlier lesson teaches")

    def test_rejects_a_sound_taught_before_its_letter(self):
        # letter.sound.ج needs letter.recognize.ج (a generated edge); move the recognition later.
        def edit(s):
            s = s.replace('teaches = ["letter.recognize.ج", "letter.recognize.ح", "letter.recognize.خ",',
                          'teaches = ["letter.recognize.ح", "letter.recognize.خ",')
            s = s.replace('requires = ["letter.recognize.ج"]', 'requires = ["letter.recognize.ح"]')
            return s.replace('teaches = ["letter.recognize.س",', 'teaches = ["letter.recognize.ج", "letter.recognize.س",')
        self.assertRejected(self.content_dir(curriculum=edit), "needs letter.recognize.ج, taught later in u2.l04")

    def test_rejects_a_prerequisite_cycle(self):
        import validate
        skills = {"letter.a.x": None, "letter.b.x": None}
        errors = validate.validate_skill_graph(skills, [("letter.a.x", "letter.b.x"), ("letter.b.x", "letter.a.x")])
        self.assertTrue(any("skill cycle" in e for e in errors), errors)

    def test_rejects_lessons_out_of_order(self):
        paths = self.content_dir(curriculum=lambda s: s.replace('id = "u2.l08"', 'id = "u2.l00"'))
        self.assertRejected(paths, "lessons must be listed in id order")

    def test_rejects_a_missing_letter(self):
        # ى (alif maqsura) is an Arabic code point but a spelling variant, not one of the 28 letters.
        paths = self.content_dir(letters=lambda s: s.replace('char = "ي"', 'char = "ى"'))
        self.assertRejected(paths, "must be exactly")

    def test_rejects_a_non_arabic_letter(self):
        paths = self.content_dir(letters=lambda s: s.replace('char = "ي"', 'char = "y"'))
        self.assertRejected(paths, "one Arabic letter")

    def test_rejects_non_nfc_authored_text(self):
        decomposed = "Café"
        paths = self.content_dir(curriculum=lambda s: s.replace('title = "How Arabic is written"', f'title = "{decomposed}"'))
        self.assertRejected(paths, "must be NFC")

    def test_rejects_a_lesson_in_an_undefined_unit(self):
        paths = self.content_dir(curriculum=lambda s: s.replace('id = "U2"\ntitle = "The letters"', 'id = "U3"\ntitle = "The letters"'))
        self.assertRejected(paths, "lessons use it but no [[unit]] defines it")

    def test_rejects_an_invalid_sura(self):
        paths = self.content_dir(curriculum=lambda s: s.replace("suras = [1, 94,", "suras = [115, 94,"))
        self.assertRejected(paths, "quran.suras")

    def test_rejects_a_letter_skill_no_lesson_teaches(self):
        paths = self.content_dir(curriculum=lambda s: s.replace('"letter.write.ء"]', ']').replace('"letter.write.ي", ]', '"letter.write.ي"]'))
        self.assertRejected(paths, "skill letter.write.ء is taught by no lesson")

    def test_rejects_suras_that_miss_a_letter(self):
        paths = self.content_dir(curriculum=lambda s: s.replace("suras = [1, 94, 97,", "suras = [1, 97,"))
        self.assertRejected(paths, "letter ظ: no compiled Quran word writes it")

    def test_rejects_a_missing_audio_file(self):
        paths = self.content_dir(audio=lambda s: s.replace('file = "beh_fathah.caf"', 'file = "missing.caf"'))
        self.assertRejected(paths, "audio clip ب.fatha: file missing.caf not found")

    def test_rejects_a_letter_without_its_fatha_recording(self):
        paths = self.content_dir(audio=lambda s: s.replace('kind = "fatha"\nfile = "beh_fathah.caf"', 'kind = "fatha"\nfile = "beh_fathah.caf"'.replace('fatha"', 'kasra"', 1)))
        self.assertRejected(paths, "letter ب: no fatha recording")

    def test_rejects_a_missing_or_malformed_stroke_guide(self):
        import json
        def drop(text):
            data = json.loads(text)
            del data["letters"]["ب"]["medial"]
            data["letters"]["ت"]["isolated"][1]["points"].append([0.4, 0.8])
            data["letters"]["د"]["initial"] = data["letters"]["د"]["final"]
            return json.dumps(data, ensure_ascii=False)
        paths = self.content_dir(strokes=drop)
        self.assertRejected(paths, "strokes ب medial: missing")
        self.assertRejected(paths, "strokes ت isolated #2: a dot has one point")
        self.assertRejected(paths, "strokes د initial: the letter has no such form")


class QuranWordMappingTests(Scratch):
    """quran_words on small fixture databases, including the regrouped-token cases."""

    def fixture(self, ayahs, counts, tokens=()):
        quran = sqlite3.connect(self.path("q.db"))
        quran.execute("CREATE TABLE arabic_text(sura INTEGER, ayah INTEGER, text TEXT)")
        quran.executemany("INSERT INTO arabic_text VALUES(?, ?, ?)", ayahs)
        quran.commit()
        words = sqlite3.connect(self.path("w.db"))
        words.execute("CREATE TABLE word_meanings(sura INTEGER, ayah INTEGER, word INTEGER)")
        words.execute("CREATE TABLE uthmani_tokens(sura INTEGER, ayah INTEGER, token INTEGER, first_word INTEGER, last_word INTEGER)")
        words.executemany("INSERT INTO word_meanings VALUES(?, ?, ?)",
                          [(s, a, w) for (s, a), n in counts.items() for w in range(1, n + 1)])
        words.executemany("INSERT INTO uthmani_tokens VALUES(?, ?, ?, ?, ?)", tokens)
        words.commit()
        return self.path("q.db"), self.path("w.db")

    def test_one_token_per_word(self):
        q, w = self.fixture([(1, 1, "أ ب")], {(1, 1): 2})
        rows, counts = compiler.quran_words(q, w, [1])
        self.assertEqual(rows, [(1, 1, 1, "أ", 0), (1, 1, 2, "ب", 0)])
        self.assertEqual(counts, {(1, 1): 2})

    def test_two_words_in_one_token_and_one_word_in_two_tokens(self):
        q, w = self.fixture([(2, 1, "لَّوۡمَا ت"), (2, 2, "إِلۡ يَاسِينَ")], {(2, 1): 3, (2, 2): 1},
                            [(2, 1, 1, 1, 2), (2, 1, 2, 3, 3), (2, 2, 1, 1, 1), (2, 2, 2, 1, 1)])
        rows, _ = compiler.quran_words(q, w, [2])
        self.assertEqual(rows, [(2, 1, 1, "لَّوۡمَا", 1), (2, 1, 2, "لَّوۡمَا", 1), (2, 1, 3, "ت", 0),
                                (2, 2, 1, "إِلۡ يَاسِينَ", 0)])

    def test_word_count_mismatch_is_rejected(self):
        import validate
        errors = validate.validate_quran_words([(1, 1, 1, "أ")], {(1, 1): 2})
        self.assertTrue(errors and "do not match" in errors[0], errors)


if __name__ == "__main__":
    unittest.main(verbosity=1)
