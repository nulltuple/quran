#!/usr/bin/env python3
"""Builds an offline tafsir pack, in the app's translation database shape, from Quran.com API v4.

The Quran.app translations feed has no English or Bengali tafsir, so the app lists two extra
entries (`Translation.supplementaryTafsirs`) whose packs this tool builds:

  169  English, Ibn Kathir (Abridged)   -> quran.en.ibnkathir.db
  165  Bengali, Tafsir Ahsanul Bayaan   -> quran.bn.ahsanulbayaan.db

A pack is a SQLite database like the feed's (e.g. quran.ar.muyassar.db): an FTS3 table
`verses(sura, ayah, text)` with one row for each of the 6,236 ayahs, and `properties` with
`schema_version` 5 and `text_version`. Text is plain: HTML paragraphs and headings become
paragraphs separated by a blank line, inline tags are dropped, entities are decoded.

Passages: the API's `by_chapter` endpoint gives a passage's explanation on its first ayah and an
empty text on the others (`by_ayah` of a later ayah lists the whole passage, checked on 2:8-9 and
2:45-46 on 2026-11-26). The pack stores such an ayah's text as the 1-based index of the passage's
first ayah in the Quran, the feed's reference convention, so the app shows the whole passage.

Usage:
  build-tafsir-pack.py download <resource-id> <raw.json>    # network, about 130 requests
  build-tafsir-pack.py build <raw.json> <output.db> <text-version>
  build-tafsir-pack.py zip <output.db> <output.zip>         # the zip holds only the database

`download` saves the API's entries verbatim, so `build` can be rerun offline. Run with
`python3 -I`. The API needs no key or account; nothing about the user is sent.
"""

import hashlib
import html.parser
import json
import os
import re
import sqlite3
import sys
import time
import urllib.request
import zipfile

API = "https://api.quran.com/api/v4"
SCHEMA_VERSION = 5
# Ayahs per sura (Hafs), so verse keys and reference indexes are checked without the network.
AYAH_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53,
    89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12,
    12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26,
    30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
]
AYAHS = sum(AYAH_COUNTS)


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "quran-tafsir-pack-builder"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except Exception as error:  # noqa: BLE001 - retried, then reported.
            if attempt == 3:
                fail(f"{url}: {error}")
            time.sleep(2 * (attempt + 1))
    return None


def download(resource_id, output):
    entries = []
    for sura in range(1, len(AYAH_COUNTS) + 1):
        page = 1
        while page:
            data = get(f"{API}/tafsirs/{resource_id}/by_chapter/{sura}?per_page=50&page={page}")
            entries += [{"verse_key": t["verse_key"], "text": t["text"]} for t in data["tafsirs"]]
            page = data["pagination"]["next_page"]
            time.sleep(0.2)
        print(f"sura {sura}: {len(entries)} entries", file=sys.stderr)
    with open(output, "w", encoding="utf-8") as file:
        json.dump({"resource_id": resource_id, "tafsirs": entries}, file, ensure_ascii=False)
    print(f"wrote {output}: {len(entries)} entries")


class _TextExtractor(html.parser.HTMLParser):
    BLOCKS = {"p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "ul", "ol", "table", "tr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.paragraphs = []
        self.current = []

    def _flush(self):
        text = re.sub(r"\s+", " ", "".join(self.current)).strip()
        if text:
            self.paragraphs.append(text)
        self.current = []

    def handle_starttag(self, tag, attrs):
        if tag in self.BLOCKS:
            self._flush()
        elif tag == "br":
            self._flush()

    def handle_endtag(self, tag):
        if tag in self.BLOCKS:
            self._flush()

    def handle_data(self, data):
        self.current.append(data)


def plain_text(markup):
    """Paragraphs separated by a blank line, without tags or entities."""
    extractor = _TextExtractor()
    extractor.feed(markup)
    extractor.close()
    extractor._flush()
    # The parser already decoded entities (`convert_charrefs`); decoding again would corrupt `&amp;lt;`.
    return "\n\n".join(extractor.paragraphs)


def verse_index(sura, ayah):
    """The 1-based index of an ayah among all 6,236, the feed's reference format."""
    return sum(AYAH_COUNTS[: sura - 1]) + ayah


def rows(entries):
    """One (sura, ayah, text) per ayah, with passage continuations as references to the passage start."""
    by_key = {}
    for entry in entries:
        key = entry["verse_key"]
        if key in by_key:
            fail(f"duplicate verse {key}")
        by_key[key] = plain_text(entry["text"] or "")
    result = []
    references = 0
    for sura, count in enumerate(AYAH_COUNTS, start=1):
        holder = None
        for ayah in range(1, count + 1):
            key = f"{sura}:{ayah}"
            if key not in by_key:
                fail(f"missing verse {key}")
            text = by_key[key]
            if text:
                holder = verse_index(sura, ayah)
                result.append((sura, ayah, text))
            elif holder is not None:
                # Passages never cross suras: a sura's first ayah without text stays empty.
                references += 1
                result.append((sura, ayah, str(holder)))
            else:
                result.append((sura, ayah, ""))
    extra = set(by_key) - {f"{s}:{a}" for s, c in enumerate(AYAH_COUNTS, 1) for a in range(1, c + 1)}
    if extra:
        fail(f"unknown verses {sorted(extra)[:5]}")
    return result, references


def build(raw_path, output, text_version):
    with open(raw_path, encoding="utf-8") as file:
        raw = json.load(file)
    result, references = rows(raw["tafsirs"])
    if os.path.exists(output):
        os.remove(output)
    db = sqlite3.connect(output)
    db.execute("CREATE TABLE properties (property TEXT, value TEXT)")
    db.execute("CREATE VIRTUAL TABLE verses USING fts3 (sura INTEGER, ayah INTEGER, text TEXT)")
    db.executemany("INSERT INTO properties VALUES (?, ?)", [("schema_version", str(SCHEMA_VERSION)), ("text_version", str(text_version))])
    db.executemany("INSERT INTO verses (sura, ayah, text) VALUES (?, ?, ?)", result)
    db.commit()
    db.execute("VACUUM")
    db.close()
    empty = sum(1 for _, _, text in result if text == "")
    print(f"wrote {output}: {len(result)} ayahs, {references} passage references, {empty} without text")


def make_zip(database, output):
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        archive.write(database, arcname=os.path.basename(database))
    with open(output, "rb") as file:
        digest = hashlib.sha256(file.read()).hexdigest()
    print(f"wrote {output}: {os.path.getsize(output)} bytes, sha256 {digest}")


def main(arguments):
    if len(arguments) == 3 and arguments[0] == "download":
        download(int(arguments[1]), arguments[2])
    elif len(arguments) == 4 and arguments[0] == "build":
        build(arguments[1], arguments[2], int(arguments[3]))
    elif len(arguments) == 3 and arguments[0] == "zip":
        make_zip(arguments[1], arguments[2])
    else:
        fail(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
