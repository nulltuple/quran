# Quran C1: English Ibn Kathir and Bengali Ahsanul Bayaan tafsir packs

- **Date:** 2026-11-26
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-26-c1-tafsir-sheet.md](2026-11-26-c1-tafsir-sheet.md) (Arabic slice, the sheet),
  roadmap v2 §6 C1 and owner decision D6 ([quran-prioritized-roadmap.md](../agents/quran-prioritized-roadmap.md))

## Context

App: **Quran**, plus **Arabican** rebuilt because it imports the changed `QuranText` module. C1's Arabic slice
shipped the tafsir sheet over the Quran.app feed, which has no English or Bengali tafsir. Owner, 2026-11-26:
"For tafsir you can do ibn kathir and ahsanul". Asked where the packs live (they are too large to bundle:
19 MB and 15 MB as SQLite), the owner chose "GitHub Release (Recommended)": packs built by a `Tools/` script
from Quran.com API v4 and published as release assets on the public repository `nulltuple/quran`.

Sources (Quran.com API v4 `GET /api/v4/resources/tafsirs`, read 2026-11-26): English "Ibn Kathir (Abridged)"
resource 169, Bengali "Tafsir Ahsanul Bayaan" resource 165 (Bayaan Foundation).

## Decisions

- **Same pack shape as the feed**, so nothing downstream changes: SQLite with FTS3 `verses(sura, ayah, text)`
  and `properties` (`schema_version` 5, `text_version`), the shape of the feed's `quran.ar.muyassar.db`
  (read with `sqlite3 .schema` from the simulator's download). A zip holding one database named like the
  entry's `fileName`, because `DefaultTranslationUnzipper` unzips into the translations folder.
- **Passages.** `by_chapter` puts a passage's explanation on its first ayah and an empty text on the rest;
  `by_ayah` of 2:9 lists `2:8, 2:9` with 2:8's text, and 2:46 lists `2:45, 2:46` (checked 2026-11-26). The pack
  stores a continuation as the 1-based index of the passage's first ayah (the feed's reference convention,
  `GRDBVerseTextPersistence.textFromRow`), never across a sura boundary. Ibn Kathir: 4,336 references, 5 ayahs
  without text; Ahsanul Bayaan: 3 references, none without text.
- **HTML to plain text.** Block tags become paragraphs separated by a blank line, inline tags are dropped,
  entities are decoded once. The sheet and the translation view render plain text, so no new renderer.
- **App entries, not a second catalog.** `Translation.supplementaryTafsirs` (2 entries, ids 10169 and 10165:
  10,000 plus the Quran.com id, far above the feed's ids, at most 122) is appended to the feed by
  `TranslationNetworkManager` unless the feed has the same id or file name, so if Quran.app ever adds these,
  the feed wins. Both ids are in `Translation.tafsirIDs`, so the sheet lists them. Download, update, delete
  and storage are the existing translations pipeline.
- **Hosting:** release `tafsir-packs-1` on `nulltuple/quran`
  (https://github.com/nulltuple/quran/releases/tag/tafsir-packs-1), owner-approved in this session.
  `quran.en.ibnkathir.zip` 7,312,765 bytes, sha256 `36b8cbbdcc874e5dd8e905244ba04ec3adda7f6aeda4717d7a16767c45808457`;
  `quran.bn.ahsanulbayaan.zip` 3,869,709 bytes, sha256 `5dfa1d7c663509b1d57077e7be4361e6b9fb8e1b4d21689d1a13378bfb19e609`.
  Inputs (not in git): API downloads 169.json sha256 `b07e54e8e729b45a987e93ee0a57a5a0c6dc8b20f608c5f48d64317b17505818`,
  165.json `4e8de82b5a85155571966e7eeca8265b9b46f7fce2ead19229d352ab74324547`.
- **Not changed:** the empty-state message still suggests Arabic Muyassar (a string change in 16 languages
  for little gain); a download from the list still selects the tafsir for the reader too (C1 follow-up).

## Trade-offs

- **Complexity added:** `Tools/build-tafsir-pack.py` (200 lines) and its test (71 lines); 2 list entries and an
  id base in `Translation+Tafsir.swift`; 6 lines in `TranslationNetworkManager`; one init parameter in
  `TranslationsRepository`. No dependency, permission or entitlement; no new persisted format (same
  translation databases). New failure mode: the GitHub release asset disappears or moves, so the download
  fails like any feed download; nothing already downloaded is affected.
- **Who benefits / how often:** the household reads English and Bengali; Arabic tafsir was usable only by
  Arabic readers. Likely used weekly by the people studying, rarely by others.
- **Rejected cheaper options:** bundling (≈34 MB of SQLite in the binary for everyone); fetching from Quran.com
  in the app (about 260 requests per download and new download code; the owner preferred the release).
- **Ongoing cost:** two packs to rebuild by hand when Quran.com corrects them (bump `text_version` and the
  entry's `version` together); the release must stay public. Attribution recorded here; the texts' own terms
  do not bind personal use (owner decision, 2026-11-25), revisit for any public release.

## Changes

- `Tools/build-tafsir-pack.py`: `download` (Quran.com API v4 `by_chapter`, paged), `build` (validation, HTML to
  text, passage references, FTS3 database), `zip`. `Tools/build-tafsir-pack.test.sh`, wired into `make test-tools`.
- `Model/QuranText/Sources/Translation+Tafsir.swift`: `supplementaryTafsirIDBase`, `supplementaryTafsirs`, the two
  ids in `tafsirIDs`.
- `Domain/TranslationService/Sources/TranslationNetworkManager.swift`: appends `supplementaryTranslations` not in
  the feed. `TranslationsRepository.swift`: the public init passes `Translation.supplementaryTafsirs`.
- GitHub release `tafsir-packs-1` (two assets; outside git).
- Platforms: shared layers; iPhone and iPad alike.

## Tests

- `Tools/build-tafsir-pack.test.sh` (12 checks): one row per ayah, schema and text version, FTS search, HTML to
  paragraphs with entities, plain rows, passage continuation stored as `15` for 2:9, a sura's first empty ayah
  stays empty, missing and duplicate ayahs refused, zip holds only the database under its name.
- `TranslationServiceTests/TranslationsRepositoryTests` (+3): supplementary tafsirs listed after the feed, also
  after a second sync; a feed entry with the same file name wins; the entries are zipped tafsirs with unique
  ids and files whose zip is named after the database.
- New behavior, not a bug fix, so no fail-before-fix run.

## Validation

- **Verified:**
  - `bash Tools/build-tafsir-pack.test.sh`: `12 passed, 0 failed`.
  - `make test-no-sync TARGET=TranslationServiceTests`: `Executed 23 tests, with 0 failures (0 unexpected)`.
  - Packs: 6,236 rows each; `sqlite3` reads 2:9 → `15` and 2:46 → `52` in Ibn Kathir; 1:1 opens with
    "Introduction to Fatihah"; Bengali 2:8 and 2:9 have their own texts.
  - Release assets: `curl -sIL .../quran.bn.ahsanulbayaan.zip`: `HTTP/2 200`, `content-length: 3869709`.
  - Simulator (no-sync build): Settings > Translations lists "English Ibn Kathir Tafseer (Abridged)" under
    English; download unzipped `quran.en.ibnkathir.db` (`text_version` 1, 6,236 rows); the tafsir sheet's picker
    offers Muyassar and Ibn Kathir; 1:1 and 2:2 show English paragraphs; 2:8 shows "Al-Baqarah 2:8–9" and
    "This explanation covers these ayahs together." with both ayahs' Quran text.
  - `make test-no-sync`: `xcresulttool` summary `Passed`, 1,507 of 1,507 (1,504 at F2, plus 3).
  - `make test-sync` (after no-sync): `Passed`, 1,986 of 1,986.
  - `make test-arabican` (after sync; `QuranText` changed): `Passed`, 117 of 117.
  - `make test-tools`: every suite `0 failed` (tafsir pack `12 passed, 0 failed`).
  - `make format-lint`: `0/1163 files require formatting, 44 files skipped.`
  - `make build-example-no-sync`, `make build-example-sync`, `make build-arabican`: exit 0 each.
- **Not verified:** the Bengali pack downloaded in the app (same path as English; the asset is served and its
  database checked with `sqlite3`); Bengali rendering at large text sizes and VoiceOver in the sheet; iPad.

## Release

- **Commit:** filled in by the `docs(trail)` follow-up.
- **Pushed:** filled in by the `docs(trail)` follow-up.
- **TestFlight:** filled in by the `docs(trail)` follow-up.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- Optional: Bengali Abu Bakr Zakaria (166) or Ibn Kathir (164), English Ma'arif (168): one `download`/`build`/`zip`
  run each, a new release asset, and an entry in `supplementaryTafsirs`.
- Optional (from the Arabic slice): keep tafsirs out of the reader's translation picker; mention English and
  Bengali tafsir in the sheet's empty state.
