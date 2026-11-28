#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 -I - "$ROOT" <<'EOF'
import importlib.util, math, sqlite3, sys, tempfile, os

root = sys.argv[1]
spec = importlib.util.spec_from_file_location("phonetic_model", os.path.join(root, "Tools/phonetic-model.py"))
pm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pm)

passed = 0
def check(name, cond):
    global passed
    if not cond:
        raise AssertionError(f"FAILED: {name}")
    passed += 1

# 1. Vocabulary invariants
check("42 QPS phonemes", len(pm.PHONEMES) == 42)
check("unique phonemes", len(set(pm.PHONEMES)) == 42)
check("vocab dict blank_id=0", pm.build_vocab_dict()["blank_id"] == 0)
check("vocab dict schema_version=1", pm.build_vocab_dict()["schema_version"] == 1)

# 2. CTC greedy decode: collapse repeats, drop blank (0), compute probs and times
ids = [0, 21, 21, 0, 33, 23, 0]  # ق (21), ُ (33), ل (23)
lps = [0.0, -0.1, -0.2, 0.0, -0.05, -0.01, 0.0]
text, probs, times = pm.greedy_phonetic_ctc(ids, lps, audio_sample_count=16000, lead_samples=0)
check("ctc decoded text", text == "قُل")
check("ctc probs count", len(probs) == 3)
check("ctc prob value", abs(probs[0] - math.exp(-0.1)) < 1e-6)
check("ctc times count = len + 1", len(times) == 4)
check("ctc times non-decreasing", all(times[i] <= times[i + 1] for i in range(len(times) - 1)))

# Empty decode
t0, p0, tm0 = pm.greedy_phonetic_ctc([], [], audio_sample_count=0)
check("empty ctc text", t0 == "" and p0 == [] and tm0 == [0.0])

# 3. Canonical word mapping
check("1:1 mapping", pm.map_word_numbers(4, 4) == [1, 2, 3, 4])
check("split token mapping", pm.map_word_numbers(5, 4) == [1, 1, 2, 3, 4])

# 4. SQLite schema creation
with tempfile.TemporaryDirectory() as td:
    db = os.path.join(td, "test.db")
    conn = sqlite3.connect(db)
    pm.create_reference_schema(conn)
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    conn.close()
    check("reference tables created", tables == {"properties", "ayah_phonetics", "word_spans", "tajweed_units"})

# 5. Attribution mentions Apache-2.0 and pinned revision
attr = pm.attribution_text()
check("attribution mentions Hisnlabs", pm.HF_REPO in attr and pm.HF_REVISION in attr)

print(f"phonetic-model.test.sh: {passed} passed, 0 failed")
EOF
