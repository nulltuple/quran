#!/bin/bash
#
# Tests the standard-library helpers of Tools/recitation-model.py (normalization, error rates, the
# reference matcher, CTC decoding, windows, sampling, the app database reader).
# `convert` and `eval` need PyTorch and Core ML tools; the V0 trail records their parity checks.
# Run: bash Tools/recitation-model.test.sh (or make test-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 -I - "$ROOT/Tools/recitation-model.py" "$ROOT/Domain/QuranResources/Sources/Databases/quran.ar.uthmani.v2.db" <<'PY'
import importlib.util, sys

spec = importlib.util.spec_from_file_location("tool", sys.argv[1])
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

passed = failed = 0
def check(description, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"ok - {description}")
    else:
        failed += 1
        print(f"not ok - {description} {detail}")

# Normalization matches RecitationRecognition's ArabicMatchNormalizer.
check("normalize strips marks and folds letters", tool.normalize("قُلْ هُوَ ٱللَّهُ أَحَدٌ") == "قل هو الله احد")
check("normalize drops BOM, tatweel, annotations and punctuation",
      tool.normalize("﻿رَزَقۡنَـٰهُمۡ ۚ النجوم.") == "رزقنهم النجوم", tool.normalize("﻿رَزَقۡنَـٰهُمۡ ۚ النجوم."))
check("normalize folds ta marbuta and alef maqsura", tool.normalize("صلاة على") == "صلاه علي")

check("levenshtein of strings", tool.levenshtein("kitten", "sitting") == 3)
check("levenshtein of word lists", tool.levenshtein(["a", "b", "c"], ["a", "c"]) == 1)
check("ratio of empty strings is 1", tool.ratio("", "") == 1.0)
ce, cn, we, wn = tool.error_rates("قل هو الله احت", "قُلْ هُوَ ٱللَّهُ أَحَدٌ")
check("error rates count one letter and one word", (ce, cn, we, wn) == (1, 11, 1, 4), (ce, cn, we, wn))

vocab = {"0": "<unk>", "1": "▁قل", "2": "▁هو", "3": "ل", "4": "_"}
check("greedy CTC collapses repeats and drops blanks", tool.greedy_ctc([4, 1, 1, 4, 2, 4], vocab, blank=4) == "قل هو")
check("greedy CTC keeps a repeat split by a blank", tool.greedy_ctc([3, 4, 3], vocab, blank=4) == "لل")

check("windows cover a long clip", tool.windows(700_000) == [(0, 320_000), (320_000, 640_000), (640_000, 700_000)])
check("windows of a short clip", tool.windows(10) == [(0, 10)])

sample = tool.sample_verses(20, seed=1)
check("sampling is deterministic", sample == tool.sample_verses(20, seed=1))
check("sampling gives distinct valid verses", len(set(sample)) == 20 and all(1 <= a <= tool.AYAH_COUNTS[s - 1] for s, a in sample))
check("the Quran has 6,236 verses", sum(tool.AYAH_COUNTS) == 6236)

check("percentile picks the nearest rank", tool.percentile([5, 1, 3, 2, 4], 50) == 3 and tool.percentile([], 95) == 0.0)

verses = tool.load_quran_text(sys.argv[2])
check("the app database has every verse", len(verses) == 6236)
check("the app text is imla'i", verses["2:3"] == "الذين يؤمنون بالغيب ويقيمون الصلاه ومما رزقناهم ينفقون", verses["2:3"])
check("a sura's first verse has no basmala", verses["39:1"] == "تنزيل الكتاب من الله العزيز الحكيم", verses["39:1"])
check("1:1 is the basmala", verses["1:1"] == tool.BASMALA and verses["9:1"].startswith("براءه"))
check("the reference matcher counts identical texts", tool.rank_verses("تنزيل الكتاب من الله العزيز الحكيم", verses)[0] == "39:1")
check("the reference matcher ranks the recited verse first", tool.rank_verses("قل هو الله احد", verses)[0] == "112:1")
check("the reference matcher handles a misheard letter",
      tool.rank_verses("الحمد لله رب العالمين", verses)[0] == "1:2")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
