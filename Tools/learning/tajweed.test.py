#!/usr/bin/env python3
"""Tests for Tools/learning/tajweed.py (Arabican tajweed spans, milestone L6).

Run: python3 -I Tools/learning/tajweed.test.py (or make test-learning-tools / make test-tools).
quran-transcript is not installed for these tests: phonetizer output is a fixture copied from a real
run (112:4, 2026-11-26), and compile.test.py checks the committed tajweed.tsv.
"""

import os
import sqlite3
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tajweed  # noqa: E402

QURAN_DB = tajweed.QURAN_DB
# 112:4 as quran-transcript writes it (Tanzil), and its rules: (type, pivot, dependencies).
TANZIL_112_4 = "وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ"
RULES_112_4 = [
    ("IZHAR_MEEM", (4, 5), ((7, 8),)),
    ("IDGHAM_KAMEL", (13, 14), ((13, 13),)),
    ("NORMAL_MADD", (18, 19), ()),
    ("IZHAR_NOON", (25, 26), ((28, 29),)),
    ("QALQALAH", (32, 33), ()),
    ("TASHDEED", (35, 35), ((15, 15),)),
]
QURANCOM_112_4 = ("وَلَمْ يَك<tajweed class=idgham_wo_ghunnah>ُن ل</tajweed>َّهُ<tajweed class=madda_normal>ۥ</tajweed> "
                  "كُفُوًا أَحَ<tajweed class=qalaqah>د</tajweed>ُۢ <span class=end>٤</span>")


def canonical(sura, ayah):
    db = sqlite3.connect(f"file:{QURAN_DB}?mode=ro", uri=True)
    (text,) = db.execute("SELECT text FROM arabic_text WHERE sura = ? AND ayah = ?", (sura, ayah)).fetchone()
    db.close()
    return text


class TextTests(unittest.TestCase):
    def test_graphemes_keep_marks_with_their_letter(self):
        word = "لَّهُۥ"
        self.assertEqual([word[a:b] for a, b in tajweed.graphemes(word)], ["لَّ", "هُ", "ۥ"])

    def test_tatweel_maps_to_the_letter_it_extends(self):
        # Tanzil writes the dagger alif of ar-rahman on a tatweel; the canonical text puts it on the meem.
        source, target = "ٱلرَّحْمَـٰنِ", canonical(1, 1).split(" ")[2]
        mapping = tajweed.align(source, target)
        tatweel = next(i for i, (a, _) in enumerate(tajweed.graphemes(source)) if source[a] == tajweed.TATWEEL)
        meem = next(i for i, (a, _) in enumerate(tajweed.graphemes(target)) if target[a] == "م")
        self.assertEqual(mapping[tatweel], meem)

    def test_a_long_vowel_written_as_a_letter_maps_to_the_letter_before_it(self):
        source, target = "ٱلصِّرَٲطَ", canonical(1, 6).split(" ")[1]
        mapping = tajweed.align(source, target)
        g = tajweed.graphemes(target)
        self.assertEqual(target[slice(*g[mapping[4]])], "رَٰ")

    def test_parse_qurancom_markup(self):
        text, spans = tajweed.parse_qurancom(QURANCOM_112_4)
        self.assertEqual(text, "وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدُۢ")
        self.assertEqual([(cls, text[a:b]) for cls, a, b in spans],
                         [("idgham_wo_ghunnah", "ُن ل"), ("madda_normal", "ۥ"), ("qalaqah", "د")])


class ClassifyTests(unittest.TestCase):
    def test_idgham_into_lam_after_noon_is_merging_without_ghunnah(self):
        rule, spans = tajweed.classify("IDGHAM_KAMEL", (13, 14), [(13, 13)], TANZIL_112_4)
        self.assertEqual(rule, "noonIdghamNoGhunnah")
        self.assertEqual([TANZIL_112_4[a:b] for a, b in spans], ["ن", "لَّ"])

    def test_the_article_assimilating_is_not_a_noon_rule(self):
        text = "قُلْ هُوَ ٱللَّهُ أَحَدٌ"
        self.assertIsNone(tajweed.classify("IDGHAM_KAMEL", (11, 12), [(11, 11)], text))

    def test_a_noon_rule_placed_on_the_next_letter_finds_its_tanwin(self):
        text = "فِى جِيدِهَا حَبْلٌۭ مِّن مَّسَدٍۭ"
        rule, spans = tajweed.classify("IDGHAM_GONNAH_NOON", (21, 21), [(21, 22)], text)
        self.assertEqual(rule, "noonIdghamGhunnah")
        self.assertEqual([text[a:b] for a, b in spans], ["لٌۭ", "مِّ"])

    def test_tanwin_fath_skips_its_silent_alif(self):
        text = "سَيَصْلَىٰ نَارًا ذَاتَ لَهَبٍۢ"
        start = text.index("رًا") + 1
        rule, spans = tajweed.classify("IKHFAA_NOON", (start, start + 1), [], text)
        self.assertEqual([text[a:b] for a, b in spans], ["رً", "ذَ"])

    def test_ghunnah_is_the_doubled_noon_even_in_a_merged_span(self):
        text = "مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ"
        rule, spans = tajweed.classify("MOSHADAD_NOON", (16, 21), [], text)
        self.assertEqual((rule, [text[a:b] for a, b in spans]), ("ghunnah", ["نَّ"]))

    def test_rules_outside_t1_are_dropped(self):
        self.assertIsNone(tajweed.classify("TASHDEED", (35, 35), [(15, 15)], TANZIL_112_4))
        self.assertIsNone(tajweed.classify("HAMZAT_WASL_DELETE", (9, 9), [(6, 7)], TANZIL_112_4))


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.key = (112, 4)
        self.texts = {self.key: canonical(*self.key)}
        self.phonetizer = {self.key: (TANZIL_112_4, RULES_112_4)}
        self.qurancom = {self.key: tajweed.parse_qurancom(QURANCOM_112_4)}

    def rows(self, review=None, qurancom=None):
        return tajweed.build([112], self.texts, self.phonetizer, qurancom or self.qurancom, review or {})[0]

    def test_agreement_per_rule(self):
        found = {(row[3], row[7]) for row in self.rows()}
        self.assertEqual(found, {("meemIzhar", "phonetizer"), ("noonIdghamNoGhunnah", "both"), ("maddNatural", "both"),
                                 ("noonIzhar", "phonetizer"), ("qalqalah", "both")})

    def test_rows_hold_canonical_graphemes(self):
        words = self.texts[self.key].split(" ")
        for sura, ayah, instance, rule, word, first, last, _ in self.rows():
            g = tajweed.graphemes(words[word - 1])
            self.assertLess(last, len(g), (rule, word))
        qalqalah = [row for row in self.rows() if row[3] == "qalqalah"]
        word = words[qalqalah[0][4] - 1]
        self.assertEqual(word[slice(*tajweed.graphemes(word)[qalqalah[0][5]])][0], "د")

    def test_a_disagreement_needs_a_review(self):
        markup = QURANCOM_112_4.replace("<tajweed class=qalaqah>د</tajweed>", "د")
        with self.assertRaises(tajweed.TajweedError) as raised:
            self.rows(qurancom={self.key: tajweed.parse_qurancom(markup)})
        self.assertIn('rule = "qalqalah"', str(raised.exception))
        self.assertIn('where = "5:دُۢ"', str(raised.exception))

    def test_a_review_decides_and_a_stale_review_fails(self):
        markup = QURANCOM_112_4.replace("<tajweed class=qalaqah>د</tajweed>", "د")
        qurancom = {self.key: tajweed.parse_qurancom(markup)}
        excluded = self.rows({(112, 4, "qalqalah", "5:دُۢ"): ("exclude", None)}, qurancom)
        self.assertNotIn("qalqalah", {row[3] for row in excluded})
        taught = self.rows({(112, 4, "qalqalah", "5:دُۢ"): ("teach", None)}, qurancom)
        self.assertIn(("qalqalah", "reviewed"), {(row[3], row[7]) for row in taught})
        with self.assertRaises(tajweed.TajweedError):
            self.rows({(112, 4, "qalqalah", "5:دُۢ"): ("teach", None)})


if __name__ == "__main__":
    unittest.main(verbosity=1)
