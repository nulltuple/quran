# 05 · Tajweed cross-check (milestone L6)

App: **Arabican**. This log is the L6 exit gate's evidence (spec 03 §5.2: "disagreements between the two
sources listed and resolved by review"). Regenerate it from `Tools/learning/tajweed.py --report`.

## Sources

| Source | Pin | How it was used |
|---|---|---|
| quran-transcript (`github.com/obadx/quran-transcript`, MIT) | commit `e30c100e0b30684eac5d2822ec0f7d72c0b04039` (v0.7.0), pip-installed into a scratch virtualenv with levenshtein 0.27.5, pydantic 2.14.4, xmltodict 1.0.4, numpy 2.5.5, fuzzysearch 0.8.1 | `quran_phonetizer` on each ayah alone (so its last word is read with a stop), `MoshafAttributes(rewaya="hafs", madd_monfasel_len=4, madd_mottasel_len=4, madd_mottasel_waqf=4, madd_aared_len=4)`, every other attribute the library's default. Rule positions from `mappings.get_ph_to_tajweed_rules`. Its own test suite was not run. |
| Quran.com `uthmani_tajweed` | `api.quran.com/api/v4/quran/verses/uthmani_tajweed?chapter_number=<n>`, fetched 2026-11-26 | Saved per sura; SHA-256 below. |

| File | SHA-256 |
|---|---|
| `tajweed_1.json` | `4ca7e4666fe7d1a93332aba41e0e2b8af5e635cc0163dae8a9fa4555eeceaa65` |
| `tajweed_103.json` | `d27226443c77c03bbc3bd08b24ba2b03a0ddebf116f5da9eeb95468a1bbbe46e` |
| `tajweed_108.json` | `9ae65a35f00975926ca2320e2a083c85d1a858fef70c2a5b1229a351feb9508b` |
| `tajweed_110.json` | `2769f80f6fd9994fe059d35495c4598fe48b9ba0b77728f071be890ac9bc51a8` |
| `tajweed_111.json` | `55542f4e0d1af6fd69002a9844ae099be5bdd15e41807402a7a88f54d0239278` |
| `tajweed_112.json` | `745d8d3de9ab44a37558e438da4066145ef1abd74c9f6adf7e1aba4825617729` |
| `tajweed_113.json` | `1c418758cf39443f8e2db585cd85225948b07ae29be5b249b94a1c565e52f7d7` |
| `tajweed_114.json` | `79224945344457fe51f72b97da4e44b0d9f114a6e615f3d4394ed93ebe6b51dd` |

Both sources write the Tanzil encoding; the canonical KFGQPC text writes marks differently (sukun U+06E1,
dagger alif without a tatweel). All 36 ayahs of the 8 bridge suras have the same word count in all three
texts. `tajweed.py` aligns each word's letters to move spans onto canonical graphemes.

## Method

1. Map each quran-transcript rule to a T1 rule (`PHONETIZER_RULES`); `IDGHAM_KAMEL` counts only when a noon
   sakinah or tanwin merges into ل or ر (the article's assimilation is U6's sun letters). Noon rules and
   ghunnah are anchored on the letters themselves (the noon or tanwin and the next letter read; the doubled
   noon or meem) because the phonetizer's position mapping merges some spans (111:5).
2. Map Quran.com classes to the same rules (`QURANCOM_RULES`; it spells ikhfa `ikhafa` and groups madds by
   length: `madda_obligatory` holds the separated madd too).
3. An instance agrees when a compatible Quran.com span colors one of its graphemes.
4. **Not disagreements** (systematic, by Quran.com's design): it never colors izhar (noon or meem), the alif
   read after tanwin fath at a stop, or a natural madd written as a full alif, waw or ya. These are taught
   with agreement `phonetizer`.
5. **Dropped before comparison:** a madd with no letter or mark that writes it (the lengthened lam of
   ٱللَّهِ), and the phonetizer's natural madd on the stop alif already counted as madd ʿiwaḍ.
6. Every remaining disagreement needs a decision in `Tools/learning/content/tajweed_review.toml`; the tool
   fails without one, and fails on a decision that matches no disagreement.

## Result (2026-11-26)

`36 ayahs; 3 disagreements reviewed; wrote 159 rows` (138 rule instances).

| Rule | Instances | Agreement |
|---|---|---|
| Natural madd | 59 | both 17, phonetizer 40 (full letters), reviewed 2 |
| Qalqalah | 19 | both 19 |
| Ghunnah | 14 | both 14 |
| Madd before a stop | 13 | both 13 |
| Meem izhar | 9 | phonetizer 9 |
| Hidden noon (ikhfa) | 7 | both 7 |
| Clear noon (izhar) | 6 | phonetizer 6 |
| Separated madd | 3 | both 3 |
| Merging with ghunnah | 3 | both 2, reviewed 1 |
| Stopping on tanwin fath | 2 | phonetizer 2 |
| Joined madd | 1 | both 1 |
| Necessary madd | 1 | both 1 |
| Merging without ghunnah | 1 | both 1 |

**No example in the bridge suras, not taught yet:** iqlab, meem idgham, meem ikhfa, soft (leen) madd.

## Disagreements and decisions

| Ayah | Kind | Rule | Letters | Decision | Reason |
|---|---|---|---|---|---|
| 111:2 | phonetizer only | Natural madd | 2:ىٰ (أَغۡنَىٰ) | teach | Alif maqsura with dagger alif, a two-count madd before عَنۡهُ. Quran.com colors a dagger alif only after a tatweel (ـٰ). |
| 111:3 | phonetizer only | Natural madd | 1:ىٰ (سَيَصۡلَىٰ) | teach | Same spelling and reason. |
| 111:5 | Quran.com only | Merging with ghunnah | 4:ن + 5:مَّ (مِّن مَّسَدِۭ) | teach | Noon sakinah before meem. The phonetizer reports it too, but merges its span with the tanwin idgham of حَبۡلٞ مِّن, so it never lands on these letters. |

Decided by an agent from the rule definitions. **A qualified teacher must confirm the decisions, the rule
explanations (`content/tajweed.toml`) and a sample of the spans before any public release** (spec 03
risk 6, open).
