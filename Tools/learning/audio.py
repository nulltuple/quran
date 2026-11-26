#!/usr/bin/env python3
"""Auditions and imports Arabican's letter recordings (Antura, CC-BY-4.0).

Arabican is the Arabic learning app (App Store Connect "Arabican"), not the Quran reader. Input: a
folder of Antura's `Assets/_lang_bundles/arabic/Audio/Letters/*.wav` (16-bit PCM). For every file
the tool writes one audition decision:

- accept: the file maps to a clip Arabican uses and passes the technical checks;
- reject: it maps to a clip we use but fails a check (too short or long, too quiet, clipped, a
  duplicate of another file);
- defer: it is not used yet (tanwin, shaddah, lam-alif, diphthongs, mark names, alif with a vowel).

Accepted files are trimmed (leading and trailing silence), peak-normalized and converted to AAC
with macOS `afconvert` (.caf) into ArabicLearning/Sources/LearningContent/Resources/Audio/. The tool
writes Tools/learning/content/audio.toml (the clip list the content compiler reads) and the
audition log Documentation/ArabicLearning/04-audio-audition.md.

The checks are technical only. Whether the articulation is right for Quranic recitation needs a
qualified listener (spec 03, risk 2); the log says so.

Usage:
  python3 -I Tools/learning/audio.py --source <folder of Antura wavs> --commit <Antura commit>
"""

import argparse
import array
import hashlib
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULTS = {
    "audio_dir": os.path.join(ROOT, "ArabicLearning/Sources/LearningContent/Resources/Audio"),
    "toml": os.path.join(HERE, "content", "audio.toml"),
    "log": os.path.join(ROOT, "Documentation/ArabicLearning/04-audio-audition.md"),
}
SOURCE_PATH = "Assets/_lang_bundles/arabic/Audio/Letters"
REPOSITORY = "vgwb/Antura"

# Antura's letter keys, in Arabican's teaching order (letters.toml).
LETTER_KEYS = {
    "alef": "ا", "beh": "ب", "teh": "ت", "theh": "ث", "jeem": "ج", "hah": "ح", "khah": "خ",
    "dal": "د", "thal": "ذ", "reh": "ر", "zain": "ز", "seen": "س", "sheen": "ش", "sad": "ص",
    "dad": "ض", "tah": "ط", "zah": "ظ", "ain": "ع", "ghain": "غ", "feh": "ف", "qaf": "ق",
    "kaf": "ك", "lam": "ل", "meem": "م", "noon": "ن", "heh": "ه", "waw": "و", "yeh": "ي",
    "hamza": "ء",
}
VOWELS = {"fathah": "fatha", "kasrah": "kasra", "dammah": "damma", "sukun": "sukun"}
# Hamza has no vowel recordings of its own; Antura records it on an alif seat, which sounds the same.
HAMZA_ON_ALIF = {"alef_hamza_hi_fathah": "fatha", "alef_hamza_hi_dammah": "damma", "alef_hamza_low_kasrah": "kasra"}
KINDS = ("name", "fatha", "kasra", "damma", "sukun")

MIN_SECONDS = 0.15
MAX_SECONDS = 3.0
MIN_PEAK_DBFS = -30.0
MAX_CLIPPED_FRACTION = 0.001
SILENCE_DBFS = -45.0
PAD_SECONDS = 0.03
TARGET_PEAK_DBFS = -3.0
AAC_BITRATE = 64000


def classify(stem):
    """(letter, kind, note) for a clip Arabican uses, or (None, None, reason) to defer the file."""
    if stem in HAMZA_ON_ALIF:
        return "ء", HAMZA_ON_ALIF[stem], "hamza recorded on an alif seat (same sound)"
    if stem.endswith("__lettername"):
        key = stem[: -len("__lettername")]
        if key in LETTER_KEYS:
            return LETTER_KEYS[key], "name", ""
        return None, None, "name of a mark or letter variant, not taught yet"
    key, _, vowel = stem.rpartition("_")
    if key in LETTER_KEYS and vowel in VOWELS:
        if key == "alef":
            return None, None, "alif carries no vowel of its own; the label is ambiguous"
        return LETTER_KEYS[key], VOWELS[vowel], ""
    return None, None, "tanwin, shaddah, lam-alif or diphthong: taught from L4"


def read_wav(path):
    with wave.open(path, "rb") as f:
        if f.getsampwidth() != 2:
            raise ValueError(f"{path}: expected 16-bit PCM")
        channels, rate = f.getnchannels(), f.getframerate()
        samples = array.array("h", f.readframes(f.getnframes()))
    if sys.byteorder == "big":
        samples.byteswap()
    if channels > 1:
        samples = array.array("h", (int(sum(samples[i:i + channels]) / channels)
                                    for i in range(0, len(samples), channels)))
    return samples, rate


def dbfs(value):
    return 20 * math.log10(value / 32768) if value > 0 else -math.inf


def voiced_range(samples, rate):
    """[start, end) of the samples above the silence threshold, padded; (0, 0) when all silent."""
    threshold = 32768 * 10 ** (SILENCE_DBFS / 20)
    loud = [i for i, s in enumerate(samples) if abs(s) > threshold]
    if not loud:
        return 0, 0
    pad = int(PAD_SECONDS * rate)
    return max(0, loud[0] - pad), min(len(samples), loud[-1] + 1 + pad)


def measure(samples, rate):
    start, end = voiced_range(samples, rate)
    peak = max((abs(s) for s in samples), default=0)
    clipped = sum(1 for s in samples if s in (32767, -32768))
    return {
        "seconds": len(samples) / rate,
        "voiced_seconds": (end - start) / rate,
        "peak_dbfs": dbfs(peak),
        "clipped_fraction": clipped / len(samples) if samples else 0.0,
        "start": start,
        "end": end,
    }


def technical_problems(metrics):
    problems = []
    if metrics["voiced_seconds"] < MIN_SECONDS:
        problems.append(f"voiced part {metrics['voiced_seconds']:.2f} s is shorter than {MIN_SECONDS} s")
    if metrics["voiced_seconds"] > MAX_SECONDS:
        problems.append(f"voiced part {metrics['voiced_seconds']:.2f} s is longer than {MAX_SECONDS} s")
    if metrics["peak_dbfs"] < MIN_PEAK_DBFS:
        problems.append(f"peak {metrics['peak_dbfs']:.1f} dBFS is quieter than {MIN_PEAK_DBFS} dBFS")
    if metrics["clipped_fraction"] > MAX_CLIPPED_FRACTION:
        problems.append(f"{metrics['clipped_fraction']:.2%} of samples clipped")
    return problems


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def audition(source):
    """One decision per .wav in `source`, sorted by file name."""
    decisions = []
    seen_audio = {}
    for name in sorted(n for n in os.listdir(source) if n.endswith(".wav")):
        path = os.path.join(source, name)
        stem = name[:-4]
        letter, kind, note = classify(stem)
        samples, rate = read_wav(path)
        metrics = measure(samples, rate)
        audio_hash = hashlib.sha256(samples.tobytes()).hexdigest()
        decision = {"file": name, "stem": stem, "sha256": sha256_file(path), "letter": letter, "kind": kind,
                    "metrics": metrics, "rate": rate}
        if letter is None:
            decision.update(decision="defer", reason=note)
        else:
            problems = technical_problems(metrics)
            if audio_hash in seen_audio:
                problems.append(f"same samples as {seen_audio[audio_hash]}")
            decision.update(decision="reject" if problems else "accept", reason="; ".join(problems or [note]))
        seen_audio.setdefault(audio_hash, name)
        decisions.append(decision)
    clip_ids = {}
    for decision in decisions:
        if decision["decision"] == "accept":
            clip_id = f"{decision['letter']}.{decision['kind']}"
            if clip_id in clip_ids:
                decision.update(decision="reject", reason=f"second recording of {clip_id} (kept {clip_ids[clip_id]})")
            else:
                clip_ids[clip_id] = decision["file"]
    return decisions


def write_trimmed_wav(samples, rate, metrics, out):
    voiced = samples[metrics["start"]:metrics["end"]]
    peak = max((abs(s) for s in voiced), default=0)
    gain = (32767 * 10 ** (TARGET_PEAK_DBFS / 20)) / peak if peak else 1.0
    scaled = array.array("h", (max(-32768, min(32767, round(s * gain))) for s in voiced))
    if sys.byteorder == "big":
        scaled.byteswap()
    with wave.open(out, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(scaled.tobytes())


def convert(source, decisions, audio_dir):
    """Writes one .caf per accepted decision into `audio_dir`, replacing what was there. AAC in a Core
    Audio file is byte-for-byte reproducible; afconvert stamps .m4a files with the time."""
    if os.path.isdir(audio_dir):
        shutil.rmtree(audio_dir)
    os.makedirs(audio_dir)
    with tempfile.TemporaryDirectory() as scratch:
        for decision in decisions:
            if decision["decision"] != "accept":
                continue
            samples, rate = read_wav(os.path.join(source, decision["file"]))
            trimmed = os.path.join(scratch, decision["file"])
            write_trimmed_wav(samples, rate, decision["metrics"], trimmed)
            out = os.path.join(audio_dir, decision["stem"] + ".caf")
            subprocess.run(["afconvert", "-f", "caff", "-d", "aac", "-b", str(AAC_BITRATE), trimmed, out],
                           check=True, capture_output=True)
            decision["output"] = os.path.basename(out)


def toml_text(decisions, commit):
    lines = [
        "# Generated by Tools/learning/audio.py from Antura's letter recordings; do not edit by hand.",
        f"# Source: https://github.com/{REPOSITORY} at {commit}, {SOURCE_PATH} (CC-BY-4.0).",
        "# Audition log: Documentation/ArabicLearning/04-audio-audition.md.",
        "",
        "[source]",
        f'repository = "{REPOSITORY}"',
        f'commit = "{commit}"',
        f'path = "{SOURCE_PATH}"',
        'license = "CC-BY-4.0"',
    ]
    for decision in decisions:
        if decision["decision"] != "accept":
            continue
        lines += [
            "",
            "[[clip]]",
            f'letter = "{decision["letter"]}"',
            f'kind = "{decision["kind"]}"',
            f'file = "{decision["output"]}"',
            f'source_file = "{decision["file"]}"',
            f'source_sha256 = "{decision["sha256"]}"',
        ]
    return "\n".join(lines) + "\n"


def log_text(decisions, commit):
    counts = {d: sum(1 for x in decisions if x["decision"] == d) for d in ("accept", "reject", "defer")}
    lines = [
        "# 04 · Letter audio audition (Arabican)",
        "",
        "Generated by `python3 -I Tools/learning/audio.py`; do not edit by hand. Arabican app only.",
        "",
        f"- **Source:** [{REPOSITORY}](https://github.com/{REPOSITORY}) at `{commit}`, `{SOURCE_PATH}/*.wav`, "
        "CC-BY-4.0 (human recordings, children's-game MSA narration).",
        f"- **Result:** {len(decisions)} files: {counts['accept']} accept, {counts['reject']} reject, "
        f"{counts['defer']} defer (not used before L4).",
        f"- **Checks (technical, automated):** voiced length {MIN_SECONDS}–{MAX_SECONDS} s (silence below "
        f"{SILENCE_DBFS:.0f} dBFS trimmed, {PAD_SECONDS * 1000:.0f} ms kept), peak at least {MIN_PEAK_DBFS:.0f} dBFS, "
        f"at most {MAX_CLIPPED_FRACTION:.1%} clipped samples, no duplicate recordings. Accepted clips are "
        f"normalized to {TARGET_PEAK_DBFS:.0f} dBFS peak and stored as AAC {AAC_BITRATE // 1000} kbps in .caf files.",
        "- **Not verified (UNVERIFIED):** articulation. No person has listened to these clips for Quranic "
        "pronunciation (ض ظ ق ع ح and the emphatic letters especially). A qualified listener must review every "
        "accepted clip before any public release (spec 03, risk 2); replace a clip by rejecting it here.",
        "",
        "| File | Clip | Decision | Voiced s | Peak dBFS | Reason |",
        "|---|---|---|---|---|---|",
    ]
    for d in decisions:
        clip = f"{d['letter']}.{d['kind']}" if d["letter"] else "—"
        m = d["metrics"]
        lines.append(f"| `{d['file']}` | {clip} | {d['decision']} | {m['voiced_seconds']:.2f} | "
                     f"{m['peak_dbfs']:.1f} | {d['reason'] or '—'} |")
    return "\n".join(lines) + "\n"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", required=True, help="folder of Antura letter .wav files")
    parser.add_argument("--commit", required=True, help="the Antura commit the files came from")
    parser.add_argument("--audio-dir", default=DEFAULTS["audio_dir"])
    parser.add_argument("--toml", default=DEFAULTS["toml"])
    parser.add_argument("--log", default=DEFAULTS["log"])
    args = parser.parse_args(argv)
    decisions = audition(args.source)
    convert(args.source, decisions, args.audio_dir)
    with open(args.toml, "w", encoding="utf-8") as f:
        f.write(toml_text(decisions, args.commit))
    with open(args.log, "w", encoding="utf-8") as f:
        f.write(log_text(decisions, args.commit))
    accepted = sum(1 for d in decisions if d["decision"] == "accept")
    print(f"auditioned {len(decisions)} files, imported {accepted} clips into {args.audio_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
