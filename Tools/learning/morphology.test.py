#!/usr/bin/env python3
"""Tests for Tools/learning/morphology.py (Arabican vocabulary data, milestone L5).

Run: python3 -I Tools/learning/morphology.test.py (or make test-learning-tools / make test-tools).
The real QAC and QuranicWords downloads are not in git; these tests use small fixtures, and
compile.test.py checks the committed outputs.
"""

import os
import shutil
import sqlite3
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import morphology  # noqa: E402

QAC = """1:1:1:1\tبِ\tP\tP|PREF|LEM:ب
1:1:1:2\tسْمِ\tN\tROOT:سمو|LEM:اسْم|M|GEN
1:2:1:1\tرَبِّ\tN\tROOT:ربب|LEM:رَبّ|M|GEN
1:2:2:1\tءَامَنُوا۟\tV\tPERF|VF:4|ROOT:أمن|LEM:آمَنَ|3MP
1:2:2:2\tو۟ا\tN\tPRON|SUFF|3MP
1:3:1:1\tمَا\tN\tREL|LEM:ما
1:3:2:1\tرَبِّ\tN\tROOT:ربب|LEM:رَبّ|M|GEN
2:1:1:1\tيُؤْمِنُ\tV\tIMPF|VF:4|ROOT:أمن|LEM:آمَنَ|3MS
"""


def entry(arabic, root, category, occurrences, en, rank=1):
    return {"arabic": arabic, "root": root, "category": category, "occurrences": occurrences, "rank": rank,
            "meaning": {"en": en, "bn": en + " (bn)"}}


class Fixture(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.qac = os.path.join(self.dir, "qac.txt")
        with open(self.qac, "w", encoding="utf-8") as f:
            f.write(QAC)

    def tearDown(self):
        shutil.rmtree(self.dir)

    def words_db(self, counts):
        path = os.path.join(self.dir, "w.db")
        db = sqlite3.connect(path)
        db.execute("CREATE TABLE word_meanings(sura INTEGER, ayah INTEGER, word INTEGER)")
        db.executemany("INSERT INTO word_meanings VALUES(?, ?, ?)",
                       [(s, a, w) for (s, a), n in counts.items() for w in range(1, n + 1)])
        db.commit()
        db.close()
        return path


class ParseAndAlignTests(Fixture):
    def test_parses_segments_and_features(self):
        segments = morphology.parse_qac(self.qac)
        self.assertEqual(len(segments), 8)
        self.assertEqual(segments[1][:6], (1, 1, 1, 2, "سْمِ", "N"))
        self.assertEqual(segments[1][6]["LEM"], "اسْم")
        self.assertIn("PREF", segments[0][6])

    def test_rejects_a_malformed_line(self):
        with open(self.qac, "a", encoding="utf-8") as f:
            f.write("1:4:1\tx\tN\tLEM:x\n")
        with self.assertRaises(morphology.MorphologyError):
            morphology.parse_qac(self.qac)

    def test_alignment_accepts_matching_word_counts_and_rejects_a_difference(self):
        segments = morphology.parse_qac(self.qac)
        self.assertEqual(morphology.check_alignment(segments, self.words_db({(1, 1): 1, (1, 2): 2, (1, 3): 2, (2, 1): 1})), 4)
        os.remove(os.path.join(self.dir, "w.db"))
        with self.assertRaises(morphology.MorphologyError) as raised:
            morphology.check_alignment(segments, self.words_db({(1, 1): 1, (1, 2): 3, (1, 3): 2, (2, 1): 1}))
        self.assertIn("1:2: QAC has 2 words, word_by_word.db 3", str(raised.exception))


class LabelTests(unittest.TestCase):
    def test_part_of_speech_labels(self):
        self.assertEqual(morphology.pos_label("V", {"PERF": "", "VF": "4"}), "verb, past, form IV")
        self.assertEqual(morphology.pos_label("V", {"IMPF": "", "PASS": "", "VF": "1"}), "verb, present, passive, form I")
        self.assertEqual(morphology.pos_label("N", {"PN": ""}), "proper noun")
        self.assertEqual(morphology.pos_label("N", {"PRON": "", "SUFF": ""}), "pronoun")
        self.assertEqual(morphology.pos_label("N", {"ROOT": "ربب"}), "noun")
        self.assertEqual(morphology.pos_label("P", {"DET": "", "PREF": ""}), "definite article")
        self.assertEqual(morphology.pos_label("P", {"P": "", "PREF": ""}), "preposition")


class BuildTests(Fixture):
    def test_counts_ranks_roles_and_glosses(self):
        segments = morphology.parse_qac(self.qac)
        quranic_words = [
            # Spelled differently but the same root, class and count: matched.
            entry("ءَامَنَ", "أ-م-ن", "verb", 2, "believe"),
            # Same root and class, a count far from ours (another sense): never chosen over the close one.
            entry("أَمِنَ", "أ-م-ن", "verb", 40, "are secure"),
            entry("رَبّ", "ر-ب-ب", "noun", 2, "Lord"),
            entry("بِ", None, "particle", 1, "with"),
        ]
        authored = {"ما": {"lemma": "ما", "en": "what / not", "bn": "যা / না"},
                    "اسْم": {"lemma": "اسْم", "en": "name", "bn": "নাম"}}
        lemmas, rows = morphology.build(segments, quranic_words, authored)
        by_lemma = {row[1]: row for row in lemmas}
        self.assertEqual([row[1] for row in lemmas], ["آمَنَ", "رَبّ", "اسْم", "ب", "ما"], "count, then text")
        self.assertEqual(by_lemma["آمَنَ"][2:], ("أمن", "verb, form IV", 2, 2, "believe", "believe (bn)", "quranic_words"))
        self.assertEqual(by_lemma["ما"][6:], ("what / not", "যা / না", "authored"))
        self.assertEqual(by_lemma["ب"][5], 1)
        # Sura 2 is not covered: its segment is counted but not written.
        self.assertTrue(all(row[0] == 1 for row in rows))
        roles = {(row[1], row[2], row[3]): row[5] for row in rows}
        self.assertEqual(roles[(1, 1, 1)], "prefix")
        self.assertEqual(roles[(2, 2, 1)], "stem")
        self.assertEqual(roles[(2, 2, 2)], "suffix")
        self.assertEqual([row[6] for row in rows if row[5] == "suffix"], [""], "a pronoun suffix has no lemma")

    def test_a_top_lemma_without_a_gloss_is_an_error(self):
        segments = morphology.parse_qac(self.qac)
        with self.assertRaises(morphology.MorphologyError) as raised:
            morphology.build(segments, [], {})
        self.assertIn("top lemmas without a gloss", str(raised.exception))

    def test_a_far_count_is_not_a_match(self):
        stats = {"آمَنَ": (537, "أمن", "verb, form IV", "verb")}
        glosses = morphology.match_glosses(stats, [entry("أَمِنَ", "أ-م-ن", "verb", 20, "are secure")], {})
        self.assertEqual(glosses["آمَنَ"], (None, "", "", ""))


if __name__ == "__main__":
    unittest.main(verbosity=1)
