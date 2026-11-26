#!/usr/bin/env python3
"""Tests for Tools/learning/audio.py (Arabican letter-audio audition and import).

Run: python3 -I Tools/learning/audio.test.py (or make test-learning-tools / make test-tools).
"""

import array
import math
import os
import shutil
import sys
import tempfile
import tomllib
import unittest
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import audio  # noqa: E402

RATE = 44100


def write_wav(path, seconds_silence=0.2, seconds_tone=0.5, amplitude=0.5, frequency=220):
    samples = [0] * int(seconds_silence * RATE)
    samples += [max(-32768, min(32767, round(amplitude * 32767 * math.sin(2 * math.pi * frequency * i / RATE))))
                for i in range(int(seconds_tone * RATE))]
    samples += [0] * int(seconds_silence * RATE)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(array.array("h", samples).tobytes())


class ClassifyTests(unittest.TestCase):
    def test_letter_names_and_vowels_map_to_clips(self):
        self.assertEqual(audio.classify("beh__lettername")[:2], ("ب", "name"))
        self.assertEqual(audio.classify("hah_fathah")[:2], ("ح", "fatha"))
        self.assertEqual(audio.classify("heh_kasrah")[:2], ("ه", "kasra"))
        self.assertEqual(audio.classify("ain_sukun")[:2], ("ع", "sukun"))
        self.assertEqual(audio.classify("hamza__lettername")[:2], ("ء", "name"))
        self.assertEqual(audio.classify("alef_hamza_low_kasrah")[:2], ("ء", "kasra"))

    def test_unused_recordings_are_deferred(self):
        for stem in ("alef_fathah", "beh_dammah_tanwin", "lam_alef", "waw_diph", "shaddah__lettername",
                     "teh_marbuta__lettername", "hah_shaddah__lettername"):
            letter, kind, reason = audio.classify(stem)
            self.assertIsNone(letter, stem)
            self.assertTrue(reason, stem)

    def test_every_letter_key_is_one_of_the_29_letters(self):
        self.assertEqual(len(set(audio.LETTER_KEYS.values())), 29)


class AuditionTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.source = os.path.join(self.dir, "src")
        os.makedirs(self.source)

    def tearDown(self):
        shutil.rmtree(self.dir)

    def wav(self, name, **kwargs):
        write_wav(os.path.join(self.source, name), **kwargs)

    @staticmethod
    def read_all(folder):
        result = {}
        for name in os.listdir(folder):
            with open(os.path.join(folder, name), "rb") as f:
                result[name] = f.read()
        return result

    def decisions(self):
        return {d["file"]: d for d in audio.audition(self.source)}

    def test_measures_the_voiced_part(self):
        self.wav("beh_fathah.wav", seconds_silence=0.3, seconds_tone=0.5)
        metrics = self.decisions()["beh_fathah.wav"]["metrics"]
        self.assertAlmostEqual(metrics["seconds"], 1.1, places=2)
        self.assertAlmostEqual(metrics["voiced_seconds"], 0.5 + 2 * audio.PAD_SECONDS, delta=0.01)
        self.assertAlmostEqual(metrics["peak_dbfs"], 20 * math.log10(0.5), delta=0.1)

    def test_accepts_a_clean_recording_and_rejects_bad_ones(self):
        self.wav("beh_fathah.wav")
        self.wav("teh_fathah.wav", seconds_tone=0.05)
        self.wav("theh_fathah.wav", amplitude=0.01)
        self.wav("jeem_fathah.wav", amplitude=1.5)
        self.wav("alef_fathah.wav", frequency=500)
        decisions = self.decisions()
        self.assertEqual(decisions["beh_fathah.wav"]["decision"], "accept")
        self.assertIn("shorter", decisions["teh_fathah.wav"]["reason"])
        self.assertIn("quieter", decisions["theh_fathah.wav"]["reason"])
        self.assertIn("clipped", decisions["jeem_fathah.wav"]["reason"])
        self.assertEqual(decisions["alef_fathah.wav"]["decision"], "defer")
        self.assertEqual({d["decision"] for n, d in decisions.items() if n not in ("beh_fathah.wav", "alef_fathah.wav")},
                         {"reject"})

    def test_rejects_a_duplicate_recording(self):
        self.wav("beh_fathah.wav")
        self.wav("teh_fathah.wav")
        decisions = self.decisions()
        self.assertEqual(decisions["beh_fathah.wav"]["decision"], "accept")
        self.assertEqual(decisions["teh_fathah.wav"]["decision"], "reject")
        self.assertIn("same samples as beh_fathah.wav", decisions["teh_fathah.wav"]["reason"])

    def test_trimmed_audio_is_normalized_and_short(self):
        self.wav("beh_fathah.wav", seconds_silence=0.5, amplitude=0.2)
        decision = self.decisions()["beh_fathah.wav"]
        samples, rate = audio.read_wav(os.path.join(self.source, "beh_fathah.wav"))
        out = os.path.join(self.dir, "trimmed.wav")
        audio.write_trimmed_wav(samples, rate, decision["metrics"], out)
        trimmed, _ = audio.read_wav(out)
        self.assertAlmostEqual(len(trimmed) / RATE, 0.5 + 2 * audio.PAD_SECONDS, delta=0.01)
        self.assertAlmostEqual(audio.dbfs(max(abs(s) for s in trimmed)), audio.TARGET_PEAK_DBFS, delta=0.1)

    @unittest.skipUnless(shutil.which("afconvert"), "afconvert is macOS only")
    def test_main_writes_clips_toml_and_log(self):
        self.wav("beh__lettername.wav", frequency=300)
        self.wav("beh_fathah.wav")
        self.wav("waw_diph.wav", frequency=400)
        out_dir = os.path.join(self.dir, "Audio")
        toml_path = os.path.join(self.dir, "audio.toml")
        log_path = os.path.join(self.dir, "log.md")
        args = ["--source", self.source, "--commit", "abc123", "--audio-dir", out_dir, "--toml", toml_path,
                "--log", log_path]
        self.assertEqual(audio.main(args), 0)
        self.assertEqual(sorted(os.listdir(out_dir)), ["beh__lettername.caf", "beh_fathah.caf"])
        with open(toml_path, "rb") as f:
            data = tomllib.load(f)
        self.assertEqual(data["source"]["commit"], "abc123")
        self.assertEqual([(c["letter"], c["kind"], c["file"]) for c in data["clip"]],
                         [("ب", "name", "beh__lettername.caf"), ("ب", "fatha", "beh_fathah.caf")])
        with open(log_path, encoding="utf-8") as f:
            log = f.read()
        self.assertIn("| `waw_diph.wav` | — | defer |", log)
        self.assertIn("UNVERIFIED", log)
        first = self.read_all(out_dir)
        self.assertEqual(audio.main(args), 0)
        second = self.read_all(out_dir)
        self.assertEqual(first, second, "re-importing gives the same bytes")


if __name__ == "__main__":
    unittest.main()
