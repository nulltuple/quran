#!/usr/bin/env python3
"""Builds, packages and evaluates the on-device Quran phonetic assessment model (roadmap V4/V5).

The model is HisnLabs Tajweed v2 (https://huggingface.co/Hisnlabs/tajweed-v2, Apache-2.0): a
20.6M-parameter Whisper-base encoder (from tarteel-ai/whisper-base-ar-quran) with 11 multi-level
CTC heads distilled from obadx/muaalem-model-v3_2 (MIT). It outputs the 42-symbol Quran Phonetic
Script (QPS, obadx/quran-transcript) plus 10 sifat heads at 50 frames/s (20 ms/frame).

Commands:
  fetch      download Hisnlabs/tajweed-v2 weights and config at a pinned revision, checking sha256
  convert    convert the PyTorch checkpoint to a Core ML ML Program (float16 compute, int8 weights,
             dynamic mel length [1, 80, 4..3000]) plus vocab.json and ATTRIBUTION.txt
  build-ref  precompute deterministic Hafs expected QPS phonemes, canonical word spans and tajweed
             rule units for every ayah into a read-only SQLite database (quran_phonetics.db)
  package    create phonetic-model-1.zip containing the Core ML package, vocab.json,
             quran_phonetics.db and ATTRIBUTION.txt, printing its byte count and sha256
  eval       evaluate a Core ML package on obadx/qdat_bench (159 learner clips, human labels)

Pure helpers above `# MARK: - fetch` use only the Python standard library and are tested by
Tools/phonetic-model.test.sh (`make test-tools`).
"""

import argparse
import hashlib
import io
import json
import math
import os
import sqlite3
import subprocess
import sys
import time
import urllib.request
import zipfile

HF_REPO = "Hisnlabs/tajweed-v2"
HF_REVISION = "b3b0503d32b4d9a8a0447880b4564fd3e9d69c15"
ASSETS = {
    "config.json": "f1351c5753a77061eb1788b0e4e8863a6e197f0a56ace0adffd2cae6db43f369",
    "model.safetensors": "d623f5f05fe82d4a68d3435ea04a552117d575ccc39fe873867ba99a1ab35432",
}
QDAT_REPO = "obadx/qdat_bench"
QDAT_REVISION = "8003b22ece41b26ea65e0dd71843e5943686a4fa"
QDAT_FILE = "data/train-00000-of-00001.parquet"
QDAT_SHA256 = "43c97ce819a04a34ea54a54805f44850b6987defef69885f265819137658c2ca"

SAMPLE_RATE = 16_000
LEAD_SAMPLES = 6_400  # 0.4 s silence before and after clip (matches HisnLabs training)
MAX_MEL_FRAMES = 3_000  # 30 s at 100 mel frames/s -> 1500 CTC frames at 50 fps

# The 42-symbol Quran Phonetic Script alphabet (index 0 is CTC blank; indices 1..42 follow).
PHONEMES = [
    "ء", "ب", "ت", "ث", "ج", "ح", "خ", "د", "ذ", "ر", "ز", "س", "ش", "ص", "ض", "ط", "ظ",
    "ع", "غ", "ف", "ق", "ك", "ل", "م", "ن", "ه", "و", "ي", "ا", "ۦ", "ۥ", "َ", "ُ", "ِ",
    "۪", "ـ", "ٲ", "ڇ", "ں", "۾", "ۜ", "ؙ",
]
SIFAT_VOCAB = {
    "qalqla": ["moqalqal", "not_moqalqal"],
    "ghonna": ["maghnoon", "not_maghnoon"],
    "tafkheem_or_taqeeq": ["mofakham", "moraqaq", "low_mofakham"],
}
ALL_SIFAT_SIZES = {
    "hams_or_jahr": 2, "shidda_or_rakhawa": 3, "tafkheem_or_taqeeq": 3, "itbaq": 2,
    "safeer": 2, "qalqla": 2, "tikraar": 2, "tafashie": 2, "istitala": 2, "ghonna": 2,
}
LONG_VOWELS = {"ا", "ۥ", "ۦ"}
HARAKAT = set("َُِ")
NASAL = set("نم")
MADD_RULES = {
    "NormalMaddRule", "MonfaselMaddRule", "MottaselMaddRule", "MottaselMaddPauseRule",
    "LazemMaddRule", "AaredMaddRule", "LeenMaddRule",
}
MOSHAF_DEFAULTS = {
    "rewaya": "hafs",
    "madd_monfasel_len": 4,
    "madd_mottasel_len": 4,
    "madd_mottasel_waqf": 4,
    "madd_aared_len": 4,
}
SCHEMA_VERSION = 1

# MARK: - Pure helpers (standard library only)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def greedy_phonetic_ctc(frame_ids, frame_max_log_probs, audio_sample_count, phonemes=PHONEMES, lead_samples=LEAD_SAMPLES):
    """Collapses repeated frame ids, drops blank (0), returns (text, probs, center_times_with_end)."""
    if not frame_ids:
        return "", [], [0.0]
    step = audio_sample_count / float(SAMPLE_RATE) / float(len(frame_ids))
    lead_sec = lead_samples / float(SAMPLE_RATE)
    out, probs, times = [], [], []
    prev = 0
    last_non_blank = -1
    for t, token in enumerate(frame_ids):
        if token != 0:
            last_non_blank = t
        if token != prev and token != 0:
            out.append(phonemes[token - 1])
            probs.append(math.exp(frame_max_log_probs[t]))
            times.append((t + 0.5) * step - lead_sec)
        prev = token
    end_time = ((last_non_blank + 1) * step - lead_sec) if last_non_blank >= 0 else 0.0
    times.append(end_time)
    return "".join(out), probs, times


def map_word_numbers(qt_word_count, canonical_word_count):
    """Maps 0-based quran-transcript word indices to 1-based canonical word numbers.
    Matches 1:1 on 6,235/6,236 ayahs. When qt_word_count == canonical_word_count + 1 (e.g.
    37:130 where Tanzil splits إل ياسين into 2 tokens for 1 canonical word), clamps trailing
    tokens gracefully; caller may also supply explicit canonical mapping."""
    if canonical_word_count <= 0 or qt_word_count == canonical_word_count:
        return list(range(1, qt_word_count + 1))
    result = []
    for i in range(qt_word_count):
        mapped = min(canonical_word_count, int(i * canonical_word_count / qt_word_count) + 1)
        result.append(mapped)
    return result


def create_reference_schema(connection):
    connection.executescript("""
        CREATE TABLE properties (
            property TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE ayah_phonetics (
            sura INTEGER NOT NULL,
            ayah INTEGER NOT NULL,
            phonemes TEXT NOT NULL,
            PRIMARY KEY (sura, ayah)
        );
        CREATE TABLE word_spans (
            sura INTEGER NOT NULL,
            ayah INTEGER NOT NULL,
            word_index INTEGER NOT NULL,
            word_number INTEGER NOT NULL,
            text TEXT NOT NULL,
            start_idx INTEGER NOT NULL,
            end_idx INTEGER NOT NULL,
            PRIMARY KEY (sura, ayah, word_index)
        );
        CREATE TABLE tajweed_units (
            sura INTEGER NOT NULL,
            ayah INTEGER NOT NULL,
            unit_index INTEGER NOT NULL,
            word_index INTEGER NOT NULL,
            kind TEXT NOT NULL,
            rule TEXT NOT NULL,
            start_idx INTEGER NOT NULL,
            end_idx INTEGER NOT NULL,
            golden INTEGER NOT NULL,
            char TEXT NOT NULL,
            PRIMARY KEY (sura, ayah, unit_index)
        );
    """)


def extract_units_from_phonetizer(words, phonemes, mappings):
    """Extracts per-word spans and Hafs tajweed rule units (mirroring HisnLabs imam.py expected())."""
    spans, pos = [], 0
    for word in words:
        ps = [m.pos for m in mappings[pos:pos + len(word)] if m.pos[1] > m.pos[0]]
        if ps:
            spans.append((min(p[0] for p in ps), max(p[1] for p in ps)))
        else:
            fallback = spans[-1][1] if spans else 0
            spans.append((fallback, fallback))
        pos += len(word) + 1

    def word_at(idx):
        for k, (a, b) in enumerate(spans):
            if a <= idx < b:
                return k
        return max(0, len(spans) - 1)

    offsets = []
    cur = 0
    for w in words:
        offsets.append(cur)
        cur += len(w) + 1
    vanishing = [
        any(m.deleted for m in mappings[p0:p0 + len(w)][-3:])
        and (w.rstrip("ْۡ").endswith("ن") or any(c in w for c in "ًࣰٌࣱٍࣲ"))
        for w, p0 in zip(words, offsets)
    ]

    units, ruled = [], set()
    for m in mappings:
        for r in m.tajweed_rules or []:
            a, b = m.pos
            name = type(r).__name__
            if name in MADD_RULES:
                seg = phonemes[a:b]
                c = next((ch for ch in seg if ch in LONG_VOWELS), None) or (seg[0] if name == "LeenMaddRule" and seg else None)
                if c is None:
                    continue
                j = seg.index(c)
                k = j
                while k < len(seg) and seg[k] == c:
                    k += 1
                golden = (k - j) + (1 if name == "LeenMaddRule" else 0)
                units.append((a + j, a + k, "madd", name, word_at(a), golden, c))
                ruled.update(range(a + j, a + k))
            elif name == "Qalqalah":
                q = phonemes.find("ڇ", a, b)
                if q >= 0:
                    units.append((q, q + 1, "qalqalah", "Qalqalah", word_at(q), 1, "ڇ"))
                    ruled.add(q)

    i = 0
    while i < len(phonemes):
        j = i
        while j < len(phonemes) and phonemes[j] == phonemes[i]:
            j += 1
        c, n, w = phonemes[i], j - i, word_at(i)
        if i not in ruled:
            if c == "ں":
                units.append((i, j, "ikhfa", "Ikhfa", w, n, c))
            elif c == "۾":
                units.append((i, j, "iqlab", "Iqlab", w, n, c))
            elif c in NASAL and n >= 3:
                prev_w = word_at(i - 1) if i else w
                kind = "idgham_ghunnah" if (prev_w != w and vanishing[prev_w]) else "ghunnah"
                units.append((i, j, kind, kind, prev_w if kind == "idgham_ghunnah" else w, n, c))
            elif c in "يو" and n >= 3:
                units.append((i, j, "idgham_ghunnah", "idgham_ghunnah", w, n, c))
            elif c not in LONG_VOWELS and c not in HARAKAT and n == 2:
                prev_w = word_at(i - 1) if i else w
                if i == spans[w][0] and prev_w != w and vanishing[prev_w]:
                    units.append((i, j, "idgham", "Idgham", prev_w, 2, c))
                else:
                    units.append((i, j, "shadda", "Shadda", w, 2, c))
        i = j

    units.sort(key=lambda u: u[0])
    return spans, units


def build_vocab_dict():
    return {
        "schema_version": SCHEMA_VERSION,
        "model": f"{HF_REPO}@{HF_REVISION}",
        "license": "Apache-2.0",
        "blank_id": 0,
        "sample_rate": SAMPLE_RATE,
        "lead_samples": LEAD_SAMPLES,
        "samples_per_frame": 320,  # 50 frames/s = 20 ms/frame
        "max_mel_frames": MAX_MEL_FRAMES,
        "phonemes": PHONEMES,
        "sifat": SIFAT_VOCAB,
    }


def attribution_text():
    return (
        "Quran Phonetic & Tajweed Assessment Model (phonetic-model-1)\n"
        "=============================================================\n\n"
        f"Acoustic model: HisnLabs Tajweed v2 ({HF_REPO}@{HF_REVISION})\n"
        "License: Apache-2.0\n"
        "Base encoder: tarteel-ai/whisper-base-ar-quran (Apache-2.0)\n"
        "Distilled from: obadx/muaalem-model-v3_2 (MIT, arXiv:2509.00094)\n"
        "Phonetic script & reference phonetizer: obadx/quran-transcript (MIT)\n"
        "Rule engine design adapted from: HisnLabs/tajweed imam.py (Apache-2.0)\n"
    )


# MARK: - fetch


def fetch(model_dir):
    os.makedirs(model_dir, exist_ok=True)
    for name, expected in ASSETS.items():
        path = os.path.join(model_dir, name)
        if not os.path.exists(path) or sha256(path) != expected:
            url = f"https://huggingface.co/{HF_REPO}/resolve/{HF_REVISION}/{name}"
            print(f"downloading {url}")
            urllib.request.urlretrieve(url, path + ".part")
            os.replace(path + ".part", path)
        actual = sha256(path)
        if actual != expected:
            sys.exit(f"{name}: sha256 {actual}, expected {expected}")
        print(f"{name}: ok ({os.path.getsize(path):,} bytes)")


# MARK: - convert


def convert(model_dir, output_dir):
    import coremltools as ct
    import coremltools.optimize.coreml as cto
    import numpy as np
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
    from safetensors.torch import load_file
    from transformers import WhisperConfig
    from transformers.models.whisper.modeling_whisper import WhisperEncoder

    class _HifzStudent(nn.Module):
        def __init__(self, enc):
            super().__init__()
            self.enc = enc
            d = enc.config.d_model
            sizes = {"phonemes": len(PHONEMES), **ALL_SIFAT_SIZES}
            self.heads = nn.ModuleDict({lv: nn.Linear(d, n + 1) for lv, n in sizes.items()})
            self.riwaya = nn.Embedding(2, d)

    class _CoreMLWrapper(nn.Module):
        def __init__(self, student):
            super().__init__()
            self.conv1 = student.enc.conv1
            self.conv2 = student.enc.conv2
            self.register_buffer("pos_emb", student.enc.embed_positions.weight.detach().clone().unsqueeze(0))
            self.register_buffer("riwaya_hafs", student.riwaya.weight[0:1].detach().clone().unsqueeze(0))
            self.layers = student.enc.layers
            self.layer_norm = student.enc.layer_norm
            self.head_phonemes = student.heads["phonemes"]
            self.head_qalqla = student.heads["qalqla"]
            self.head_ghonna = student.heads["ghonna"]
            self.head_tafkheem = student.heads["tafkheem_or_taqeeq"]

        def forward(self, mel):
            x = F.gelu(self.conv1(mel))
            x = F.gelu(self.conv2(x)).transpose(1, 2)
            x = x + self.pos_emb[:, :x.shape[1], :] + self.riwaya_hafs
            for layer in self.layers:
                residual = x
                h = layer.self_attn_layer_norm(x)
                q = layer.self_attn.q_proj(h).reshape(1, -1, 8, 64).transpose(1, 2) * (64.0 ** -0.5)
                k = layer.self_attn.k_proj(h).reshape(1, -1, 8, 64).transpose(1, 2)
                v = layer.self_attn.v_proj(h).reshape(1, -1, 8, 64).transpose(1, 2)
                attn = F.softmax(torch.matmul(q, k.transpose(-2, -1)), dim=-1)
                out = torch.matmul(attn, v).transpose(1, 2).reshape(1, -1, 512)
                x = residual + layer.self_attn.out_proj(out)
                residual = x
                h = layer.final_layer_norm(x)
                x = residual + layer.fc2(F.gelu(layer.fc1(h)))
            h = self.layer_norm(x)
            return (
                F.log_softmax(self.head_phonemes(h), dim=-1),
                F.log_softmax(self.head_qalqla(h), dim=-1),
                F.log_softmax(self.head_ghonna(h), dim=-1),
                F.log_softmax(self.head_tafkheem(h), dim=-1),
            )

    cfg = WhisperConfig(
        d_model=512, encoder_layers=6, encoder_attention_heads=8, encoder_ffn_dim=2048,
        num_mel_bins=80, max_source_positions=1500, activation_function="gelu",
    )
    student = _HifzStudent(WhisperEncoder(cfg))
    student.load_state_dict(load_file(os.path.join(model_dir, "model.safetensors")), strict=True)
    wrapper = _CoreMLWrapper(student).eval()
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, torch.zeros(1, 80, 400))

    os.makedirs(output_dir, exist_ok=True)
    shape = ct.Shape(shape=(1, 80, ct.RangeDim(lower_bound=4, upper_bound=MAX_MEL_FRAMES, default=400)))
    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS18,
        inputs=[ct.TensorType("mel", shape=shape, dtype=np.float32)],
        outputs=[
            ct.TensorType("phoneme_log_probs", dtype=np.float32),
            ct.TensorType("qalqalah_log_probs", dtype=np.float32),
            ct.TensorType("ghunnah_log_probs", dtype=np.float32),
            ct.TensorType("tafkheem_log_probs", dtype=np.float32),
        ],
    )
    quant_cfg = cto.OpLinearQuantizerConfig(
        mode="linear_symmetric", dtype="int8", granularity="per_channel", weight_threshold=2048,
    )
    mlmodel = cto.linear_quantize_weights(mlmodel, cto.OptimizationConfig(global_config=quant_cfg))
    mlmodel.short_description = (
        f"Quran phonetic & tajweed CTC model: HisnLabs Tajweed v2 (Apache-2.0, {HF_REPO}@{HF_REVISION}), "
        "distilled from obadx/muaalem-model-v3_2."
    )
    pkg_path = os.path.join(output_dir, "HisnLabsTajweedV2Int8.mlpackage")
    mlmodel.save(pkg_path)
    with open(os.path.join(output_dir, "vocab.json"), "w", encoding="utf-8") as f:
        json.dump(build_vocab_dict(), f, ensure_ascii=False, indent=2)
    with open(os.path.join(output_dir, "ATTRIBUTION.txt"), "w", encoding="utf-8") as f:
        f.write(attribution_text())
    size_mb = sum(os.path.getsize(os.path.join(r, fn)) for r, _, fs in os.walk(pkg_path) for fn in fs) / 1_048_576
    print(f"saved {pkg_path} ({size_mb:.2f} MB), vocab.json, ATTRIBUTION.txt")


# MARK: - build-ref


def build_ref(output_db, wbw_db=None, suras=None, quran_db=None):
    from quran_transcript import Aya, MoshafAttributes, quran_phonetizer

    moshaf = MoshafAttributes(**MOSHAF_DEFAULTS)
    wbw_counts = {}
    if wbw_db and os.path.exists(wbw_db):
        with sqlite3.connect(f"file:{wbw_db}?mode=ro", uri=True) as conn:
            for s, a, cnt in conn.execute("SELECT sura, ayah, COUNT(*) FROM word_meanings GROUP BY sura, ayah"):
                wbw_counts[(s, a)] = cnt

    if quran_db and os.path.exists(quran_db):
        with sqlite3.connect(f"file:{quran_db}?mode=ro", uri=True) as conn:
            ayah_keys = conn.execute("SELECT sura, ayah FROM arabic_text ORDER BY sura, ayah").fetchall()
    else:
        # Fallback: standard 114 suras using quran-transcript
        ayah_keys = []
        for s in range(1, 115):
            a = 1
            while True:
                try:
                    Aya(s, a).get()
                    ayah_keys.append((s, a))
                    a += 1
                except Exception:
                    break

    if suras:
        allowed = set(suras)
        ayah_keys = [(s, a) for s, a in ayah_keys if s in allowed]

    os.makedirs(os.path.dirname(os.path.abspath(output_db)), exist_ok=True)
    tmp_db = output_db + ".tmp"
    if os.path.exists(tmp_db):
        os.remove(tmp_db)

    t0 = time.perf_counter()
    conn = sqlite3.connect(tmp_db)
    create_reference_schema(conn)
    conn.executemany(
        "INSERT INTO properties(property, value) VALUES (?, ?)",
        [
            ("schema_version", str(SCHEMA_VERSION)),
            ("source", "obadx/quran-transcript (MIT)"),
            ("moshaf", json.dumps(MOSHAF_DEFAULTS, sort_keys=True)),
            ("ayah_count", str(len(ayah_keys))),
        ],
    )

    ayah_rows, word_rows, unit_rows = [], [], []
    for sura, ayah in ayah_keys:
        qt_text = Aya(sura, ayah).get().uthmani
        words = qt_text.split()
        out = quran_phonetizer(" ".join(words), moshaf, remove_spaces=True)
        spans, units = extract_units_from_phonetizer(words, out.phonemes, out.mappings)
        canonical_count = wbw_counts.get((sura, ayah), len(words))
        word_nums = map_word_numbers(len(words), canonical_count)
        ayah_rows.append((sura, ayah, out.phonemes))
        for idx, (word, (s_idx, e_idx), w_num) in enumerate(zip(words, spans, word_nums)):
            word_rows.append((sura, ayah, idx, w_num, word, s_idx, e_idx))
        for u_idx, (s_idx, e_idx, kind, rule, w_idx, golden, ch) in enumerate(units):
            unit_rows.append((sura, ayah, u_idx, w_idx, kind, rule, s_idx, e_idx, golden, ch))

    conn.executemany("INSERT INTO ayah_phonetics VALUES (?, ?, ?)", ayah_rows)
    conn.executemany("INSERT INTO word_spans VALUES (?, ?, ?, ?, ?, ?, ?)", word_rows)
    conn.executemany("INSERT INTO tajweed_units VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", unit_rows)
    conn.commit()
    conn.execute("VACUUM")
    conn.close()
    os.replace(tmp_db, output_db)
    dt = time.perf_counter() - t0
    print(
        f"built {output_db}: {len(ayah_rows)} ayahs, {len(word_rows)} words, {len(unit_rows)} units "
        f"({os.path.getsize(output_db):,} bytes, sha256={sha256(output_db)[:16]}...) in {dt:.1f}s"
    )


# MARK: - package


def package(output_dir, zip_path):
    required = ["HisnLabsTajweedV2Int8.mlpackage", "vocab.json", "quran_phonetics.db", "ATTRIBUTION.txt"]
    for item in required:
        full = os.path.join(output_dir, item)
        if not os.path.exists(full):
            sys.exit(f"missing required package item: {full}")
    os.makedirs(os.path.dirname(os.path.abspath(zip_path)), exist_ok=True)
    tmp = zip_path + ".tmp"
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for item in required:
            full = os.path.join(output_dir, item)
            if os.path.isdir(full):
                for root, dirs, files in os.walk(full):
                    dirs.sort()
                    for fn in sorted(files):
                        src = os.path.join(root, fn)
                        rel = os.path.relpath(src, output_dir)
                        zf.write(src, rel)
            else:
                zf.write(full, item)
    os.replace(tmp, zip_path)
    print(f"packaged {zip_path}: {os.path.getsize(zip_path):,} bytes, sha256={sha256(zip_path)}")


# MARK: - eval


def evaluate(model_path, qdat_parquet, compute_units):
    import coremltools as ct
    import Levenshtein
    import numpy as np
    import pyarrow.parquet as pq
    import soundfile as sf
    import torch

    def whisper_mel_filters(sr=SAMPLE_RATE, n_fft=400, n_mels=80):
        def hz_to_mel(f):
            f_sp, min_log_hz, logstep = 200.0 / 3, 1000.0, np.log(6.4) / 27.0
            f = np.asarray(f, dtype=np.float64)
            return np.where(f >= min_log_hz, min_log_hz / f_sp + np.log(np.maximum(f, 1e-10) / min_log_hz) / logstep, f / f_sp)
        def mel_to_hz(m):
            f_sp, min_log_hz, logstep = 200.0 / 3, 1000.0, np.log(6.4) / 27.0
            m = np.asarray(m, dtype=np.float64)
            return np.where(m >= min_log_hz / f_sp, min_log_hz * np.exp(logstep * (m - min_log_hz / f_sp)), f_sp * m)
        all_freqs = np.linspace(0, sr / 2, n_fft // 2 + 1)
        f_pts = mel_to_hz(np.linspace(hz_to_mel(0.0), hz_to_mel(8000.0), n_mels + 2))
        f_diff = np.diff(f_pts)
        slopes = f_pts[None, :] - all_freqs[:, None]
        fb = np.maximum(0.0, np.minimum(-slopes[:, :-2] / f_diff[:-1], slopes[:, 2:] / f_diff[1:]))
        fb *= (2.0 / (f_pts[2:n_mels + 2] - f_pts[:n_mels]))[None, :]
        return torch.from_numpy(fb.T.astype(np.float32))

    mel_fb = whisper_mel_filters()
    hann = torch.hann_window(400)
    ml = ct.models.MLModel(model_path, compute_units=getattr(ct.ComputeUnit, compute_units))
    rows = pq.read_table(qdat_parquet).to_pylist()
    edits = ref_len = 0
    latencies = []
    audio_secs = 0.0
    for r in rows:
        raw = r["audio"]["bytes"]
        data, sr = sf.read(io.BytesIO(raw), dtype="float32")
        if data.ndim > 1:
            data = data.mean(axis=1)
        if sr != SAMPLE_RATE:
            proc = subprocess.run(
                ["ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "f32le", "pipe:1"],
                input=raw, capture_output=True, check=True,
            )
            data = np.frombuffer(proc.stdout, dtype=np.float32)
        audio_secs += len(data) / float(SAMPLE_RATE)
        t0 = time.perf_counter()
        x = np.concatenate([np.zeros(LEAD_SAMPLES, np.float32), data.astype(np.float32), np.zeros(LEAD_SAMPLES, np.float32)])
        stft = torch.stft(torch.from_numpy(x), 400, 160, window=hann, return_complex=True)
        mel_spec = mel_fb @ (stft[..., :-1].abs() ** 2)
        log_spec = torch.clamp(mel_spec, min=1e-10).log10()
        log_spec = torch.maximum(log_spec, log_spec.max() - 8.0)
        mel = ((log_spec + 4.0) / 4.0).numpy()
        t_even = min(MAX_MEL_FRAMES, max(4, (mel.shape[1] // 2) * 2))
        lp = ml.predict({"mel": mel[:, :t_even][None]})["phoneme_log_probs"][0]
        ids = lp.argmax(-1).tolist()
        max_lp = [float(lp[t, i]) for t, i in enumerate(ids)]
        heard, _, _ = greedy_phonetic_ctc(ids, max_lp, len(x))
        latencies.append((time.perf_counter() - t0) * 1000.0)
        ref = r["phonetic_transcript"].replace(" ", "")
        edits += Levenshtein.distance(heard, ref)
        ref_len += len(ref)
    latencies.sort()
    p50 = latencies[len(latencies) // 2]
    p95 = latencies[min(len(latencies) - 1, int(0.95 * len(latencies)))]
    print(json.dumps({
        "clips": len(rows),
        "per": round(edits / max(1, ref_len), 4),
        "latency_ms_p50": round(p50, 1),
        "latency_ms_p95": round(p95, 1),
        "rtf": round((sum(latencies) / 1000.0) / max(1e-6, audio_secs), 4),
    }, indent=2))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("fetch").add_argument("model_dir")
    conv = sub.add_parser("convert")
    conv.add_argument("model_dir")
    conv.add_argument("output_dir")
    ref = sub.add_parser("build-ref")
    ref.add_argument("output_db")
    ref.add_argument("--wbw-db", default="Example/QuranEngineApp/Resources/word_by_word.db")
    ref.add_argument("--quran-db", default="Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db")
    ref.add_argument("--suras", help="comma-separated sura numbers to include (default: all 114)")
    pkg = sub.add_parser("package")
    pkg.add_argument("output_dir")
    pkg.add_argument("zip_path")
    ev = sub.add_parser("eval")
    ev.add_argument("--model", required=True)
    ev.add_argument("--qdat", required=True)
    ev.add_argument("--compute-units", default="CPU_ONLY", choices=["ALL", "CPU_ONLY", "CPU_AND_GPU", "CPU_AND_NE"])

    args = parser.parse_args(argv)
    if args.command == "fetch":
        fetch(args.model_dir)
    elif args.command == "convert":
        convert(args.model_dir, args.output_dir)
    elif args.command == "build-ref":
        suras = [int(x) for x in args.suras.split(",")] if args.suras else None
        build_ref(args.output_db, wbw_db=args.wbw_db, suras=suras, quran_db=args.quran_db)
    elif args.command == "package":
        package(args.output_dir, args.zip_path)
    else:
        evaluate(args.model, args.qdat, args.compute_units)


if __name__ == "__main__":
    main(sys.argv[1:])
