#!/usr/bin/env python3
"""Tests the Quran H5 offline import with the actual upstream export layouts."""

import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import zipfile

TOOL = Path(__file__).with_name("build-similar-verses.py")


class ImportTests(unittest.TestCase):
    def setUp(self):
        scratch = self.enterContext(tempfile.TemporaryDirectory())
        self.root = Path(scratch)
        self.quran = self.root / "quran.db"
        self.similar = self.root / "matching-ayah.db.zip"
        self.mutashabihat = self.root / "Mutashabihat ul Quran.json.bz2"
        self.output = self.root / "similar-verses.db"
        with sqlite3.connect(self.quran) as db:
            db.execute("CREATE TABLE arabic_text (sura INTEGER, ayah INTEGER, text TEXT)")
            db.executemany("INSERT INTO arabic_text VALUES (?, ?, ?)", [
                (1, 1, "بِسْمِ ٱللَّهِ الرَّحْمَٰنِ الرَّحِيمِ"),
                (1, 2, "ٱلْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ"),
                (2, 1, "بسم الله الرحمن الرحيم قل"),
                (2, 2, "بِسْمِ ٱللَّهِ الرَّحْمَٰنِ الرَّحِيمِ مِنْ"),
            ])
        self.write_similar([
            ("1:1", "2:1", 90),
            ("2:1", "1:1", 80),
            ("1:1", "1:2", 50),
        ])
        self.write_mutashabihat({"1:1": [42], "2:1": [42]})

    def write_similar(self, rows):
        db_path = self.root / "matching-ayah.db"
        db_path.unlink(missing_ok=True)
        with sqlite3.connect(db_path) as db:
            db.execute("CREATE TABLE similar_ayahs (verse_key TEXT, matched_ayah_key TEXT, score INTEGER)")
            db.executemany("INSERT INTO similar_ayahs VALUES (?, ?, ?)", rows)
        with zipfile.ZipFile(self.similar, "w") as archive:
            archive.write(db_path, "matching-ayah.db")

    def write_mutashabihat(self, index):
        with zipfile.ZipFile(self.mutashabihat, "w") as archive:
            archive.writestr("phrase_verses.json", json.dumps(index))
            archive.writestr("phrases.json", json.dumps({
                "42": {"ayah": {"1:1": [[1, 4]], "2:1": [[1, 4]]}},
            }))

    def run_import(self):
        return subprocess.run(
            [sys.executable, "-I", str(TOOL), str(self.similar), str(self.mutashabihat),
             str(self.output), "--quran-db", str(self.quran)],
            capture_output=True, text=True, check=False,
        )

    def test_cross_checks_both_sources_against_canonical_text(self):
        result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stderr)
        with sqlite3.connect(self.output) as db:
            rows = db.execute(
                "SELECT sura, ayah, match_sura, match_ayah, sources, shared_ngram, source_score "
                "FROM verse_pairs ORDER BY sura, ayah, match_sura, match_ayah"
            ).fetchall()
        self.assertEqual(rows, [
            (1, 1, 1, 2, 1, 0, 50),
            (1, 1, 2, 1, 3, 4, 90),
            (1, 1, 2, 2, 0, 4, 0),
            (2, 1, 2, 2, 0, 4, 0),
        ])

    def test_identical_sources_build_byte_identical_databases(self):
        result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stderr)
        original = self.output.read_bytes()
        result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_bytes(), original)

    def test_rejects_missing_canonical_reference_without_replacing_output(self):
        self.output.write_bytes(b"previous")
        self.write_similar([("1:1", "2:30", 90)])
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("2:30", result.stderr)
        self.assertEqual(self.output.read_bytes(), b"previous")

    def test_rejects_inconsistent_phrase_indexes(self):
        self.write_mutashabihat({"1:1": [42]})
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("phrase_verses.json disagrees", result.stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
