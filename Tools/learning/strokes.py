#!/usr/bin/env python3
"""Imports letter stroke guides for Arabican's tracing exercise from Noorine (MIT).

Arabican is the Arabic learning app (App Store Connect "Arabican"), not the Quran reader. Input:
Noorine's `Core/course_content.json` (github.com/Yns1000/Noorine). Each letter there lists, per
positional form, ordered strokes: a `curve` or `line` (a polyline, at least two points) or a `dot`
(one point). Points are fractions of a square canvas, x to the right and y down, and a stroke runs
from its first point to its last, the direction a learner writes it.

Output: Tools/learning/content/strokes.json, keyed by Arabican's letters (letters.toml); letters
Arabican does not teach as their own letter (ta marbuta) are dropped. The content compiler validates
the file and writes the `stroke` table.

Usage:
  python3 -I Tools/learning/strokes.py --source <course_content.json> --commit <Noorine commit>
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "content", "strokes.json")
REPOSITORY = "Yns1000/Noorine"
SOURCE_PATH = "Core/course_content.json"
FORMS = ("isolated", "initial", "medial", "final")
KINDS = ("curve", "line", "dot")
LETTERS = "ابتثجحخدذرزسشصضطظعغفقكلمنهويء"


def convert(course, commit):
    letters = {}
    for entry in course["letters"]:
        char = entry.get("isolated")
        if char not in LETTERS:
            continue
        forms = {}
        for form in FORMS:
            strokes = (entry.get("strokes") or {}).get(form)
            if not strokes:
                continue
            forms[form] = [
                {"kind": stroke["type"], "points": [[round(x, 3), round(y, 3)] for x, y in stroke["points"]]}
                for stroke in strokes
            ]
        letters[char] = forms
    ordered = {char: letters[char] for char in LETTERS if char in letters}
    return {
        "source": {"repository": REPOSITORY, "commit": commit, "path": SOURCE_PATH, "license": "MIT"},
        "letters": ordered,
    }


def dumps(data):
    """JSON with one stroke per line, so a diff shows which stroke changed."""
    compact = {"ensure_ascii": False, "separators": (", ", ": ")}
    lines = ["{", f' "source": {json.dumps(data["source"], **compact)},', ' "letters": {']
    letters = list(data["letters"].items())
    for i, (char, forms) in enumerate(letters):
        lines.append(f"  {json.dumps(char, **compact)}: {{")
        items = list(forms.items())
        for j, (form, strokes) in enumerate(items):
            lines.append(f'   "{form}": [')
            lines += [f"    {json.dumps(stroke, **compact)}" + ("," if k < len(strokes) - 1 else "")
                      for k, stroke in enumerate(strokes)]
            lines.append("   ]" + ("," if j < len(items) - 1 else ""))
        lines.append("  }" + ("," if i < len(letters) - 1 else ""))
    lines += [" }", "}"]
    return "\n".join(lines) + "\n"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", required=True, help="Noorine's course_content.json")
    parser.add_argument("--commit", required=True, help="the Noorine commit the file came from")
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    with open(args.source, encoding="utf-8") as f:
        data = convert(json.load(f), args.commit)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(dumps(data))
    print(f"wrote {args.out}: {len(data['letters'])} letters")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
