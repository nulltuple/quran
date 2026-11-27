# V0 slice (b): recited words aligned to canonical Quran words, with timing

- **Date:** 2026-11-27
- **Agent:** Claude Code / claude-opus-5-5
- **Type:** feature
- **Status:** shipped
- **Related:** [2026-11-26-v0-recitation-engine.md](2026-11-26-v0-recitation-engine.md) (slice a; its Follow-ups name this
  slice), [2026-11-24-m1-canonical-word-data.md](2026-11-24-m1-canonical-word-data.md) (canonical words,
  `uthmani_tokens`)

App: **Quran** (QuranEngine Domain module `RecitationRecognition`, still not linked into either app). Arabican does not
import the module.

## Context

Roadmap §6 V0 deliverable 3: the engine's output "mapped onto the canonical ayah and word identities (… `Word`)". Slice
(a) identifies verses from a transcript; this slice maps each recited word to the canonical `Word`s of the passage and
keeps the CTC frames (80 ms) it spans, which V2 (live follow, reveal by recitation) and V3 (mistake detection) need.

Evidence for the expected text: the bundled Uthmani `arabic_text` (`quran.ar.uthmani.v2.db`) has one whitespace token per
canonical word in 6,230 of 6,236 ayahs; the six others (15:7, 27:20, 36:22, 37:130, 37:164, 41:47) are mapped by
`word_by_word.db` `uthmani_tokens` (checked this session with a script over both databases: `mismatch 6`, no token without
letters). The model writes plain (imla'i) spelling with harakat, so the aligner compares an imla'i transcript with Uthmani
words.

## Decisions

- **Align against the Uthmani words, not the imla'i search text.** The imla'i `verses` text splits words differently from
  the canonical numbering in 468 ayahs (slice a trail); the Uthmani tokens map to canonical words exactly, through the
  same `UthmaniWordLayout` the translation view's word-by-word line uses (`WordByWordService.textLayouts`).
- **Word-level edit distance with regrouping.** Pair cost 2 × (1 − similarity), gap 1, and two recited words for one
  expected (or one for two) at the pair cost + 0.4 (`يا أيها` / `يَٰٓأَيُّهَا`). Similarity is the better of the letter ratio
  and the ratio without alef, on `ArabicMatchNormalizer` letters with `ؤ`→`و`, `ئ`→`ي`, `ء` dropped. Chosen on the 350
  benchmark transcripts with a Python prototype (scratchpad, not kept) before writing Swift:

  | Variant | Canonical words matched (of 4,305) |
  |---|---|
  | letters only, regrouping +0.1 | 4,122 (95.75%) |
  | + dagger alef and small waw/ya folded, hamza folded | 4,122–4,129 |
  | + alef-free similarity (alef only) | 4,187 (97.26%) at +0.4 |
  | + alef-free (alef, hamza, waw, ya removed), +0.4 | 4,221 (98.05%) |
  | **hamza folded + alef-free (alef only), +0.4** | **4,218 (97.98%)** |

  Removing waw and ya as well matched 3 more words but would also forgive a missing conjunction `و`, a real mistake V3 must
  see; folding the dagger alef to alef made things worse with the alef-free comparison. The Swift implementation reproduces
  the chosen row exactly (`words=4305 matched=4218 mismatched=79 omitted=8 inserted=101`).
- **Match threshold 0.7.** A step at or above it is `.matched`; below it `.mismatched`. The 79 mismatched words are mostly
  misheard words in clips over 20 s (a reciter going back over a phrase, words cut at a window edge). This is an alignment
  label, not a mistake verdict: V3 adds per-word confidence from the CTC posteriors (forced alignment) before telling anyone
  they made a mistake.
- **Statuses:** `.matched`, `.mismatched`, `.omitted`, `.inserted` (a repeat, the basmala before a verse, noise). Every
  expected word appears exactly once, in order (asserted over all 350 clips).
- **Frames are global.** `RecitationRecognizer.recognizeWords` shifts each window's frames by the window's first frame, so a
  word's frames count from the start of the recording (`RecitationAcousticModel.samplesPerFrame`, new requirement; 1,280 for
  the Tilawi model).
- **A real artifact kept visible in a test:** in Alafasy's 1:2 the model writes stray letters into the 3 s madd of
  `ٱلۡعَٰلَمِينَ` and joins them to the word (`العالميندرس`, frames 33–69). The step still aligns to word 4 (mismatched,
  similarity 0.67); `testALongHeldLastWordStillAlignsToItsWord` records it instead of hiding it. V3 must handle long madd
  (likely by confidence over frames, or the phoneme model).

## Trade-offs

- **Complexity added:** 3 source files (`RecognizedWord.swift` 63 lines, `WordAligner.swift` 189, `ExpectedWordsReader.swift`
  62), `RecitationRecognizer` +18 lines, `RecitationAcousticModel` +5; 4 test files (+2 tests in `CoreMLRecitationModelTests`).
  `RecitationRecognition` now depends on `VerseTextPersistence` and `WordTextService` (both already in the package, Domain may
  use Data and Domain). No new package, permission, persisted state or data asset.
- **Who benefits / how often:** nobody directly yet; V2 and V3 build on it. Those are committed roadmap objectives.
- **Rejected cheaper options:** greedy letter-stream alignment (no word identity when the scripts split words differently);
  aligning against the imla'i text (468 ayahs with other word boundaries); CTC forced alignment of the expected text now
  (needs the expected text in the model's vocabulary spelling, an imla'i form per canonical word that doesn't exist yet; it
  is V3's step).
- **Ongoing cost:** O(recited × expected) letter comparisons per alignment (2.1 s for all 350 clips, about 6 ms per clip, in
  a debug simulator build); callers must align to the identified verses, not a whole sura. No launch or memory cost (not
  linked into the app).

## Changes

- `Domain/RecitationRecognition/Sources/RecognizedWord.swift`: `RecognizedWord`, `CTCTranscript.words(frameOffset:)`.
- `Domain/RecitationRecognition/Sources/WordAligner.swift`: `ExpectedWordText`, `WordAlignmentStep`, `WordAligner`.
- `Domain/RecitationRecognition/Sources/ExpectedWordsReader.swift`: Uthmani text + `WordByWordService.textLayouts` →
  `[ExpectedWordText]`; `ExpectedWordsError`.
- `Domain/RecitationRecognition/Sources/RecitationRecognizer.swift`: `recognizeWords`, `transcribe` built on it,
  `alignWords(in:to:)`.
- `Domain/RecitationRecognition/Sources/RecitationAcousticModel.swift`: `samplesPerFrame` requirement.
- `Package.swift`: the module's new dependencies. Platform-neutral (iPhone and iPad), no `#if`.
- Docs: roadmap §5/§6 V0, `quran-roadmap-progress.md`, `feature-cost-register.md`, trail index.

## Tests

- `RecognizedWordTests` (4): tokens group into words with frames; window offset; a piece that ends one word and starts the
  next; plain transcript.
- `WordAlignerTests` (10): plain spelling matches every Uthmani word of 1:2; `يا أيها` → `يَٰٓأَيُّهَا`; omitted, inserted
  (repeat), mismatched word; basmala before 2:1 inserted; frames kept; a text covering two words (15:7); empty inputs; hamza
  seats.
- `ExpectedWordsReaderTests` (4): 1:2–3 in order; 15:7's first token covers words 1–2; 37:130's word 3 joins two tokens;
  a verse without words throws `noWordLayout`.
- `WordAlignerRecitationTests` (1): the 350 real transcripts, every word once and in order, ≥ 97% matched (measured 97.98%).
- `CoreMLRecitationModelTests` (+2): Husary 112:1 audio → 4 matched words with ordered frames inside the clip; Alafasy 1:2
  long madd (above); and the 2:255 recording over three windows (≥ 90% matched, frame starts ordered, last start past
  frame 500). These run with `.cache/recitation-model` present (they did here: 0 skipped).
- Three first-run failures were wrong expectations in the new tests, fixed in the tests (two equal repeats may tie either
  way; the dagger-alef word is equal only under the alef-free similarity; the Alafasy madd above).

## Validation

- **Verified:**
  - `make test-no-sync TARGET=RecitationRecognitionTests`: 47 passed, 0 failed, 0 skipped (xcresult summary);
    `RecitationModelLatency window_ms=[236, 238, 239, 240, 276]`.
  - `make format-lint`: `0/1203 files require formatting`.
  - `make test-no-sync`: 1,613 passed, 0 failed, 0 skipped; then `make test-sync`: 2,092 passed, 0 failed, 0 skipped; then
    `make test-arabican`: 117 passed, 0 failed (xcresult summaries; run one after the other, model present).
  - App builds (`make build-example-*`, `make build-arabican`) were not run for this slice: neither app links
    `RecitationRecognition` (no reference in `Example/` or `Apps/`), so neither app's build inputs changed beyond the
    package manifest; they run with slice (c), which links the module.
- **Not verified:** live microphone speech and any device (slice c); alignment speed in a release build.

## Release

- **Commit:** this entry's commit (`feat(recitation): align recited words to canonical Quran words`).
- **Pushed:** origin/main.
- **TestFlight:** no build for this slice alone: `RecitationRecognition` is not linked into either app, so neither
  shipped binary changes. Slice (c) links it (developer screen) and ships both slices in one build.
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- **V0 (c):** developer microphone screen behind a debug setting; device benchmarks (needs D7 for the model on a phone).
- **V3:** CTC forced alignment over posteriors for per-word confidence; an imla'i form per canonical word (or a mapping
  from the model's spelling); long madd handling (Alafasy 1:2 above).
- Bound the alignment (band around the diagonal) if a caller ever aligns long passages.
