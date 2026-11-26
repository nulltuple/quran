#!/usr/bin/env python3
"""Tests for Tools/learning/strokes.py (Arabican stroke-guide import from Noorine).

Run: python3 -I Tools/learning/strokes.test.py (or make test-learning-tools / make test-tools).
"""

import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import strokes  # noqa: E402

COURSE = {"letters": [
    {"isolated": "ة", "strokes": {"isolated": [{"type": "dot", "points": [[0.5, 0.5]]}]}},
    {"isolated": "ب", "strokes": {
        "final": [{"type": "curve", "points": [[0.9, 0.7], [0.2, 0.5]]}],
        "isolated": [{"type": "curve", "points": [[0.81234, 0.5], [0.2, 0.5]]}, {"type": "dot", "points": [[0.5, 0.85]]}],
    }},
    {"isolated": "ا", "strokes": {"isolated": [{"type": "line", "points": [[0.5, 0.2], [0.5, 0.7]]}]}},
]}


class ConvertTests(unittest.TestCase):
    def test_keeps_arabican_letters_in_teaching_order_and_forms_in_order(self):
        data = strokes.convert(COURSE, "abc")
        self.assertEqual(list(data["letters"]), ["ا", "ب"], "ta marbuta dropped, alif before ba")
        self.assertEqual(list(data["letters"]["ب"]), ["isolated", "final"])
        self.assertEqual(data["letters"]["ب"]["isolated"][0], {"kind": "curve", "points": [[0.812, 0.5], [0.2, 0.5]]})
        self.assertEqual(data["source"]["commit"], "abc")

    def test_dumps_is_valid_json_with_one_stroke_per_line(self):
        data = strokes.convert(COURSE, "abc")
        text = strokes.dumps(data)
        self.assertEqual(json.loads(text), data)
        self.assertIn('    {"kind": "dot", "points": [[0.5, 0.85]]}\n', text)

    def test_committed_file_covers_every_letter(self):
        with open(strokes.DEFAULT_OUT, encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual("".join(data["letters"]), strokes.LETTERS)
        with open(strokes.DEFAULT_OUT, encoding="utf-8") as f:
            committed = f.read()
        self.assertEqual(strokes.dumps(data), committed,
                         "the committed file is in the tool's own format")


if __name__ == "__main__":
    unittest.main()
