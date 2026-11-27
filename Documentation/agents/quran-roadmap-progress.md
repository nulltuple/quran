# Quran roadmap progress and session handoff

The live status of [quran-prioritized-roadmap.md](quran-prioritized-roadmap.md). Every session that
works on the roadmap updates this file in the same commit as its code. A new session starts here:
read **Handoff** first, then the trail entries it names.

Milestone ids follow roadmap v2 (2026-11-26); §8 of the roadmap maps the old M ids.

Statuses: `not started`, `in progress`, `blocked`, `verified` (tests pass locally, not yet
released), `shipped` (pushed to `origin/main` and uploaded to TestFlight). A milestone is `shipped`
only when every work item is, and its exit criteria are met; device checks the owner must do are
listed under **Owner checklist**, not counted as done.

## Handoff

- **Latest session (2026-11-27, H3 memorization map and passage review queue — Antigravity / Gemini 4 Neon):**
  **H3 is verified and pushed at `4ddf13a8` (TestFlight upload blocked on Xcode Accounts sign-in)** (trail
  [2026-11-27-h3-memorization-map-and-review-queue.md](../trail/2026-11-27-h3-memorization-map-and-review-queue.md)):
  - Archive succeeded for `Quran 1.20.3 (1025)`, but `xcodebuild -exportArchive` failed (70): `Failed to Use Accounts`
    for team `NBMD2V39VV`. Once the owner re-signs in to Xcode > Settings > Accounts, run `make release-testflight-quran`
    and `make release-testflight-arabican` (ships both V2b `0054f9ce` and H3 `4ddf13a8`).
  - `Model/QuranKit`: `AyahRangeSet` canonical range algebra (`union`, `subtracting`, `intersection`, `contains`,
    O(suras) `verseCount`).
  - `Data/CoreDataModel` `Quran 5` (lightweight migration tested from `Quran 4`) & `MemorizationPersistence`:
    CloudKit-compatible `MO_MemorizedRange` and `MO_Passage` with tombstones (`removedOn`) and `snoozedUntil`.
  - `Data/BackupPersistence` & `Domain/BackupService`: backup schema 3 (`memorizedRanges`, `passages`, schema 1
    and schema 2 files still restore, merge carries removals and newer snoozes, preview row in Settings).
  - `Domain/MemorizationService`: `PassageSplitter` (sura-first, page/half-page splits), `ReviewQueue` (Sabaq /
    Sabqi / Manzil buckets derived from FSRS + declarations, `ReviewBudgetStore` daily budgets 2/4/5, reasons
    including `"Weak · N sessions"`, `"Due N days ago"`, `"Declared · Not tested yet"`, skip/reschedule/split/reset),
    and `MemorizationMapSummary` (Juz → Surah → Ayah, declared vs demonstrated kept strictly apart).
  - `Features/HifzReviewFeature` + `HomeFeature` + reader wiring: Memorization section under Continue Reading on
    Home (`Review & Memorization Map` + `Start Next Review`), segmented Queue / Map screen, Quick Declare sheet
    (Surah / Juz / Pages), Daily Budgets / Reschedule / Split sheets, Reset & Remove confirmation alerts, and
    direct H2/V2b Practice launch on exact passages (`QuranInput.initialPracticeRange`,
    `QuranNavigator.navigateToPractice`, `HifzPracticeBuilder.build(passage:)`).
  - 74 keys × 16 localization catalogs (`LocalizationTests` 53/53 passed).
  - Full suites: no-sync 1,776, sync 2,257, Arabican 117, tools all passed (0 failed, 0 skipped); all 3 app builds
    succeeded; simulator end-to-end verified in Light/Dark, Portrait/Landscape, and AX-XL (including direct H2/V2b
    Practice launch on Al-Ikhlāṣ 112:1–4).
  - **Next: H4 (Spot tests with strict and granular scores).** To resume in a new session, read `AGENTS.md`, this
    Handoff, the H3 trail, and roadmap §6 H4, then build H4 (random-start seeded exams over memorized/custom ranges
    and presets Warm up / Weakest / Due / Recent / Old, count or timer, hidden location option, strict/word-recall/
    coverage/assistance scores, temporary tests never changing history).

- **Earlier session (2026-11-27, V2b live reveal in Practice — Antigravity / Gemini 4 Neon):**
  **V2b is verified (pending TestFlight upload — Xcode App Store Connect account sign-in was required at 13:23)** (trail
  [2026-11-27-v2b-live-practice-reveal.md](../trail/2026-11-27-v2b-live-practice-reveal.md)): hands-free automatic word
  reveal and ayah progression inside H2 Practice using V2a's 8 s / 1 s streaming path with `PracticeRecitationTracker`
  (bounded lookahead within the practice stretch, skip guard, 1-/2-word ayah thresholds, `RecitationMicrophone.clearBuffer()`
  on cumulative step jumps, off-track detection after 3 speaking misses). Manual override always wins (hints/peeks never
  un-reveal and record `.hint`, Check / Listen & Repeat / backgrounding stop the mic, reader mic button toggles Practice
  live recitation); auto-advanced ayahs save `.model` provenance (draft v2, backward-compatible with v1). Also fixed
  H2c's AX-XL double-scaled Arabic font size and stacked action rows at accessibility sizes.
  Full suites: no-sync 1,757, sync 2,238, Arabican 117 passed (0 skipped, Core ML model tests executed); simulator UI
  verified with simulated microphone (`Husary_112001..112004.mp3`) in Light/Dark, Portrait/Landscape, and AX-XL.

- **Earlier session (2026-11-27, H2c verification & release — Gemini 4 Neon, continuing from Codex Astra High `509fceca`):**
  **H2 slice c is verified and shipped** (trail
  [2026-11-27-quran-h2c-reader-practice.md](../trail/2026-11-27-quran-h2c-reader-practice.md)): translation-view practice
  (hidden Arabic/word-by-word content, optional per-ayah Show Meaning hint counting once as help, Check shows Arabic even
  when normally hidden), line-page Mushaf masking (printed spans masked in place, canonical word cues in the practice bar),
  forward and backward page transitions driven by the mask's reciting ayah, and edition-aware draft resumption.
  Commit `509fceca` uploaded as **Quran 1.20.3 (1022)** (`MemQuran`) and **Arabican 0.1.0 (1022)** (`Arabican`).
  Full suites: no-sync 1,742, sync 2,223, Arabican 117 passed (0 skipped, CoreML model tests executed); simulator UI verified
  in Light/Dark, Portrait/Landscape, and Accessibility Extra-Large Dynamic Type on iPhone 18 Pro Max (left on Madani Mushaf
  1439 in Arabic mode, Light, Large text). **H2 (slices a–c) is complete. Stopped at the owner-review checkpoint before V2b.**

- **Previous handoff:** 2026-11-27 (fourteenth session), Claude Code / claude-opus-5-5. This session built **H2 slice b**
  (trail [2026-11-27-h2b-practice-listen-cues-cumulative-resume.md](../trail/2026-11-27-h2b-practice-listen-cues-cumulative-resume.md)):
  listen and repeat through the audio banner, mistaken words picked in the practice bar, cue levels, cumulative order, and
  resume after kill from a user-defaults draft. The thirteenth session built **H1 + H2 slice a**
  (trail [2026-11-27-h1-h2a-learning-store-and-practice.md](../trail/2026-11-27-h1-h2a-learning-store-and-practice.md)):
  Core Data `Quran 4` (practice sessions, append-only recall evidence with manual/model provenance), `MemorizationService`
  with swift-fsrs 6.0.0 replayed from evidence, backup schema 2, and ayah menu → Practice with masks on the page image.
  The twelfth session built **V3a recite and
  check** (trail [2026-11-27-v3a-recite-and-check.md](../trail/2026-11-27-v3a-recite-and-check.md)): ayah menu → Recite to
  Check sheet, `RecitationChecker` (Domain) with a quality gate on planted mistakes, and a **simulated microphone** for
  hands-on checks without speaker or room noise (Gotchas). The eleventh session built **V2a live follow in
  the reader** (trail [2026-11-27-v2a-live-follow.md](../trail/2026-11-27-v2a-live-follow.md)): a microphone button in the
  reader, `RecitationFollower` (Domain) tracking the place from 8 s windows every second, the recited word highlighted on
  the audio path. The tenth session reordered the roadmap (v4: voice track first, trail
  [2026-11-27-quran-roadmap-v4-order.md](../trail/2026-11-27-quran-roadmap-v4-order.md)) and
  built **V1 voice search** (trail [2026-11-27-v1-voice-search.md](../trail/2026-11-27-v1-voice-search.md)). The ninth
  session finished **V0**'s engine work:
  slice (b), recited words aligned to canonical `Word`s with frame timing (trail
  [2026-11-27-v0-word-alignment.md](../trail/2026-11-27-v0-word-alignment.md)), and slice (c), the developer Recitation
  Lab with live microphone recognition (trail [2026-11-27-v0-recitation-lab.md](../trail/2026-11-27-v0-recitation-lab.md)).
  Slice (a), the on-device engine itself, is in [2026-11-26-v0-recitation-engine.md](../trail/2026-11-26-v0-recitation-engine.md)
  (research table, runtime findings, benchmarks, per-use recommendation; read it before any V work). Earlier C2, F2 and
  C1 trails are linked from the milestone table.
- **Roadmap v2 (2026-11-26):** [quran-prioritized-roadmap.md](quran-prioritized-roadmap.md) now
  reconciles v1 (M1–M15) with Codex's Tarteel research (stored at
  [research/2026-11-26-tarteel-competitive-research.html](research/2026-11-26-tarteel-competitive-research.html)).
  New area-based IDs (F, R, C, H, V, P); §8 maps old M and Q ids. Trail:
  [2026-11-26-quran-roadmap-v2.md](../trail/2026-11-26-quran-roadmap-v2.md).
- **Roadmap v3 order (owner, 2026-11-26):** C2 → V0 Quran AI Engine → V1 voice search → H1+H2 → V2 → H3–H5 →
  H7 foundation + V3 → remaining (P1, H6, H7 completion, C3, P2, M2). V1–V3 are committed objectives; V0 is not a
  go/no-go spike. Roadmap §5 and §6 V0; trail
  [2026-11-26-quran-roadmap-v3-order.md](../trail/2026-11-26-quran-roadmap-v3-order.md).
- **Roadmap v4 order (owner proposal, accepted with two changes, 2026-11-27):** V1 → V2a → V3a → H1+H2 → V2b → H3–H5 →
  H7 foundation + V3b → V4 → V5 → remaining (P1, H6, H7 completion, C3, P2, M2). V2 and V3 are split: their standalone
  halves (V2a follow in the reader, V3a recite-and-check) come first; V2b (reveal in Practice) needs H2 and V3b (mistake
  history) needs H1/H7. V4/V5 (phoneme and tajweed assessment, reviewer-gated) come after the Hifz loop, not before it.
  Roadmap §5 and §6 voice track; trail [2026-11-27-quran-roadmap-v4-order.md](../trail/2026-11-27-quran-roadmap-v4-order.md).
- **State of the tree:** H3 at `4ddf13a8` (no-sync 1,776, sync 2,257, Arabican 117 passed; TestFlight pending Xcode sign-in); V2b at `0054f9ce` (no-sync 1,757, sync 2,238, Arabican 117 passed; TestFlight pending Xcode sign-in); H2c at `509fceca` (Quran 1.20.3 and Arabican 0.1.0 build 1022; no-sync 1,742, sync 2,223, Arabican 117 passed).
  Before it, H2b at `5a58c0d3` (Quran and Arabican build 1020; no-sync 1,736, sync 2,217, Arabican 117 passed).
  Before it, H1 + H2a at `722d5999` (Quran and Arabican build 1018; no-sync 1,719, sync 2,200, Arabican 117 passed).
  Before it, V3a recite and check at `b5d48dfd` (Quran build 1015; no-sync 1,691, sync 2,171, Arabican 117 passed). Before it, V2a live follow at `b6f14d8d` (Quran and Arabican build 1013; no-sync 1,667, sync 2,146, Arabican 117 passed). Before it, V1 voice search at `c5c8815b` (Quran and Arabican build 1011; no-sync 1,644, sync 2,123, Arabican
  117, all passed). Earlier: V0 (b) at `5b3a6c65`; V0 model download (D7) at `d5d7d7df` (Quran build 1008; no-sync 1,627, sync 2,106, Arabican 117, all passed). V0 (c) at `78c09e45` (Quran build 1006; no-sync 1,623/1,623, sync 2,102/2,102,
  Arabican 117/117, all passed; no Arabican build, it imports no changed module). The model is not in git: `make recitation-model` builds `.cache/recitation-model/TilawiFastConformerInt8.mlpackage`
  (Python 3.12 via `uv`, ~1 GB); without it the model-backed tests skip. Before V0 (b): minimum iOS 27.2 at `3a955eea`
  (build 1003), V0 (a) at `c061ba9b` (build 1001).
- **Owner decisions so far:** M2 skipped for now (2026-11-25). Local collections go in Core Data, not
  MobileSync, and the TestFlight build stays no-sync (2026-11-25). Licensing does not restrict reuse
  (2026-11-25). Roadmap v3 order (owner, 2026-11-26; replaces v2's "Hifz before AI"). **D7 decided (2026-11-27):** the
  recitation model is a GitHub release asset, published as `recitation-model-1`; never delete or replace it (builds pin its
  sha256), publish `recitation-model-2` for a new model. **D2 approved (2026-11-27):** swift-fsrs (exact pin 6.0.0, as Arabican's) may be used in the root package for H1's
  passage scheduling. **D1 decided (2026-11-27):
  minimum iOS 27.2 for both apps** (trail [2026-11-27-minimum-ios-27-2.md](../trail/2026-11-27-minimum-ios-27-2.md));
  no availability checks or fallbacks for 27.2 or earlier (AGENTS.md, Identity and branding). **D4 approved (2026-11-26):**
  microphone permission, evaluating and integrating local inference dependencies, downloading publicly available
  models and evaluation datasets; family recordings optional, never blocking. D6 (2026-11-26): English Ibn
  Kathir (169) and Bengali Ahsanul Bayaan (165), hosted as the `tafsir-packs-1` GitHub release of
  `nulltuple/quran`; publishing further release assets for new packs follows the same approval.
- **To resume in a new session:** "Continue the Quran roadmap from
  Documentation/agents/quran-roadmap-progress.md, starting with the first item under Next steps."
  Read AGENTS.md (this repo's CLAUDE.md), then this Handoff, then the trails it names.
- **Gotchas:**
  - `make build-example-sync` rewrites `Package.resolved` with the MobileSync pins; main keeps
    the no-sync form. Run `git checkout -- Package.resolved` after it and stage paths explicitly
    (never `git add -A`), or the release script refuses to upload.
  - `make preview` needs the `build-ios-apps` Codex plugin, which is not installed. To look at a
    SwiftUI view, render it with `ImageRenderer` from a temporary test that writes PNGs to the
    scratchpad, then delete the test (M1.4 trail, Validation).
  - Test counts: `make test-*` prints one `Executed N tests` line per target; read the total with
    `xcrun xcresulttool get test-results summary --path <the .xcresult the log names>`.
  - Every new `Localizable.strings` key must be in all 16 catalogs: `LocalizationCatalogTests` fails otherwise
    (F2's first full run did).
  - `make release-testflight-*` refuses a dirty tree: commit, or set in-progress files aside, before releasing.
    Package test runs compile at their start, so don't edit Swift while a `make test-*` chain runs.
  - The simulator's Quran app also has English Ibn Kathir downloaded and selected in the reader (C1 EN/BN check),
    and a `Quran Backup 2026-11-26.json` in Files (F2 check).
  - The simulator's Quran app has Sahih International and Arabic Muyassar downloaded and selected (C1 check),
    is in Translation/Tafseer mode, and was left on Mushaf "Madani 1441" (R1 check); switch back to Hafs 1405
    in Settings > Choose Mushaf if a check needs the default edition.
  - To inspect a remote zip without downloading it, list it with HTTP range reads (Python `zipfile` over a
    seekable ranged-GET file object; the R1 trail, Research, describes it).
  - Taps inside the reader's content must not block the page's UIKit long press (ayah menu): use
    `simultaneousGesture(TapGesture())`, not `onTapGesture` (C2 trail, Decisions).
  - The simulator's Quran app has word-by-word meaning set to English (C2 check). After the C2 c2 check it is on
    Mushaf Hafs 1405 with the word pointer on, in Arabic (page) mode.
  - `make build-example-no-sync` builds for a device (`Debug-iphoneos`); to try a change in the simulator use
    `make run-example-no-sync`, which builds for the simulator and installs it. To read the app's logs (swift-log to
    stderr), relaunch it with `xcrun simctl launch --console-pty <udid> com.nulltup.memquran > <file>` in the background.
  - A simulated tap within ~0.5 s of a pointer release used to be dropped (the spring animation blocked touches); the
    release animation now allows interaction. Taps on the reader's page also go to `QuranView`'s bar-toggling tap
    recognizer: overlays that need a tap should be `UIControl`s (a button wins over an ancestor's tap recognizer).
  - V0: ONNX Runtime's GitHub repos and iOS pod host are gone or broken (since about 2026-11-17); Core ML float16 compute
    gives `<unk>` on the CPU (the simulator's only Core ML device), so the model computes in float32. The Python env for
    `Tools/recitation-model.py` must be 3.12 with the pinned `torch==2.7.0` (coremltools 9 is untested with newer torch).
    `VerseMatcherRecitationTests` takes ~50 s in a debug build (350 identifications; allowance 300 s); don't run model
    benchmarks while a test suite runs (CPU contention trips the 60 s per-test limit).
  - Recitation Lab on the simulator: copy the model with
    `D=$(xcrun simctl get_app_container <udid> com.nulltup.memquran data)`, then `.cache/recitation-model/TilawiFastConformerInt8.mlpackage`
    and `source/vocab.json` into `"$D/Library/Application Support/RecitationModel/"`; grant the mic with
    `xcrun simctl privacy <udid> grant microphone com.nulltup.memquran`; turn the lab on with
    `xcrun simctl spawn <udid> defaults write com.nulltup.memquran showDeveloperTools -bool YES`. The simulator records
    from the Mac's microphone: playing a fixture with `afplay` works only if the Mac's output is not muted. The simulator's
    app currently has the model installed and Developer tools on. "Enable debug logging" is always on in every build
    (`Container.isDebugLoggingAlwaysEnabled`), so never gate tester-hidden features on it.
  - **Simulated microphone (debug builds, use this instead of `afplay`):** launch the app with
    `xcrun simctl launch <udid> com.nulltup.memquran -RecitationSimulatedInput /abs/a.mp3,/abs/b.mp3` and every
    recording (voice search, live follow, recite and check, the lab) plays those files in real time, each after 1 s of
    quiet floor, then quiet until stopped: no speaker, microphone or room noise. `make run-example-no-sync` builds Debug.
    Build a planted mistake by listing fixtures with one left out (V3a trail, Validation).
  - V1 voice search on the simulator: Search tab → mic button (top right). The Mac microphone hears room noise of
    0.02–0.10 peak and `afplay` fixtures reach it at only ~0.1, so the pause detector is marginal there (it stopped on its
    own in one of three tries); play the fixture only after "Listening…" appears, or tap Search Now. To read levels, add a
    temporary `logger.debug` in `VoiceSearchViewModel.startListening` and relaunch with `--console-pty` (see above).
  - A task that ends itself must not call a method that cancels its own `Task` handle: V1's first auto-stop cancelled the
    listening task it ran in, and Core ML recognition then threw `CancellationError` (V1 trail, Decisions).
  - V2a live follow on the simulator: open page 604 (Recent pages), tap the reader's microphone (top right; the first tap
    after the reader opens is sometimes dropped, tap again), then `afplay Domain/TestResources/Sources/test_data/recitation/Husary_11200{1,2,3,4}.mp3`
    one after another. The Mac microphone's room noise can show "Lost your place" during a pause (V2a trail, Not verified).
  - H2 practice on the simulator: page 604 (Recent pages), long press 112:1 (the first long press after the reader opens
    is sometimes dropped; repeat it) → Practice. Taps on the practice bar while it slides in are dropped: wait a moment.
    The ayah menu's rows also drop a tap while the menu animates in: tap Practice again. The simulator's app has the cue
    level set to "First Word of Each Ayah" (H2b check; options button left of ×). Listen and repeat plays through the Mac's
    speakers (it is output, not the microphone): check it by the Listen/Stop button and the playing-ayah highlight, and
    don't leave it running. The draft is `hifzPractice.draft` in
    `$(xcrun simctl get_app_container <udid> com.nulltup.memquran data)/Library/Preferences/com.nulltup.memquran.plist`
    (`plutil -p`); `simctl spawn … defaults read` does not see the app's domain.
    Practice data lives in the Core Data store (`MO_PracticeSession`, `MO_RecallEvidence`); the simulator's app has a few
    sessions from the H1 check.
  - Only the iPhone 18 Pro Max simulator (AGENTS.md "Simulator"); never run two package test runs
    at once (no-sync, then sync, then Arabican if a shared module changed).
- **Next steps, in order** (roadmap v4 §5):
  1. **H4 — Spot tests with strict and granular scores:** sources (memorized ranges, custom ranges, presets Warm up,
     Weakest, Due, Recent, Old), random start with seeded sampler in `MemorizationService`, question length in ayahs
     or lines, count or timer, start cue, hidden location option, manual reveal and grade (hint/skip recorded),
     strict / word-recall / coverage / assistance scores (no score when denominator is zero), temporary tests never
     changing history.
  2. **H5 — Similar verses and confusion drills:** QUL similar-ayah / mutashabihat cross-checked against our n-gram
     index over normalized canonical tokens, side-by-side RTL compare sheet, drills saving confusions as evidence.
  3. **H7 foundation + V3b:** mistake history heatmap and repair queue; V3a mistakes recorded as `.model` evidence
     with dispute (`retractEvidence`).
  4. Owner device benchmarks (checklist items 23 and 25): latency, memory (simulator footprint ~852 MB after recognition; if a
     phone is far above ~500 MB, try the int4 package or the float16 fix for the Neural Engine), battery for 10 minutes of
     live follow.
  5. V3a follow-ups (trail): VoiceOver verdicts per marked word; CTC forced alignment of the expected text; insertions
     as mistakes only if the owner wants them.
  6. V0 research follow-ups (slice a trail): the Whisper comparison (`eval --backend whisper --n 20`), the CPU float16
     fault, phoneme model (`obadx/muaalem-model-v3_2`, now V4).
  7. Open from R1: IndoPak has no verified pack (blocked); optional carry-over of the reading position by ayah when
     switching editions.
  8. Small optional follow-ups: native review of agent translations (F2's 24 `backup.*` keys, C2's 17
     `word_study.*` keys, V1's 30 `voice_search.*`, V2a's 9 `recitation_follow.*`, V3a's 16 `recitation_check.*`,
     H3's 74 `hifz_review.*`); the C2 translation-view landing of a
     navigated verse at ~45% (under a medium sheet, `UI/NoorUI/Sources/Features/Quran/QuranScrollingViewModifier.swift:103`);
     teacher review of `Grammar.strings`; keep tafsirs out of the reader's translation picker; more tafsir packs (Bengali
     166/164, English 168) with `Tools/build-tafsir-pack.py`; Arabican's `Tools/learning/morphology.py` could read the shared
     `quran_morphology.db`; a Settings row to delete the recitation model.
- **Inputs a rebuild needs** (none are in git; `Tools/build-qul-word-data.py` docstring has usage):
  - Word study morphology: QAC v0.4 `quran-morphology.txt` from
    `https://raw.githubusercontent.com/mustafa0x/quran-morphology/8f38b39016824284f9ed16ae15069ff9102c4acf/quran-morphology.txt`,
    sha256 `742bfac59941b2cb09736d5b7aae694af50792261fb8450cbf6afafcc340645f`; then
    `python3 -I Tools/build-quran-morphology.py <it> Example/QuranEngineApp/Resources/quran_morphology.db` and copy the
    result to `Domain/TestResources/Sources/test_data/` (the two copies must match; the output is reproducible, sha256
    `691564dc80a202b8daf8ec71b07435ff5de33d3ff1416262cc2201afed97a99b`).
  - Tafsir packs: `python3 -I Tools/build-tafsir-pack.py download 169 169.json` (and 165), then `build` and
    `zip` (docstring); the 2026-11-26 downloads' sha256 are in the C1 English/Bengali trail.
  - QUL recitation 411 SQLite, sha256 `3167adb2290dc137cfa594381a4051f5480bf3dfe646efd81d5e35cac86eb79b`
    (owner's `~/Downloads/surah-recitation-mishari-al-afasy.db.zip`).
  - QUL English wbw (translation 92), sha256 `7eb453613a199760a5c8e7b607999ac198ba7babb7c94fed47acecd2aba4b1ed`
    (`~/Downloads/english-wbw-translation.db.zip`).
  - QUL Bengali wbw (translation 94), sha256 `c7b46f28464ba80053f4e7c228f242897eddc45ce9a605ef73efb478fde85b4f`.
    The downloaded copy is gone (it lived in a cleared scratchpad); re-download it signed in to QUL
    and check the hash before rebuilding.
  - Quran.com words: `python3 -I Tools/fetch-quran-com-words.py download raw.json` then
    `normalize raw.json words.json`; the 2026-11-24 output had sha256
    `6eed196dd28585a8a734d42f0886e317a28c686c19548efa9082d0492fc4c13d` (6,236 ayahs, 77,429 words).

## Milestones

| ID | Work item | Status | Evidence | Commit / build |
|---|---|---|---|---|
| M1.1 | Canonical word identity and exact page-image mapping | shipped | 6,236/6,236 ayahs mapped from Quran.com KFGQPC v1 glyph codes (was 6,233 by width heuristic); heuristic agreed on all 6,230 ayahs both covered; QUL vs Quran.com English agree on 77,257/77,429 words, all 172 differences are wording of the same word (`those who(believe)`/`who`) plus one (`Mighty`/`Grave`, 18:5). `make test-tools` checks | 68a7fe6e, build 955 |
| M1.1 | Resolve the 6 translation-view and 3 image exceptions | shipped | 15:7, 27:20, 36:22, 37:130, 37:164, 41:47 regrouped by letter-level alignment (`uthmani_tokens`); 13:37, 37:130, 38:26 now mapped; 11:13 differs by one spelling (`ٱفۡتَرَىٰهُ`/`افْتَرَاهُ`), boundaries unchanged | 68a7fe6e, build 955 |
| M1.1 | Every word has English, Bengali, transliteration | shipped | 77,432/77,432/77,432/77,432; 2:181, 8:6, 13:37 realigned (QUL translations skip a word that QUL's recitation and Quran.com have) | 68a7fe6e, build 955 |
| M1.1 | Recitation segment cleaning | shipped | 451 out-of-order trailing segments, 32 outside the ayah, 15 stray leading, 3 inverted dropped; 21 late ayah starts corrected (e.g. 6:80 started 18 s late); 372 words have no segment of their own and keep the previous word highlighted | 68a7fe6e, build 955 |
| M1.2 | Word pointer on the unified data, legacy `words.db` retired | shipped | equivalent on all 8,454 glyphs `words.db` translated (24 wording differences, no identity differences); pointer now covers 6,236 ayahs (was 857) and follows the Bengali/English choice; preferences unchanged | 68a7fe6e, build 955 |
| M1.3 | No stale word after seeks (repeats, stepping) | shipped | `Player` drops times until its seek completes (`PlayerTests`) | 68a7fe6e, build 955 |
| M1.3 | Time observer only for reciters with word timings | shipped | `AudioRequest.reportsPlaybackTime` (`QuranAudioPlayerWordTests`) | 68a7fe6e, build 955 |
| M1.3 | Pause, speed, verse/range repeat, delays, stop, page change | shipped (unit-verified) | existing `QuranAudioPlayerWordTests`, `AudioPlayer` delay tests, `ContentRecitedWordTests`; by-ear timing UNVERIFIED (owner checklist) | 6597d965, build 951 |
| M1.3 | Manual scroll stops word-following until next ayah | shipped (unit-verified) | `ContentRecitedWordTests`; device feel UNVERIFIED | 6597d965 |
| M1.4 | Localization of the 14 remaining languages | shipped | `menu.word_by_word` in 14 catalogs and the reciter name in 12 `Readers.strings` (`tr`/`zh` have none); `testWordByWordStringsAreTranslatedInEveryLocalization`. Agent translations, native review UNVERIFIED | b664d566, build 957 |
| M1.4 | VoiceOver, Dynamic Type, RTL, iPad split view checks | shipped (view-verified) | fixed: at AX sizes a long meaning widened the ayah to 747 pt in a 320 pt column, now wraps (`QuranWordByWordTextTests`); word cells read Arabic then meaning, recited word reads as selected; RTL/Dark/AX5 checked by rendering the view. On-device VoiceOver and the app in split view UNVERIFIED (owner checklist 8–9) | b664d566, build 957 |
| M1.5 | Transliteration line in the translation view | shipped | off-by-default toggle (More menu, translation mode, meanings on); Arabic, italic transliteration, meaning; `ContentTranslationWordByWordTests`, `MoreMenuWordByWordTests`, `QuranWordByWordTextTests`, `WordByWordServiceTests` | cc0e776d, build 959 |
| M1.5 | Dual-language meanings (English and Bengali together) | blocked | owner decision: not built unless asked; doubles rows per word | |
| M2 | More synchronized reciters and resource packs | blocked | needs owner QUL downloads (**Blocked**) | |
| M3.1 | Audit of no-sync stores and sync-gated features | shipped | audit in the M3.1 trail entry: no-sync has notes, 5-color highlights, page bookmarks, recent pages (Core Data); verse collections, Favorites and named reading bookmarks are sync-only (MobileSync) | 88b60523 |
| M3.1 | Local verse collections store (Favorites + user collections), no login | shipped (no UI yet) | Core Data model `Quran 3` (lightweight migration from `Quran 2` tested), `CoreDataCollectionPersistenceTests` (11), `PersistenceAyahBookmarkCollectionServiceTests` (12); same API as the sync `AyahBookmarkCollectionService` | 88b60523, build 961 |
| F1 (M3.2) | Collection screens, Favorites and Bookmark action in the no-sync build | shipped | Bookmarks tab: My Collections + Page Bookmarks; ayah menu Bookmark row opens the collection editor; highlights stay note-based without sync (decision in the F1 trail). Tests: `LocalBookmarkCollectionsTests` (5), `AyahMenuLegacyViewModelTests` (+2), `LocalQuranAnnotationsObserverTests` (2). Page marks for collected ayahs not yet (follow-up) | c6406c8c, build 983 |
| F1 follow-up | Collection and note marks in the no-sync translation view | shipped | the ayah-number capsule shows ★ and note icons without sync, as in sync (the mushaf page marks only reading bookmarks, in both builds); a highlight alone gets no note icon. Tests: `VerseOverlaysCollectionIndicatorTests` (3), `AyahIndicatorTests` (2), `LocalQuranAnnotationsObserverTests` (+2), `NoteTests` (+1 no-sync), 3 translation tests un-gated; simulator: `2:2 \| ★` | 2fa15c38, build 986 |
| R1 | Mushaf editions via verified `ReadingRemoteResources` | shipped (IndoPak blocked) | Hafs 1421, 1439, 1440, 1441 and Tajweed from `files.quran.app` (paths, sizes, sha256, contents in the R1 trail); `QuranAppReadingRemoteResourcesTests` (4); simulator: 1441 downloaded and rendered. IndoPak: no verified pack | f1c4aa6b, build 986 |
| C1 | Tafsir sheet and Arabic tafsir packs | shipped (Arabic) | ayah menu "Tafsir" (page and translation modes) opens a sheet: tafsir picker, passage range and Quran text, next/previous skipping the passage; 11 feed tafsirs (`Translation.tafsirIDs`). Tests: `QuranTextDataServiceTafsirTests` (5), `TafsirViewModelTests` (6), `TafsirPreferencesTests` (3), `AyahMenuStudyRowsTests` (2), `versesReferencing` (1), ayah menu (+2); simulator: 2:1 → 2:2 with Muyassar | 2688bda9, build 988 |
| C1 (EN/BN) | English Ibn Kathir and Bengali Ahsanul Bayaan tafsir packs | shipped | owner D6: GitHub release `tafsir-packs-1` (packs built by `Tools/build-tafsir-pack.py` from Quran.com API v4 ids 169, 165); `Translation.supplementaryTafsirs` appended to the feed. Tests: `build-tafsir-pack.test.sh` (12), `TranslationsRepositoryTests` (+3); simulator: Ibn Kathir downloaded, 2:8–9 passage in the sheet | d4d1bd55, build 992 |
| F2 (M3.4) | JSON backup export/import with preview and merge/replace | shipped | Settings > Backup & Restore (no-sync): JSON schema 1, preview counts, merge (idempotent by natural key) or replace (one save). Tests: `CoreDataBackupPersistenceTests` (13), `BackupServiceTests` (10), `BackupViewModelTests` (6); simulator: export → Files → restore preview → merge | 34ce5a47, build 990 |
| C2 (a, b) | Full-Quran morphology database and word study sheet | shipped | `Tools/build-quran-morphology.py`: all 77,432 canonical words, 130,030 segments, 1,651 roots, 4,783 lemmas (2:181, 8:6, 13:37 `بَعْدَ مَا` split); ح م د 68, حَمْد 43 as QAC. Translation view word tap → sheet: segments, grammar in plain words, root and lemma counts. Tests: `build-quran-morphology.test.sh` (31), `WordStudyServiceTests` (8), `WordStudyFeatureTests` (8), `QuranWordByWordTextTapTests` (4), translation and content (+4); simulator: 1:1 ٱلرَّحْمَٰنِ sheet, long press still opens the ayah menu | f03021d8, build 994 |
| C2 (c1) | Occurrence list that moves the reader and returns | shipped | Root and Dictionary form rows open a paged list (50 per page, off the main actor; whole و list of 9,594 under 250 ms per page); an occurrence opens its study and moves the reader (`WordStudyReaderFollower`, `ContentViewModel.navigate(to:)`); dismissing returns it. Tests: `WordOccurrencesViewModelTests` (6), `WordStudyReaderFollowerTests` (4), `WordStudyViewModelTests` (+2), `ContentViewModelTests` (+1); simulator: ر ح م → 2:64 → Back → 1:1, رَحْمٰن → 19:18 → dismiss → 1:1 | 657f3385, build 996 |
| C2 (c2) | Tap-to-hear word, word pointer entry | shipped | Hear row plays the word's excerpt of the Afasy (1001) sura recording with its own `AVPlayer`, streamed unless downloaded, pausing the main recitation; the Mushaf pointer keeps a released word's popover 4 s and a tap opens its study. Tests: `WordRecitationRetrieverTests` (6), `WordStudyHearingTests` (6), `WordPointerViewModelTests` (+5), `WordTextServiceTests` (+2), `ByPassTouchesViewTests` (2); simulator: 1:1 streamed, 3:2 word 6 from the pointer | 9047de22, build 999 |
| V0 (a) | Recitation engine (Core ML), verse identification, benchmarks | shipped | Tilawi FastConformer CTC → Core ML int8 (125 MB, not bundled; `make recitation-model`); `RecitationRecognition` module. 350 EveryAyah clips, 7 reciters: top-1 350/350, CER 0.67% (≤20 s clips), 26 ms p50 per clip (M4 Pro); Swift matcher 350/350, 0 confident-wrong. Tests: `RecitationRecognitionTests` (25), `GRDBVerseTextPersistenceTests` (+1), `recitation-model.test.sh` (22) | `c061ba9b`, build 1001 |
| V0 (b) | Recited words aligned to canonical words, with frame timing | shipped (build 1006) | `WordAligner` + `ExpectedWordsReader` (Uthmani tokens via `WordByWordService.textLayouts`); 350 transcripts: 4,218/4,305 words matched (97.98%), each word once and in order; Husary 112:1 audio → 4 matched words with ordered frames. Tests: `WordAlignerTests` (10), `RecognizedWordTests` (4), `ExpectedWordsReaderTests` (4), `WordAlignerRecitationTests` (1), `CoreMLRecitationModelTests` (+3) | `5b3a6c65`, build 1006 |
| V0 (c) | Developer Recitation Lab (live microphone), simulator benchmarks | shipped (device benchmarks: owner) | Settings > Diagnostics > Developer tools (off by default) > Recitation Lab; model installed by hand until D7. Simulator: 11.5–14.1 s recognized in 267–281 ms, footprint ~852 MB; live mic heard 112:1 through the speakers and answered not confident. Tests: `RecitationModelStoreTests` (3), `RecitationAudioTests` (3), `RecitationLabViewModelTests` (2), `DiagnosticsViewModelTests` (+2) | `78c09e45`, build 1006 |
| V0 (D7) | Model published as GitHub release `recitation-model-1`, downloaded and checked in the app | shipped | `recitation-model-1.zip` 84,288,886 bytes, sha256 `a6c3ee79…c7e3`; the lab's Download button fetched, checked, unzipped and compiled it in the simulator (~6 s). Tests: `RecitationModelDownloaderTests` (4) | `d5d7d7df`, build 1008 |
| V1 | Offline voice search | shipped (device checks: owner) | Search tab mic → Search by Recitation sheet: offers the 84 MB model, listens until a 2 s pause (`EndOfRecitationDetector`), top 5 verses (Best Match, or "Is It One of These?" when the trust gate fails), each first verse once, opens the reader at it. Simulator: 112:1 through the Mac speakers auto-stopped → Best Match → reader at 112:1. Tests: `VoiceSearchViewModelTests` (5), `EndOfRecitationDetectorTests` (7), `RecitationEngineLoaderTests` (4), `VerseMatcherTests` (+1); no-sync 1,644, sync 2,123, Arabican 117 passed | `c5c8815b`, build 1011 |
| V2a | Live recitation follow in the reader | shipped (device checks: owner) | Reader mic button → capsule in the audio bar's place; `RecitationFollower` aligns 8 s windows every 1 s (`WordAligner.alignWithin`) near the place, highlights the recited word on the audio path (pages turn), loses the place after 3 missed windows of speech and finds it again in the whole Quran; stops on Stop, leaving, background, or 60 s without speech. Simulator: Husary 112:1–4 through the speakers followed word by word; 220–254 ms a window. Tests: `RecitationFollowerTests` (16), `RecitationFollowViewModelTests` (6), streaming model test (1); no-sync 1,667, sync 2,146, Arabican 117 passed | `b6f14d8d`, Quran and Arabican build 1013 |
| V3a | Recite and check (mistakes shown, nothing stored) | shipped (device checks: owner) | Ayah menu → Recite to Check sheet (one verse: to the end of its page within the sura); text hidden while reciting; result marks omitted (struck, red), substituted (underlined, red), uncertain (orange), not reached (faded) words and skipped verses. `RecitationChecker` (semi-global alignment, posterior confidence ≥ 0.6, similarity < 0.5 for a substitution, self-correction grace, extra words never mistakes, absorbed omissions split). Gate on 350 EveryAyah transcripts with planted mistakes: false alarms 0.77% of words, cuts 92%, swaps 92%. Windows cut at pauses. Simulated microphone for hands-on checks. no-sync 1,691, sync 2,171, Arabican 117 passed | `b5d48dfd`, Quran build 1015 |
| H1 (M3.3) | Learning store (`Quran 4`) and `MemorizationService`, with H2a | shipped 2026-11-27 (sessions and evidence; `MemorizedRange`/`Passage` entities moved to H3) | D1 and D2 decided | [h1-h2a](../trail/2026-11-27-h1-h2a-learning-store-and-practice.md) |
| H2 | Practice mode: page masking, hints, grading, listen-and-repeat, cumulative, translation & line-page | shipped (slices a–c; device checks: owner) | a: image-page masks, first letter, next word, check, self-grade. b: listen and repeat (3 runs, pause = ayah length, via the audio banner), mistaken words in the bar (word evidence), cue levels, cumulative A, B, A+B …, resume after kill (draft in user defaults). c: translation-view practice (masked Arabic, optional per-ayah Show Meaning hint, Check reveals Arabic even when hidden), line-page ayah-span masks + canonical word cues in the bar, forward/backward page turns, edition-aware draft resume. Tests: +6 in H2c (no-sync 1,742, sync 2,223, Arabican 117 passed); simulator: translation + Show Meaning + cumulative + resume, Madani 1439 line-page masks + cues + edition-aware resume, landscape, Dark + AX-XL | [h1-h2a](../trail/2026-11-27-h1-h2a-learning-store-and-practice.md), [h2b](../trail/2026-11-27-h2b-practice-listen-cues-cumulative-resume.md) `5a58c0d3` (1020), [h2c](../trail/2026-11-27-quran-h2c-reader-practice.md) `509fceca`, Quran & Arabican build 1022 |
| V2b | Automatic reveal and advance in Practice | verified (device checks: owner) | `PracticeRecitationTracker` (bounded lookahead, skip guard, 1-/2-word ayahs, manual `sync`, off-track after 3 speaking misses), `RecitationMicrophone.clearBuffer()` on cumulative jumps, `.model` provenance + draft v2 (v1 compatible), Practice bar + reader mic toggle, AX-XL stacking; +15 tests (no-sync 1,757, sync 2,238, Arabican 117 passed); simulator simulated-mic check uncovered 112:1–3 and advanced to 112:4 hands-free, Check stopped mic | [v2b](../trail/2026-11-27-v2b-live-practice-reveal.md) |
| H3 | Memorization map and passage review queue | verified (device checks: owner) | `QuranKit` `AyahRangeSet`, `Quran 5` (`MO_MemorizedRange`, `MO_Passage`, migration from `Quran 4` tested), backup schema 3 (schema 1 & 2 restore), `PassageSplitter`, Sabaq/Sabqi/Manzil review queue with reasons & `ReviewBudgetStore` daily budgets, skip/reschedule/split/reset with confirmation, Juz→Surah→Ayah map (declared vs demonstrated kept apart, colors + text labels), `HifzReviewFeature`, Home Memorization section, direct H2/V2b Practice launch; +19 tests (no-sync 1,776, sync 2,257, Arabican 117 passed); simulator end-to-end verified in Light/Dark, Portrait/Landscape, AX-XL | [h3](../trail/2026-11-27-h3-memorization-map-and-review-queue.md) |
| H4 | Spot tests with strict and granular scores | not started | | |
| H5 | Similar verses and confusion drills | not started | | |
| P1 | Private iCloud sync over the existing `NSPersistentCloudKitContainer` path | not started | owner D3 | |
| H6 | Goals, Khatmah, activity time, today's plan, reminders | not started | owner D5 for reminders | |
| H7 | Mistake history heatmap and repair queue | not started | | |
| V3b | Recite-and-check mistakes recorded as evidence (H7) | not started | needs H1, H7 | |
| V4 | Phoneme and vowel assessment (research, lab only) | not started | reviewer-gated | |
| V5 | Tajweed-rule feedback | not started | V4; reviewer-gated | |
| C3 | Translation compare, formatted share, search filters | not started | | |
| P2 | Widgets, App Intents, Spotlight | not started | | |

## Blocked

- **IndoPak Mushaf (R1):** no verified public pack on `files.quran.app` (every `naskh/`, `indopak/` guess
  404s; the Android naskh page provider is not public). Needs a source the owner trusts.
- **More synchronized reciters (M2):** QUL downloads need the owner's signed-in browser. Needed:
  QUL recitations with word segments whose audio the app can stream (QUL lists 59 "With
  segments"); which match the app's existing quranicaudio.com recordings is UNVERIFIED.

## Owner checklist (TestFlight, physical device)

Run on TestFlight build 959 or later, reciter "Mishary Al-Afasy (word by word)":

1. Play 1:1–1:7 at 1x: the highlight follows each word by ear; turn word-by-word meaning to
   English, then Bengali, in both the page and translation views.
2. Set verse repeat 3x with a 1x delay on 2:255: on each repeat the first word lights first, with
   no flash of the ayah's last word.
3. Range 37:125–37:132 repeated twice: 37:130's third word (`إِلۡ يَاسِينَ`) highlights as one
   word on the page; in the translation view it shows "Elijah" under both parts.
4. Play 6:79–6:81: 6:80's highlight starts with its recitation (it was 18 s late).
5. Speeds 0.75x and 1.5x on 2:282 (a long ayah): the page scrolls to follow the word; drag the
   page mid-ayah and it stops following until the next ayah.
6. Word pointer (page view): drag over 2:181 and 13:37 (ayahs `words.db` lacked): each word shows
   its meaning; pause marks show none; switch the pointer to transliteration.
7. Lock the phone during playback for 10 minutes with another reciter, then the word-by-word one:
   battery use looks normal in Settings > Battery.
8. VoiceOver on, translation view, word-by-word English: swipe through 1:2; each word reads its
   Arabic (in an Arabic voice) then its meaning; during playback the recited word says
   "selected".
9. Largest accessibility text size (Settings > Accessibility > Display & Text Size), word-by-word
   on, iPad in split view and an iPhone SE-size phone: every ayah stays on screen, long meanings
   wrap. Then switch the app to German, Russian and Chinese: the More menu shows a translated
   "Word-by-word meaning" title.
10. Translation view, word-by-word English, More menu: a "Transliteration" switch appears under
    "Word-by-word meaning" (not in page mode, not with meanings off); turn it on: each word shows
    an italic transliteration between the Arabic and the meaning (e.g. 2:2 `dhālika`).
11. Install build 961 over build 959 or earlier with notes, highlights and page bookmarks saved:
    after the update all of them are still there (the store migrated to model `Quran 3`).
12. F1 (build 983 or later): long-press an ayah, tap Save Ayah..., tick Favorites, close:
    the menu shows a filled star for that ayah; the Bookmarks tab shows Favorites with 1, then your page
    bookmarks under "Page Bookmarks". Create, rename and delete a collection; tap Edit with page bookmarks:
    Delete All asks about page bookmarks only. Check VoiceOver on the Bookmarks tab and the largest text size.
13. F1 follow-up (build 986 or later): save an ayah to Favorites and write a note on another; in
    Translation/Tafseer mode the first ayah's number capsule shows a star, the second a note icon; an ayah
    that is only highlighted shows neither. Check VoiceOver reads "Collections" / "Notes" after the number.
14. R1 (build 986 or later): Settings > Choose Mushaf shows Uthmani and Tajweed tabs (no IndoPak).
    Pick each of Hafs 1421, 1440, Madani 1439, Madani 1441 and Tajweed in turn: each downloads (52–144 MB)
    with a progress bar, then a page renders with ayah markers; turn on airplane mode and the chosen edition
    still opens; switch back to Hafs 1405. Try killing the app mid-download and reopening.
15. C1 (build 988 or later): with no tafsir downloaded, long-press an ayah on the Mushaf page, tap Tafsir: the
    sheet says no tafsir is downloaded; Download a Tafsir opens the translations list; download Arabic Muyassar
    Tafseer and close it: the sheet shows the ayah and its tafsir. Go to 2:45 (Muyassar explains 2:45–46
    together): the sheet says "Al-Baqarah 2:45–46" and that one explanation covers them; the next arrow goes to
    2:47. Download Ibn Kathir too: a picker appears; the choice is kept after closing. Try Dark mode, the
    largest text size and VoiceOver.
16. F2 (build 990 or later): Settings > Backup & Restore > Export Backup, Save to Files. Delete one note, then
    Restore from Backup, pick the file: the preview counts match; Merge brings the note back and nothing is
    duplicated (run Merge twice). Then try Replace on a second device or after adding a new bookmark: the new
    bookmark is gone, the backup's records are there. Try a non-backup .json file: an error, nothing changes.
17. C1 English/Bengali (build 992 or later): Settings > Translations lists "English Ibn Kathir Tafseer (Abridged)"
    under English and "Bengali Ahsanul Bayaan Tafseer" under Bengali; download both (7 and 4 MB). Long-press 2:8,
    Tafsir: pick each; Ibn Kathir shows "Al-Baqarah 2:8–9" and one explanation; Bengali shows 2:8 alone. Check the
    Bengali text at the largest text size, and with airplane mode on after downloading.
18. C2 word study (build 994 or later): open Al-Fatihah in Translation/Tafseer mode, More menu > Word-by-word
    meaning > English. Tap ٱلْحَمْدُ in 1:2: a Word Study sheet shows al-ḥamdu, its meaning, "Prefix · Definite article",
    "Noun · masculine · nominative", Root ح م د (68) and Dictionary form حَمْد (43). Long-press a word: the ayah menu
    still opens. Try 2:3's يُؤْمِنُونَ (Verb · form IV · imperfect …), Bengali meanings, Dark mode, the largest text
    size, VoiceOver (each word reads as a button with a hint), and an iPad in split view.
19. C2 occurrences (build 996 or later): in the Word Study sheet for 1:2's ٱلْحَمْدُ, tap Root ح م د: a list of 68
    words in Quran order, each with its meaning and "Sura, Ayah n, word n". Tap one in another sura: its study opens,
    the sheet drops to half height and the reader behind it moves to that ayah (it may sit just under the sheet; drag
    the sheet down). Tap Back: the reader returns to 1:2. Open Dictionary form, pick a word, then swipe the sheet away:
    the reader returns to 1:2. Scroll a long list fast (Root أ ل ه from اللَّهِ, 2,851): no stutter while pages load.
    Try VoiceOver (rows read meaning, place and Arabic; Root and Dictionary form say they list every word) and an
    iPad in split view.
20. C2 tap-to-hear and pointer entry (build 999 or later): in the Word Study sheet for 1:1's ٱلرَّحْمَٰنِ, tap "Hear the
    word": you hear that word alone (it may carry a little of the next sound), and the note says it streams. Try a long
    word (2:255 ٱلْقَيُّومُ), one word several times in a row, and airplane mode (a red "could not be played" note; tap
    again after reconnecting). Start a recitation from the banner, open a word study and tap Hear: the recitation pauses
    and resumes from the banner. Download Al-Fātiḥah for "Mishary Al-Afasy (word by word)" in Settings > Audio: the
    streaming note disappears and Hear works offline. Mushaf page (Hafs 1405), More menu > Word translation pointer on:
    drag the pointer over a word and let go: its meaning stays for about 4 seconds with a book symbol; tap it: Word
    Study opens for that word. Let go over a pause mark or blank space: nothing stays. Try VoiceOver on the Hear row.
21. V0 slice (a) (build 1001 or later): nothing to try on the device yet (no screen uses the engine). Decide D7 (roadmap
    §7): where the 125 MB recitation model is downloaded from, so slice (c) can run it on your phone.
22. Minimum iOS 27.2 (build 1003 or later): the build installs on a phone with iOS 27.2 or later (it no longer offers to
    install on older iOS). Open More menu > Word-by-word meaning and Word translation pointer: the pages sit on the
    popover's glass as before.
23. V0 Recitation Lab and model download (build 1008 or later): Settings > Diagnostics shows a "Developer tools" switch,
    off. Turn it on: a "Recitation Lab" row appears; turn it off and the row goes. Open the lab: it offers "Download the
    model (84 MB)"; tap it on Wi-Fi: a progress bar, then "Model ready" (the first load compiles the model and can take
    a while on a phone). Try sending the app to the background mid-download and coming back. Tap Record, allow the
    microphone, recite 1:1–1:4, tap Stop: the verses section shows 1:1–1:3 or similar with "confident", the words list shows
    each word matched with its time. Note the Recognition time, Real-time factor and Memory footprint for a 10 s and a 50 s
    recitation, and the battery after ten recordings. Play a recitation from the app's banner, then record: the
    recitation stops while recording and plays normally afterwards.
24. V1 voice search (build 1011 or later): Search tab, tap the microphone at the top right. The first time, the sheet
    offers "Download (84 MB)"; download it on Wi-Fi, then tap Recite. Recite 2–3 words of any verse and pause: after about 2
    seconds it stops on its own and shows "Best Match" with the verse, or "Is It One of These?" when unsure. Tap a verse: the
    sheet closes and the reader opens at it. Try: a quiet room and a noisy one (does it stop too early or never?), a short
    fragment (2:255's first words), a verse whose text repeats (55:13), saying nothing for 8 seconds ("Nothing Heard"),
    tapping Search Now mid-verse, closing the sheet while it listens (the microphone indicator goes off), denying the
    microphone in Settings (an alert offers Open Settings), Dark mode, the largest text size, VoiceOver, an iPad. Note the
    time from pause to result and anything it got wrong.
25. V2a live follow (build 1013 or later): open any Mushaf page, tap the microphone at the top right (left of the bookmark).
    The capsule where the audio banner sits says "Listening… Recite from this page." Recite from the page: within about a
    second of each word, that word is highlighted (with its meaning when word-by-word meaning is on) and the capsule shows the
    verse; keep going past the page's last verse: the page turns by itself. Then: pause for 10 s (does it say "Lost your
    place"? it shouldn't); repeat a verse (the highlight goes back); recite a sura from another part of the Quran (after a few
    seconds it says Lost, then jumps there); start with the basmala; recite in a noisy room; the translation view; tap the
    microphone again or × to stop (the highlight clears, the audio banner returns); play audio from the ayah menu while
    following (following stops); lock the phone (following stops). Note the delay from word to highlight, the battery used
    in 10 minutes of following, anything it followed wrongly, and Dark mode, the largest text size, VoiceOver and an iPad.
26. V3a recite and check (build 1015 or later): on a Mushaf page, long press a verse you know → Recite to Check (under
    Repeat). The sheet says how to start; tap Start Reciting, recite from memory, tap Stop and Check. Try: a faithful
    recitation (expect "No mistakes found."; note any red or orange word, those are false alarms); leave out one word; say
    a wrong word; skip a whole verse; say a wrong word and correct it straight away (should not count); stop half way (the
    rest is faded, not red); select several verses first; a noisy room; a recitation over a minute. Note every false alarm
    and missed mistake with the verse, the time from Stop to result, Dark mode, the largest text size, VoiceOver and an iPad.
27. H1 + H2a practice (build 1018 or later): on a Mushaf page, long press a verse you are memorizing → Practice. The
    verses from it to the end of the page are covered; the bar names the current ayah. Recite it from memory; try First
    Letter (lightbulb) and Next Word (eye), then Check: the ayah shows whole; grade it Forgot, Mistakes or Correct. Finish
    the page (the bar says "Practice saved." and the next review), or tap × half way (graded ayahs are kept). Then
    Settings > Backup & Restore: export, and check the preview of a restore counts the practice sessions. Note whether the
    covers ever show a word they should hide (or hide one they should show), a page with a pause mark inside an ayah,
    landscape, Dark mode, the largest text size, VoiceOver (hidden words must never be read) and an iPad.
28. H2b practice (build 1020 or later): start Practice on a page you are memorizing. Tap the speaker: the current ayah plays
    three times with a pause as long as the ayah after each (repeat it in the pause); the button turns into Stop, and back
    when it ends; then Check and Correct (it is recorded as with help). Grade an ayah Mistakes: its words appear in the bar;
    tap the ones you got wrong (red), Done. Options (sliders, left of ×) > Cues: try First Word of Each Ayah and Every Other
    Word (do the visible words help, or give too much away?). Options > Order > Cumulative on 3–4 new ayahs: 1, 2, 1–2, 3,
    1–3 … Half way through, kill the app from the app switcher, reopen, long press the same first ayah → Practice: it says
    "Picked up where you left off." at the ayah you reached. Note whether three repetitions and that pause length suit you,
    and the largest text size, VoiceOver on the word buttons, landscape and an iPad.
29. H2c practice in translation and line-page readers (build 1022 or later): switch the reader to Translation/Tafseer mode
    (with word-by-word meanings on and a translation selected), long press an ayah → Practice: unrevealed Arabic words are
    replaced with `…`, word meanings/transliteration/word-study taps are removed, and translations are hidden until you tap
    Show Meaning (counts once as help; resets on the next ayah). Try with "Show Arabic text" turned off in More menu: Check
    still reveals the Arabic for grading. Then switch to a line-page Mushaf (Settings > Choose Mushaf > Madani Mushaf 1439
    or 1441), open a page and start Practice: printed ayahs are covered in place, the bar reads "Ayah masks · word cues
    below", and Next Word / cue levels display canonical words in the bar; kill the app mid-session and resume on the same
    line-page edition. Check VoiceOver (hidden words must never be read), Dark mode, largest text size, landscape, and iPad
    split view.
30. V2b live reveal in Practice (next TestFlight build): start Practice on page 604 (112:1) and tap the microphone button
    in the Practice bar (or the top-right microphone button). If the model is not yet downloaded, check the inline Download
    (84 MB) prompt while manual buttons stay usable. Recite 112:1–112:4 aloud: each word uncovers in place as you recite
    and Practice advances ayah by ayah without touching the screen (also try in Translation/Tafseer mode and Madani 1439
    line-page mode). Test: pausing 10 s (stays Listening, not off-track); reciting the basmala before 112:1 (stays
    Listening); reciting the wrong verse (after ~3 s shows "Didn’t match this ayah…", then recovers when you recite the
    right ayah); tapping First Letter or Next Word mid-ayah (never re-hides, records with help); tapping Check mid-ayah
    (stops the microphone immediately for manual grading); tapping Listen and Repeat while reciting (stops the mic);
    Cumulative order across steps; locking the phone (stops the mic, keeps Practice open). Note latency, memory, and 10 min
    battery on a physical device, plus Dark mode, AX-XL, VoiceOver and iPad split view.
31. H3 memorization map and passage review queue (next TestFlight build): install over build 1022 (`Quran 4` → `Quran 5`
    migration keeps all notes, collections and past practice sessions). On Home under Continue Reading, check the
    Memorization section (due count + Start Next Review) and tap Review & Memorization Map. Tap + to declare a surah, a
    juz, and a page range: verify Sabaq/Sabqi/Manzil bucket cards, daily budgets (sliders button), due reasons ("Weak · N
    sessions", "Due N days ago", "Declared · Not tested yet"), Skip Today, Reschedule, Split Passage, and Reset Progress
    (confirmation alert). Switch to Map: check Declared vs Demonstrated counts, drill Juz → Surah → Ayah (every cell shows
    color + text label, no truncation), tap Practice to launch H2/V2b directly on that passage. Export a backup in Settings
    > Backup & Restore and verify the preview shows Memorized ranges (schema 3). Check Dark mode, AX-XL, Landscape,
    VoiceOver and iPad split view.
