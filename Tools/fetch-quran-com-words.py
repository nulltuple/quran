#!/usr/bin/env python3
"""Downloads the per-word data of every ayah from the public Quran.com API v4 into one JSON file.

The output is an input of `build-qul-word-data.py words`; it is not bundled in the app. It gives,
for each word of an ayah in Quran.com word numbering (the numbering QUL uses), its KFGQPC v1 glyph
codes (`code_v1`, the font the Madani 1405 page images were drawn with: one code point per glyph,
so a word followed by a pause mark has two), its Uthmani text, its transliteration and its word
audio path. The builder uses the glyph codes to map words to page-image glyphs exactly, instead of
guessing from glyph widths.

Usage:
  fetch-quran-com-words.py download <raw.json>   # needs the network, about 230 requests
  fetch-quran-com-words.py normalize <raw.json> <output.json>  # offline

`download` saves the API's responses verbatim, so `normalize` can be rerun without the network.

Run with `python3 -I`. The API needs no key or account; nothing about the user is sent.
"""

import hashlib
import json
import sys
import time
import urllib.request

API = "https://api.quran.com/api/v4"
WORD_FIELDS = "code_v1,text_uthmani,v1_page,line_number,position,char_type_name"
SURAS = 114
AYAHS = 6236


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "quran-word-data-builder"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except Exception as error:  # noqa: BLE001 - retried, then reported.
            if attempt == 3:
                fail(f"{url}: {error}")
            time.sleep(2 * (attempt + 1))
    return None


def download_raw():
    verses = []
    for sura in range(1, SURAS + 1):
        page = 1
        while True:
            body = get(
                f"{API}/verses/by_chapter/{sura}?words=true&per_page=50&page={page}&word_fields={WORD_FIELDS}"
            )
            verses.extend(body["verses"])
            next_page = body["pagination"]["next_page"]
            if not next_page:
                break
            page = next_page
            time.sleep(0.1)
        print(f"sura {sura}: {len(verses)} ayahs so far", file=sys.stderr)
    return verses


def normalize(verses):
    """One record per ayah: its words in order, and its end (ayah-number) glyph codes."""
    ayahs = []
    for verse in verses:
        sura, ayah = (int(part) for part in verse["verse_key"].split(":"))
        words = []
        end_codes = None
        for word in sorted(verse["words"], key=lambda word: word["position"]):
            if word["char_type_name"] == "end":
                end_codes = word["code_v1"]
                continue
            if word["char_type_name"] != "word":
                fail(f"{sura}:{ayah} word {word['position']} has type {word['char_type_name']!r}")
            words.append(
                {
                    "position": word["position"],
                    "code_v1": word["code_v1"],
                    "text_uthmani": word["text_uthmani"],
                    "v1_page": word["v1_page"],
                    "line_number": word["line_number"],
                    "translation": (word.get("translation") or {}).get("text"),
                    "transliteration": (word.get("transliteration") or {}).get("text"),
                    "audio_url": word.get("audio_url"),
                }
            )
        if end_codes is None:
            fail(f"{sura}:{ayah} has no ayah-number glyph")
        if [word["position"] for word in words] != list(range(1, len(words) + 1)):
            fail(f"{sura}:{ayah} word positions are not 1...n")
        ayahs.append({"sura": sura, "ayah": ayah, "end_code_v1": end_codes, "words": words})
    ayahs.sort(key=lambda record: (record["sura"], record["ayah"]))
    keys = [(record["sura"], record["ayah"]) for record in ayahs]
    if len(set(keys)) != len(keys):
        fail("the download has duplicate ayahs")
    return ayahs


def write(ayahs, path, expected_ayahs):
    if expected_ayahs is not None and len(ayahs) != expected_ayahs:
        fail(f"expected {expected_ayahs} ayahs, got {len(ayahs)}")
    data = json.dumps({"source": f"{API}/verses/by_chapter", "ayahs": ayahs}, ensure_ascii=False, sort_keys=True)
    with open(path, "w", encoding="utf-8") as file:
        file.write(data)
    digest = hashlib.sha256(data.encode("utf-8")).hexdigest()
    words = sum(len(record["words"]) for record in ayahs)
    print(f"wrote {len(ayahs)} ayahs, {words} words, sha256 {digest}")


def main(argv):
    if len(argv) == 3 and argv[1] == "download":
        verses = download_raw()
        if len(verses) != AYAHS:
            fail(f"expected {AYAHS} ayahs, got {len(verses)}")
        with open(argv[2], "w", encoding="utf-8") as file:
            json.dump({"verses": verses}, file, ensure_ascii=False)
        print(f"downloaded {len(verses)} ayahs")
    elif len(argv) == 4 and argv[1] == "normalize":
        with open(argv[2], encoding="utf-8") as file:
            raw = json.load(file)
        write(normalize(raw["verses"]), argv[3], AYAHS if len(raw["verses"]) == AYAHS else None)
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
