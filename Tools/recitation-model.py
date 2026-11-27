#!/usr/bin/env python3
"""Builds and evaluates the on-device Quran recitation model (roadmap V0).

The model is Tilawi's FastConformer CTC fine-tune for Quran recitation
(https://huggingface.co/muhdur/tilawi-fastconformer-quran, CC-BY-4.0, fine-tuned from NVIDIA's
stt_ar_fastconformer_hybrid_large_pcd_v1.0). It ships as one ONNX graph (raw 16 kHz audio in, CTC
log-probabilities over 1,025 SentencePiece tokens out, 80 ms a frame) with int4 MatMul and int8
convolution weights. iOS runs it through Core ML, which needs no third-party runtime:

  fetch     download the ONNX model and vocabulary at a pinned revision and check their sha256
  convert   dequantize the ONNX weights, fix the input to WINDOW_SAMPLES (20 s, zero padding masked
            by `length`), convert through PyTorch (onnx2torch) to a Core ML ML Program that computes
            in float32, then quantize its weights (int8 per channel for iOS 16, int4 per block of 32
            for iOS 18). Float16 compute is wrong on the CPU (the simulator's only Core ML device),
            so the model computes in float32; see the V0 trail.
  eval      sample EveryAyah verses with a fixed seed, transcribe them with a backend (`onnx` runs
            the original model through onnxruntime, `coreml` a converted package, `whisper` a Hugging
            Face Whisper model such as Tarteel's, through transformers), and report CER and
            WER against the app's imla'i verse text, verse identification top-1/top-5 with a simple
            reference matcher, latency and real-time factor. It writes every transcript, so the app's
            own matcher (RecitationRecognition) can be scored on the same clips.

Usage:
  recitation-model.py fetch <model-dir>
  recitation-model.py convert <model-dir> <output-dir>
  recitation-model.py eval --backend onnx|coreml|whisper --model <path or id> --vocab <vocab.json>
                           --quran-db <quran.ar.uthmani.v2.db> --cache <dir> --out <results.json>
                           [--reciter Husary_128kbps]... [--n 50] [--seed 1] [--compute-units ALL]

`convert` and `eval` need the packages in Tools/recitation-model-requirements.txt (Python 3.12, for
example `uv venv -p 3.12 venv && VIRTUAL_ENV=venv uv pip install -r <it>`) and ffmpeg for `eval`.
The helpers above `main` use only the standard library; Tools/recitation-model.test.sh tests them.
Run with `python3 -I`. Nothing about the user is sent anywhere: the tool downloads public files.
"""

import argparse
import hashlib
import json
import os
import random
import re
import sqlite3
import statistics
import subprocess
import sys
import time
import urllib.request

HF_REPO = "muhdur/tilawi-fastconformer-quran"
HF_REVISION = "e9448a0e84f3adb64c28b7a8db501dd8e0e59a84"  # main on 2026-11-26
ASSETS = {
    "fastconformer_full_mixed.onnx": "4767182cd92975869f81a7e32700b14ca2b04e8dc97a15ff220a8697f4639488",
    "vocab.json": "c55877f3bff8bc3aaefc160e8c2fb88cb349088d092513d40210ccfe535e671b",
}
SAMPLE_RATE = 16_000
WINDOW_SAMPLES = 20 * SAMPLE_RATE
BLANK_ID = 1024
EVERYAYAH = "https://everyayah.com/data"
# Verses per sura (EveryAyah's recitations.js lists the same counts).
AYAH_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53,
    89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12,
    12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26,
    30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
]

# MARK: - Text (mirrors RecitationRecognition's ArabicMatchNormalizer)

_DIACRITICS = re.compile(r"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]")
_FOLD = str.maketrans({
    "\u0623": "\u0627", "\u0625": "\u0627", "\u0622": "\u0627", "\u0671": "\u0627",
    "\u0629": "\u0647", "\u0649": "\u064A",
})
_NON_LETTER = re.compile(r"[^\u0621-\u064A\s]")


def normalize(text):
    """Arabic for matching: no BOM, marks or tatweel; folded alef, ta marbuta and alef maqsura;
    no punctuation; single spaces. Never used for displayed Quran text."""
    text = _DIACRITICS.sub("", text.replace("\ufeff", "")).translate(_FOLD)
    return " ".join(_NON_LETTER.sub("", text).split())


def levenshtein(a, b):
    """Edit distance between two sequences (strings or word lists)."""
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        current = [i]
        for j, y in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x != y)))
        previous = current
    return previous[-1]


def error_rates(hypothesis, reference):
    """(character errors, reference characters, word errors, reference words) after normalization;
    characters are compared without spaces."""
    h, r = normalize(hypothesis), normalize(reference)
    return (levenshtein(h.replace(" ", ""), r.replace(" ", "")), len(r.replace(" ", "")),
            levenshtein(h.split(), r.split()), len(r.split()))


def ratio(a, b):
    """1 - edit distance / longer length; 1.0 for two empty strings."""
    longest = max(len(a), len(b))
    return 1.0 if longest == 0 else 1.0 - levenshtein(a, b) / longest


def bigrams(text):
    return {text[i:i + 2] for i in range(len(text) - 1)}


def rank_verses(transcript, verses, k=5, shortlist=200):
    """Reference matcher for comparing models: the k verse keys whose normalized text (compared
    without spaces) is closest to the transcript by `ratio`, among the `shortlist` verses sharing the most letter
    bigrams with it. The app's matcher is RecitationRecognition's; this one only ranks models."""
    query = normalize(transcript).replace(" ", "")
    letters = {key: text.replace(" ", "") for key, text in verses.items()}
    grams = bigrams(query)
    overlap = sorted(((len(grams & bigrams(text)), key) for key, text in letters.items()), reverse=True)
    order = lambda key: tuple(map(int, key.split(":")))
    scored = sorted(((-ratio(query, letters[key]), order(key), key) for _, key in overlap[:shortlist]))
    return [key for _, _, key in scored[:k]]  # best first; equal scores in Quran order


def greedy_ctc(frame_ids, vocab, blank=BLANK_ID):
    """Collapses repeated frame ids, drops blanks, and joins SentencePiece pieces into text."""
    pieces, previous = [], None
    for token in frame_ids:
        if token != previous and token != blank:
            pieces.append(vocab[str(token)])
        previous = token
    return "".join(pieces).replace("\u2581", " ").strip()


def windows(sample_count, window=WINDOW_SAMPLES):
    """[start, end) sample ranges that cover `sample_count` in consecutive windows."""
    return [(start, min(start + window, sample_count)) for start in range(0, max(sample_count, 1), window)]


def sample_verses(n, seed):
    """`n` distinct (sura, ayah) pairs across the whole Quran, the same for a given seed."""
    keys = [(sura, ayah) for sura, count in enumerate(AYAH_COUNTS, 1) for ayah in range(1, count + 1)]
    return sorted(random.Random(seed).sample(keys, n))


def percentile(values, p):
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = min(len(ordered) - 1, max(0, round(p / 100 * (len(ordered) - 1))))
    return ordered[index]


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


BASMALA = "بسم الله الرحمن الرحيم"


def load_quran_text(db_path):
    """{'sura:ayah': normalized imla'i text} from the app's `verses` FTS table. That table puts the
    basmala before verse 1 of every sura but 1 and 9; it is not part of the verse (EveryAyah's verse
    1 recordings start after it), so it is removed, as RecitationRecognition's VerseMatcher does."""
    with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as connection:
        rows = connection.execute("SELECT sura, ayah, text FROM verses").fetchall()
    verses = {}
    for sura, ayah, text in rows:
        text = normalize(text)
        if ayah == 1 and sura not in (1, 9) and text.startswith(BASMALA + " "):
            text = text[len(BASMALA) + 1:]
        verses[f"{sura}:{ayah}"] = text
    return verses


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
        print(f"{name}: ok")


# MARK: - convert


def _register_missing_converters():
    """onnx2torch and coremltools lack a few comparison and logic ops this graph uses."""
    import torch
    from coremltools.converters.mil import Builder as mb
    from coremltools.converters.mil.frontend.torch.ops import _get_inputs
    from coremltools.converters.mil.frontend.torch.torch_op_registry import register_torch_op
    from onnx2torch.node_converters.registry import _CONVERTER_REGISTRY, add_converter
    from onnx2torch.utils.common import OperationConverterResult, onnx_mapping_from_node

    class Apply(torch.nn.Module):
        def __init__(self, function):
            super().__init__()
            self.function = function

        def forward(self, *inputs):
            return self.function(*inputs)

    known = {(key.operation_type, key.version) for key in _CONVERTER_REGISTRY}
    for op, versions, function in [
        ("GreaterOrEqual", [12, 16], torch.ge), ("IsNaN", [9, 13, 20], torch.isnan),
        ("Not", [1], torch.logical_not), ("And", [1, 7], torch.logical_and),
    ]:
        for version in versions:
            if (op, version) in known:
                continue

            @add_converter(operation_type=op, version=version)
            def _convert(node, graph, function=function):
                return OperationConverterResult(torch_module=Apply(function), onnx_mapping=onnx_mapping_from_node(node))

    @register_torch_op(torch_alias=["less"])
    def onnx_less(context, node):
        x, y = _get_inputs(context, node, expected=2)
        if x.dtype != y.dtype:
            x, y = mb.cast(x=x, dtype="fp32"), mb.cast(x=y, dtype="fp32")
        context.add(mb.less(x=x, y=y, name=node.name))


def dequantize(model):
    """Replaces MatMulNBits (4-bit blocks, zero point 8) with MatMul and DynamicQuantizeLinear +
    ConvInteger with Conv, so the graph has float weights only (the same function, up to the
    dynamic activation quantization the original applies)."""
    import numpy as np
    from onnx import helper
    from onnx import numpy_helper as nh

    graph = model.graph
    initializers = {i.name: i for i in graph.initializer}
    producer = {output: node for node in graph.node for output in node.output}
    consumers = {}
    for node in graph.node:
        for name in node.input:
            consumers.setdefault(name, []).append(node)
    array = lambda name: nh.to_array(initializers[name])
    added, removed, replaced = [], set(), {}
    for node in graph.node:
        if node.op_type == "MatMulNBits":
            attributes = {a.name: helper.get_attribute_value(a) for a in node.attribute}
            k, n, block = attributes["K"], attributes["N"], attributes["block_size"]
            if attributes["bits"] != 4 or len(node.input) != 3:
                raise ValueError(f"unsupported MatMulNBits {node.name}")
            packed, scales = array(node.input[1]), array(node.input[2])
            nibbles = np.stack([packed & 0x0F, packed >> 4], axis=-1).reshape(n, packed.shape[1], block)
            weights = ((nibbles.astype(np.float32) - 8.0) * scales[:, :, None]).reshape(n, -1)[:, :k]
            added.append(nh.from_array(weights.T.copy(), node.name + "_W"))
            replaced[node.name] = helper.make_node("MatMul", [node.input[0], node.name + "_W"], list(node.output), name=node.name)
        elif node.op_type == "ConvInteger":
            quantized_input, quantized_weights, _, weight_zero_point = node.input
            source = producer[quantized_input]
            cast = consumers[node.output[0]][0]
            rescale = consumers[cast.output[0]][0]
            scales = producer[rescale.input[1]]
            if source.op_type != "DynamicQuantizeLinear" or cast.op_type != "Cast" or rescale.op_type != "Mul" or scales.op_type != "Mul":
                raise ValueError(f"unexpected ConvInteger pattern at {node.name}")
            weights = (array(quantized_weights).astype(np.float32) - array(weight_zero_point).astype(np.float32)) * array(scales.input[1])
            added.append(nh.from_array(weights.astype(np.float32), node.name + "_W"))
            conv = helper.make_node("Conv", [source.input[0], node.name + "_W"], [rescale.output[0]], name=node.name)
            conv.attribute.extend(node.attribute)
            replaced[node.name] = conv
            removed.update([cast.name, rescale.name])
    nodes = [replaced.get(node.name, node) for node in graph.node if node.name not in removed]
    del graph.node[:]
    graph.node.extend(nodes)
    graph.initializer.extend(added)
    opsets = [o for o in model.opset_import if o.domain != "com.microsoft"]
    del model.opset_import[:]
    model.opset_import.extend(opsets)
    return model


def convert(model_dir, output_dir):
    import coremltools as ct
    import coremltools.optimize.coreml as cto
    import numpy as np
    import onnx
    import onnxslim
    import torch
    from onnx2torch import convert as onnx_to_torch

    _register_missing_converters()
    os.makedirs(output_dir, exist_ok=True)
    model = dequantize(onnx.load(os.path.join(model_dir, "fastconformer_full_mixed.onnx")))
    model = onnxslim.slim(model, input_shapes=[f"audio_signal:1,{WINDOW_SAMPLES}", "length:1"])
    module = onnx_to_torch(model).eval()
    example = (torch.zeros(1, WINDOW_SAMPLES), torch.tensor([WINDOW_SAMPLES]))
    with torch.no_grad():
        traced = torch.jit.trace(module, example, check_trace=False)
    for name, target, config in [
        ("TilawiFastConformerInt8", ct.target.iOS16, cto.OpLinearQuantizerConfig(
            mode="linear_symmetric", dtype="int8", granularity="per_channel", weight_threshold=2048)),
        ("TilawiFastConformerInt4", ct.target.iOS18, cto.OpLinearQuantizerConfig(
            mode="linear_symmetric", dtype="int4", granularity="per_block", block_size=32, weight_threshold=2048)),
    ]:
        mlmodel = ct.convert(
            traced, convert_to="mlprogram", compute_precision=ct.precision.FLOAT32, minimum_deployment_target=target,
            inputs=[ct.TensorType("audio_signal", shape=(1, WINDOW_SAMPLES), dtype=np.float32),
                    ct.TensorType("length", shape=(1,), dtype=np.int32)],
            outputs=[ct.TensorType("log_probs", dtype=np.float32)])
        mlmodel = cto.linear_quantize_weights(mlmodel, cto.OptimizationConfig(global_config=config))
        mlmodel.short_description = (
            "Quran recitation CTC model: Tilawi FastConformer (CC-BY-4.0, fine-tuned from NVIDIA "
            f"stt_ar_fastconformer_hybrid_large_pcd_v1.0), {HF_REPO}@{HF_REVISION}.")
        mlmodel.save(os.path.join(output_dir, name + ".mlpackage"))
        print(f"saved {name}.mlpackage")


# MARK: - eval


def _decode_audio(path):
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def _backend(kind, model_path, compute_units):
    """A function from 16 kHz samples to log-probabilities, or for `whisper` (a Hugging Face model id
    such as tarteel-ai/whisper-base-ar-quran, run by transformers on the CPU) to text."""
    import numpy as np
    if kind == "whisper":
        from transformers import pipeline
        recognizer = pipeline("automatic-speech-recognition", model=model_path, device="cpu", chunk_length_s=30)
        # Tarteel's checkpoints predate `language=`; their generation config already forces Arabic transcription.
        return lambda audio: recognizer({"raw": audio, "sampling_rate": SAMPLE_RATE})["text"]
    if kind == "onnx":
        import onnxruntime
        session = onnxruntime.InferenceSession(model_path)

        def run(window):
            feeds = {"audio_signal": window[None], "length": np.array([len(window)], dtype=np.int64)}
            return session.run(None, feeds)[0][0]
        return run
    import coremltools as ct
    mlmodel = ct.models.MLModel(model_path, compute_units=getattr(ct.ComputeUnit, compute_units))

    def run(window):
        padded = np.zeros((1, WINDOW_SAMPLES), dtype=np.float32)
        padded[0, :len(window)] = window
        output = mlmodel.predict({"audio_signal": padded, "length": np.array([len(window)], dtype=np.int32)})["log_probs"][0]
        return output[: -(-len(window) // 1280)]  # the frames that cover real audio (80 ms each)
    return run


def evaluate(args):
    vocab = json.load(open(args.vocab, encoding="utf-8")) if args.backend != "whisper" else None
    verses = load_quran_text(args.quran_db)
    run = _backend(args.backend, args.model, args.compute_units)
    clips, latencies = [], []
    for reciter in args.reciter:
        directory = os.path.join(args.cache, reciter)
        os.makedirs(directory, exist_ok=True)
        for sura, ayah in sample_verses(args.n, args.seed):
            name = f"{sura:03d}{ayah:03d}.mp3"
            path = os.path.join(directory, name)
            if not os.path.exists(path):
                urllib.request.urlretrieve(f"{EVERYAYAH}/{reciter}/{name}", path + ".part")
                os.replace(path + ".part", path)
            audio = _decode_audio(path)
            started = time.perf_counter()
            if args.backend == "whisper":
                text = run(audio)
            else:
                text = " ".join(filter(None, (greedy_ctc(run(audio[start:end]).argmax(-1).tolist(), vocab)
                                              for start, end in windows(len(audio)))))
            elapsed = time.perf_counter() - started
            key = f"{sura}:{ayah}"
            ranked = rank_verses(text, verses)
            ce, cn, we, wn = error_rates(text, verses[key])
            latencies.append(elapsed)
            clips.append({"reciter": reciter, "key": key, "seconds": round(len(audio) / SAMPLE_RATE, 2),
                          "latency_ms": round(elapsed * 1000, 1), "transcript": text, "top5": ranked,
                          "char_errors": ce, "chars": cn, "word_errors": we, "words": wn})
    seconds = sum(c["seconds"] for c in clips)

    def summary(selection):
        same = lambda a, b: verses[a].replace(" ", "") == verses[b].replace(" ", "")  # identical texts count
        exact = lambda c: same(c["top5"][0], c["key"])
        in_top5 = lambda c: any(same(k, c["key"]) for k in c["top5"])
        return {
            "clips": len(selection),
            "top1": round(sum(map(exact, selection)) / len(selection), 4),
            "top5": round(sum(map(in_top5, selection)) / len(selection), 4),
            "cer": round(sum(c["char_errors"] for c in selection) / sum(c["chars"] for c in selection), 4),
            "wer": round(sum(c["word_errors"] for c in selection) / sum(c["words"] for c in selection), 4),
            # Long recordings repeat phrases (a reciter going back after a pause), which counts as insertions.
            "cer_upto_20s": round(sum(c["char_errors"] for c in short) / max(1, sum(c["chars"] for c in short)), 4)
            if (short := [c for c in selection if c["seconds"] <= 20]) else None,
        }
    result = {
        "backend": args.backend, "model": os.path.basename(args.model.rstrip("/")), "compute_units": args.compute_units,
        "seed": args.seed, "n": args.n, "overall": summary(clips),
        "by_reciter": {r: summary([c for c in clips if c["reciter"] == r]) for r in args.reciter},
        "latency_ms": {"p50": round(percentile(latencies, 50) * 1000, 1), "p95": round(percentile(latencies, 95) * 1000, 1),
                       "mean": round(statistics.mean(latencies) * 1000, 1)},
        "real_time_factor": round(sum(latencies) / seconds, 4), "audio_seconds": round(seconds, 1), "clips": clips,
    }
    with open(args.out, "w", encoding="utf-8") as file:
        json.dump(result, file, ensure_ascii=False, indent=1)
    print(json.dumps({k: v for k, v in result.items() if k != "clips"}, ensure_ascii=False, indent=1))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("fetch").add_argument("model_dir")
    convert_parser = commands.add_parser("convert")
    convert_parser.add_argument("model_dir")
    convert_parser.add_argument("output_dir")
    eval_parser = commands.add_parser("eval")
    eval_parser.add_argument("--backend", choices=["onnx", "coreml", "whisper"], required=True)
    for name in ["--model", "--vocab", "--quran-db", "--cache", "--out"]:
        eval_parser.add_argument(name, required=True)
    eval_parser.add_argument("--reciter", action="append", required=True)
    eval_parser.add_argument("--n", type=int, default=50)
    eval_parser.add_argument("--seed", type=int, default=1)
    eval_parser.add_argument("--compute-units", default="ALL", choices=["ALL", "CPU_ONLY", "CPU_AND_GPU", "CPU_AND_NE"])
    args = parser.parse_args(argv)
    if args.command == "fetch":
        fetch(args.model_dir)
    elif args.command == "convert":
        convert(args.model_dir, args.output_dir)
    else:
        evaluate(args)


if __name__ == "__main__":
    main(sys.argv[1:])
