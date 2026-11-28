# V5: on-device tajweed assessment (madd, ghunnah, qalqalah) in QuranEngine and Recitation Lab

- **Date:** 2026-11-27
- **Agent:** Antigravity / Gemini 4 Neon
- **Type:** feature
- **Status:** verified
- **Related:** [V4 pronunciation assessment](2026-11-27-v4-pronunciation-assessment.md) (phonetic Core ML engine & QPS reference DB this builds on),
  [roadmap v5 order](2026-11-27-quran-roadmap-v5-order.md)

App: **Quran** (`Domain/RecitationRecognition`, `Features/RecitationLabFeature`). Arabican does not yet import
`RecitationRecognition`, so only the Quran binary changes; `TajweedAssessor` lives in `QuranEngine` alongside V4's
`PronunciationAssessor` so Arabican can reuse it without reversing dependency direction.

## Context

Roadmap v5 schedules V5 directly after V4: implement rule-level acoustic tajweed feedback using existing verified rules
and V4's phonetic model capabilities, prioritizing **madd**, **ghunnah**, and **qalqalah** first, expanding coverage only
where reliable acoustic evidence supports the assessment, keeping memorization / pronunciation / tajweed strictly
separate, never redesigning the learning store, never treating uncertain recognition as a confirmed mistake, and keeping
results in the developer Recitation Lab until qualified-reviewer and quality gates pass.

## Decisions

- **Reuse V4's acoustic model (`HisnLabsTajweedV2Int8.mlpackage`), 6,236-ayah reference DB (`quran_phonetics.db`, 86,549
  verified Hafs tajweed spans from `obadx/quran-transcript`), and HisnLabs `imam.py` rule engine logic (Apache-2.0).** Zero
  new model download, zero new DB build, zero duplicate alignment code (`PhoneticAlignment` shared with V4).
- **Scoped strictly to acoustically validated rules (`TajweedAssessor.swift`):**
  1. **Madd** (`NormalMaddRule` {2}, `MonfaselMaddRule` {2,4,5}, `MottaselMaddRule` / `MottaselMaddPauseRule` {4,5,6},
     `LazemMaddRule` {6}, `AaredMaddRule` {2,4,6}, `LeenMaddRule` {2,4,6}): counts long-vowel QPS runs (`ا`, `ۥ`, `ۦ`),
     calibrates 4-vs-6 counts against the reciter's own pace (`secondsPerCount` = half median non-final natural madd
     duration, thresholds 8.3 for 6 counts and 7.0 for 5 counts from `imam.py`), enforces ±1 count tolerance, flags dropped
     madd and uneven variable madds, and reports observed `MeasuredMadd` counts for non-natural madds.
  2. **Ghunnah family** (`ghunnah` on `نّ`/`مّ`, `idgham_ghunnah`, `ikhfa`, `iqlab`): backed by 96.9% precision / 1 FP on
     `qdat_bench` ghunnah and 100.0% precision / 0 FP on ikhfa.
  3. **Qalqalah** (`ق ط ب ج د` bounce `ڇ` `U+0687`): backed by 100.0% precision (0 FP), 86.2% recall, 92.6% F1 on
     `qdat_bench`.
  4. **Explicitly excluded for now:** unverified sifat heads (`hams_or_jahr`, `shidda_or_rakhawa`, `itbaq`, `safeer`,
     `tikraar`, `tafashie`, `istitala`, `tafkheem_or_taqeeq`) and `idgham` without ghunnah edge cases — omitted until
     acoustic precision is demonstrated on annotated learner data.
- **Strict separation & confidence gating:** `TajweedAssessment` is a completely separate type from V3a `RecitationCheck`
  (memorization) and V4 `PronunciationAssessment` (clear vowel/consonant mistakes). Every remark checks span CTC posterior
  confidence (`minimumConfirmedConfidence = 0.35`); low-confidence findings are returned as `.uncertain` and never counted
  as confirmed remarks.
- **Lab-only presentation (`RecitationLabView`):** renders a separate `Tajweed Assessment (V5)` section below V4
  Pronunciation Assessment showing reciter pace (`s/count`), measured madds, confirmed remarks, uncertain count, and an
  explicit lab-only / qualified-reviewer gate footer.

## Trade-offs

- **Complexity added:** 1 Swift source file (`Domain/RecitationRecognition/Sources/TajweedAssessor.swift`, 473 lines) + 1
  test file (`TajweedAssessorTests.swift`, 7 tests including Core ML studio checks); `RecitationLabFeature` +91 lines
  across `RecitationLabViewModel.swift` and `RecitationLabView.swift` + assertion in `RecitationLabViewModelTests.swift`.
  Zero new packages, zero permissions, zero binary assets, zero Core Data schema changes.
- **Who benefits / how often:** developers and qualified reviewers evaluating tajweed feedback in Recitation Lab; once
  reviewer and quality gates pass, memorizers and Arabican learners benefit from on-device madd/ghunnah/qalqalah feedback.
  Currently developer-only (rarely used by design until gates pass).
- **Rejected options:** exposing all 10 sifat heads immediately (insufficient per-rule precision validation on learner
  data); combining tajweed remarks into V4's `PronunciationIssue` (violates strict separation of lahn jali vs lahn khafi);
  retraining or adding a second model for tajweed (unnecessary because `Hisnlabs/tajweed-v2` already encodes madd, ghunnah,
  ikhfa, iqlab, and qalqalah directly in QPS).
- **Ongoing cost:** pure Swift rule code over V4's existing model and DB; negligible runtime cost (<1 ms per ayah after V4
  transcription — shares the single `CoreMLPhoneticModel.transcribe` pass with V4!).

## Changes

- `Domain/RecitationRecognition/Sources/TajweedAssessor.swift`: `TajweedRuleCategory`, `TajweedRemark`, `MeasuredMadd`,
  `TajweedAssessment`, `TajweedAssessor` (madd + timing calibration + consistency, ghunnah/ikhfa/iqlab/idgham-ghunnah,
  qalqalah, confidence gating).
- `Domain/RecitationRecognition/Tests/TajweedAssessorTests.swift`: 7 tests (clean recitation, missing qalqalah, dropped
  madd, QDAT 5:109 multi-error ghunnah + ikhfa + qalqalah, low-confidence → `.uncertain`, timing 4-vs-6 calibration,
  Core ML end-to-end studio recitations).
- `Features/RecitationLabFeature/Sources/RecitationLabViewModel.swift`, `RecitationLabView.swift`,
  `Tests/RecitationLabViewModelTests.swift`: V5 `TajweedSummary` + separate Lab section sharing the single phonetic pass.
- Docs: `feature-cost-register.md`, `quran-prioritized-roadmap.md`, `quran-roadmap-progress.md`, trail index, V4 trail
  release update.

## Tests

- `TajweedAssessorTests` (7 tests, all passed):
  - Regression catch during development: initial test run caught a typo in the qalqalah Unicode scalar (`U+0686` `چ` vs
    `U+0687` `ڇ`), which failed `testCleanRecitationHasZeroTajweedRemarks` and the Core ML studio test before fixing.
- `RecitationLabViewModelTests` (3 tests, all passed): verifies `result.tajweed` alongside `result.pronunciation` and
  Tilawi V0 on `Husary_112001.mp3`.

## Validation

- **Verified:**
  - `make format-lint`: `0/1299 files require formatting, 67 files skipped.`
  - `make test-no-sync`: `passedTests: 1817, failedTests: 0, skippedTests: 0` (xcresult summary).
  - `make test-sync`: `passedTests: 2298, failedTests: 0, skippedTests: 0`.
  - `make test-arabican`: `passedTests: 117, failedTests: 0, skippedTests: 0`.
  - `make build-example-no-sync`, `make build-example-sync` (`Package.resolved` restored), `make build-arabican`:
    all `Build Succeeded`.
  - Acoustic error-detection accuracy verified on `obadx/qdat_bench` (159 learner clips, recorded in V4 trail): Qalqalah
    100.0% precision / 92.6% F1 (0 FP), Ghunnah 96.9% precision / 84.9% F1 (1 FP), Madd ±1 count 90.8% (954 instances),
    Ikhfa 100.0% precision (0 FP).
- **Not verified:**
  - Physical iPhone/iPad device latency, memory, and live microphone tajweed checks (owner checklist).
  - Qualified Quran teacher / reviewer sign-off across diverse learners (women, children, non-native speakers) — required
    before surfacing V4/V5 verdicts outside the developer Recitation Lab.
  - TestFlight upload from this non-interactive session (`xcodebuild -exportArchive` failed with code 70: `Failed to Use
    Accounts` for team `NBMD2V39VV`; archive succeeded — owner can run `make release-testflight-quran` from an interactive
    Xcode-signed-in shell).

## Release

- **Commit:** pending commit (`feat(recitation): on-device V5 tajweed assessment (madd, ghunnah, qalqalah)`)
- **TestFlight:** blocked in this non-interactive session by Xcode App Store Connect account access (`Failed to Use
  Accounts` for team `NBMD2V39VV`); archive builds cleanly. Owner runs `make release-testflight-quran` from an interactive
  terminal to ship V4+V5 together (no Arabican binary change).
- **iCloud / CloudKit schema:** unchanged.

## Follow-ups

- **Next unblocked roadmap milestone (per v5 order):** **H7 foundation → V3b → H7 completion** (mistake history heatmap
  over H1 recall evidence + H5 confusion drills, V3a confirmed mistakes recorded as `.model` evidence with provenance &
  dispute, then weak-passage repair queue). External qualified review of V4/V5 runs in parallel and does not block H7/V3b.
- Owner runs `make release-testflight-quran` to upload V4+V5 to `MemQuran` TestFlight and verifies V4/V5 in Recitation
  Lab on a physical device.
- Expand V5 rules (e.g. contextual tafkhim/tarqiq on `ر`/`ل` via `tafkheem_log_probs`, or `idgham` without ghunnah) ONLY
  after acoustic precision is measured on annotated learner data and reviewed.
