//
//  HifzPracticeViewModelTests.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import BatchDownloader
import CoreDataPersistence
import CoreDataPersistenceTestSupport
import Foundation
import MemorizationPersistence
import MemorizationService
import QuranAnnotations
import QuranKit
import QuranResources
import RecitationRecognition
import TestResources
import XCTest
@testable import HifzPracticeFeature

@MainActor
final class HifzPracticeViewModelTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = TemporaryCoreDataStore()
        persistence = CoreDataMemorizationPersistence(stack: store.stack())
        suiteName = "HifzPracticeViewModelTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        stateStore = PracticeStateStore(userDefaults: userDefaults)
        modelDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("hifz-practice-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        masks = []
        listened = []
        stoppedListening = 0
        closed = false
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: modelDirectory)
        stateStore = nil
        userDefaults = nil
        persistence = nil
        store = nil
        try super.tearDownWithError()
    }

    func testPracticeHidesTheAyahsRevealsOnRequestAndSavesTheGrades() async throws {
        let sut = makeSUT()
        await sut.start()
        XCTAssertEqual(sut.phase, .reciting)
        XCTAssertEqual(masks.last, PracticeMask(hiddenVerses: [verse(2), verse(3), verse(4)], partialVerse: verse(1), revealedWords: 0))

        sut.showHint()
        XCTAssertEqual(sut.hint, "قُ", "the first letter of قُلۡ, with its vowel")
        sut.revealNextWord()
        XCTAssertNil(sut.hint)
        XCTAssertEqual(masks.last??.revealedWords, 1)

        sut.check()
        XCTAssertEqual(sut.phase, .grading)
        XCTAssertEqual(masks.last??.revealedWords, 4, "112:1 has four words")
        XCTAssertNil(masks.last??.partialVerse, "the checked ayah shows whole, with its end marker")
        XCTAssertFalse(sut.hasHiddenWord)

        await sut.grade(.correct)
        XCTAssertEqual(sut.currentVerse, verse(2))
        XCTAssertEqual(masks.last, PracticeMask(hiddenVerses: [verse(3), verse(4)], partialVerse: verse(2), revealedWords: 0))
        for outcome in [RecallOutcome.correct, .mistake, .revealed] {
            sut.check()
            await sut.grade(outcome)
        }

        guard case .finished(let progress) = sut.phase else {
            return XCTFail("Expected finished, got \(sut.phase)")
        }
        XCTAssertEqual(progress.lastGrade, .again)
        XCTAssertEqual(progress.gradedSessions, 1)
        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(
            history.evidence.sorted { $0.verse < $1.verse }.map(\.outcome),
            [.hint, .correct, .mistake, .revealed],
            "Correct after a hint and a peeked word is recorded as a hint"
        )
        XCTAssertEqual(history.evidence.first { $0.verse.ayah == 1 }?.assistance, 2)

        await sut.end()
        XCTAssertEqual(masks.last, .some(nil), "the page shows every word again")
        XCTAssertTrue(closed)
        let sessions = try await persistence.history().sessions
        XCTAssertEqual(sessions.count, 1, "ending after finishing saves nothing more")
    }

    func testMeaningCueAppliesOnceToTheRequestedAyahAndCountsAsHelp() async throws {
        let sut = makeSUT()
        await sut.start()
        sut.revealMeaning(for: verse(2))
        XCTAssertEqual(masks.last??.showsMeaning, false)
        sut.revealMeaning(for: verse(1))
        sut.revealMeaning(for: verse(1))
        XCTAssertEqual(masks.last??.showsMeaning, true)
        sut.check()
        XCTAssertEqual(masks.last??.checkedVerse, verse(1))
        await sut.grade(.correct)
        XCTAssertEqual(masks.last??.showsMeaning, false)
        await sut.end()
        let evidence = try await persistence.history().evidence
        XCTAssertEqual(evidence.first?.assistance, 1)
        XCTAssertEqual(evidence.first?.outcome, .hint)
    }

    func testLineScanShowsOnlyCanonicalRevealsAndCuesInTheBar() async {
        let sut = makeSUT()
        sut.usesLinePage = true
        await sut.start()
        XCTAssertNil(sut.linePageCues)
        sut.setCueLevel(.alternateWords)
        XCTAssertEqual(sut.linePageCues, "قُلۡ … ٱللَّهُ …")
        sut.revealNextWord()
        sut.revealNextWord()
        XCTAssertEqual(sut.linePageCues, "قُلۡ هُوَ ٱللَّهُ …")
        sut.check()
        XCTAssertNil(sut.linePageCues)
    }

    func testEndingEarlySavesOnlyTheGradedAyahs() async throws {
        let sut = makeSUT()
        await sut.start()
        sut.check()
        await sut.grade(.correct)

        await sut.end()

        let history = try await persistence.history()
        XCTAssertEqual(history.evidence.map(\.outcome), [.correct])
        XCTAssertEqual(history.sessions.first?.last, MemorizationVerse(sura: 112, ayah: 4))
        XCTAssertTrue(closed)
    }

    func testEndingBeforeGradingSavesNothing() async throws {
        let sut = makeSUT()
        await sut.start()

        await sut.end()

        let sessions = try await persistence.history().sessions
        XCTAssertEqual(sessions, [])
    }

    func testOneSelectedAyahPracticesToTheEndOfItsPage() {
        let quran = Quran.hafsMadani1405
        let start = AyahNumber(quran: quran, sura: 2, ayah: 6)!
        XCTAssertEqual(HifzPracticeBuilder.passage(for: [start]), Passage(start, start.page.lastVerse))
        XCTAssertEqual(HifzPracticeBuilder.passage(for: [verse(3), verse(1)]), Passage(verse(1), verse(3)))
        XCTAssertNil(HifzPracticeBuilder.passage(for: []))
    }

    func testCueLevelKeepsWordsOfHiddenAyahsVisibleAndIsRemembered() async throws {
        let sut = makeSUT()
        await sut.start()

        sut.setCueLevel(.firstWord)

        let mask = try XCTUnwrap(masks.last ?? nil)
        XCTAssertEqual(mask.cueWords, Set((1 ... 4).map { Word(verse: verse($0), wordNumber: 1) }))
        XCTAssertEqual(stateStore.cueLevel, .firstWord)

        sut.check()
        XCTAssertEqual(
            masks.last??.cueWords,
            Set((2 ... 4).map { Word(verse: verse($0), wordNumber: 1) }),
            "the checked ayah shows whole, so it needs no cue"
        )

        sut.setCueLevel(.alternateWords)
        // 112:2 is ٱللَّهُ ٱلصَّمَدُ: two words, so only its first is a cue.
        XCTAssertTrue(masks.last??.cueWords.contains(Word(verse: verse(2), wordNumber: 1)) == true)
        XCTAssertFalse(masks.last??.cueWords.contains(Word(verse: verse(2), wordNumber: 2)) == true)
    }

    func testCumulativeOrderGoesBackOverTheAyahsSoFar() async throws {
        stateStore.order = .cumulative
        let sut = makeSUT()
        await sut.start()

        var recited: [Int] = []
        while let current = sut.currentVerse {
            recited.append(current.ayah)
            if recited.count == 3 {
                XCTAssertEqual(sut.currentStep?.step, 2, "the A+B step")
                XCTAssertEqual(masks.last??.hiddenVerses, [verse(2), verse(3), verse(4)], "going back hides the later ayahs again")
            }
            sut.check()
            await sut.grade(.correct)
        }

        XCTAssertEqual(recited, [1, 2, 1, 2, 3, 1, 2, 3, 4, 1, 2, 3, 4])
        XCTAssertEqual(sut.steps.count, 7)
        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.evidence.count, 13)
    }

    func testOrderChangesOnlyBeforeTheFirstGrade() async {
        let sut = makeSUT()
        await sut.start()
        sut.revealNextWord()

        sut.setOrder(.cumulative)
        XCTAssertEqual(sut.order, .cumulative)
        XCTAssertEqual(sut.revealedWords, 0, "a new order starts over")
        XCTAssertEqual(stateStore.order, .cumulative)

        sut.check()
        await sut.grade(.correct)
        XCTAssertFalse(sut.canChangeOrder)
        sut.setOrder(.straight)
        XCTAssertEqual(sut.order, .cumulative)
    }

    func testMistakenWordsAreRecordedWithTheAyah() async throws {
        let sut = makeSUT()
        await sut.start()
        sut.check()

        sut.markMistakes()
        XCTAssertEqual(sut.phase, .markingMistakes)
        XCTAssertEqual(sut.wordChoices.map(\.words), [[1], [2], [3], [4]], "قُلۡ هُوَ ٱللَّهُ أَحَدٌ")
        XCTAssertEqual(sut.wordChoices.first?.text, "قُلۡ")
        sut.toggleMistake(sut.wordChoices[2])
        sut.toggleMistake(sut.wordChoices[3])
        sut.toggleMistake(sut.wordChoices[3])
        XCTAssertEqual(sut.markedWords, [3])
        await sut.saveMistakes()
        XCTAssertEqual(sut.currentVerse, verse(2))
        XCTAssertEqual(sut.markedWords, [])

        await sut.end()
        let evidence = try await persistence.history().evidence
        XCTAssertEqual(evidence.map(\.word).sorted(), [0, 3])
        XCTAssertEqual(Set(evidence.map(\.outcome)), [.mistake])
    }

    func testListenAndRepeatPlaysTheAyahAndCountsAsHelp() async throws {
        let sut = makeSUT()
        await sut.start()

        sut.toggleListening()
        XCTAssertEqual(listened, [verse(1)])
        XCTAssertTrue(sut.isListening)
        sut.audioStopped()
        XCTAssertFalse(sut.isListening, "playback finished")

        sut.toggleListening()
        sut.check()
        XCTAssertFalse(sut.isListening)
        XCTAssertEqual(stoppedListening, 1, "checking stops the recitation")
        await sut.grade(.correct)

        await sut.end()
        let evidence = try await persistence.history().evidence
        XCTAssertEqual(evidence.map(\.outcome), [.hint])
        XCTAssertEqual(evidence.first?.assistance, 2)
    }

    func testPracticeResumesAfterTheAppIsKilled() async throws {
        let first = makeSUT()
        await first.start()
        first.check()
        await first.grade(.correct)
        first.check()
        await first.grade(.mistake)
        // The app is killed: `first` never ends.

        let second = makeSUT()
        await second.start()
        XCTAssertEqual(second.currentVerse, verse(3))
        XCTAssertTrue(second.resumed)
        XCTAssertEqual(masks.last, PracticeMask(hiddenVerses: [verse(4)], partialVerse: verse(3), revealedWords: 0))
        second.check()
        await second.grade(.correct)
        XCTAssertFalse(second.resumed)
        await second.end()

        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.evidence.sorted { $0.verse < $1.verse }.map(\.outcome), [.correct, .mistake, .correct])
        XCTAssertNil(stateStore.draft, "a saved session leaves no draft")
    }

    func testAnotherPassagesDraftIsSavedAsItsOwnSession() async throws {
        let other = Passage(AyahNumber(quran: .hafsMadani1405, sura: 113, ayah: 1)!, AyahNumber(quran: .hafsMadani1405, sura: 113, ayah: 5)!)
        try stateStore.saveDraft(PracticeDraft(
            passage: other,
            order: .straight,
            position: 1,
            startedOn: Date(timeIntervalSince1970: 1_800_000_000),
            recalls: [VerseRecall(verse: other.first, outcome: .correct)]
        ))

        let sut = makeSUT()
        await sut.start()

        XCTAssertEqual(sut.currentVerse, verse(1))
        XCTAssertFalse(sut.resumed)
        XCTAssertNil(stateStore.draft)
        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.map(\.first), [MemorizationVerse(sura: 113, ayah: 1)])
    }

    func testLiveRecitationWithoutModelOffersDownloadAndKeepsManualPracticeWorking() async {
        let sut = makeSUT()
        await sut.start()

        await sut.toggleLiveRecitation()

        XCTAssertEqual(sut.liveRecitationState, .needsModel(byteCount: RecitationModelArchive.current.byteCount))
        XCTAssertEqual(sut.phase, .reciting)

        // Manual practice still works seamlessly even when the model is missing.
        sut.revealNextWord()
        XCTAssertEqual(sut.revealedWords, 1)
        sut.check()
        XCTAssertEqual(sut.phase, .grading)
    }

    func testLiveRecitationRevealsAndAdvancesThroughAlIkhlasAndSavesModelEvidence() async throws {
        try installModel()
        let sut = makeSUT()
        await sut.start()
        let prepared = await sut.prepareRecognizer()
        XCTAssertTrue(prepared)
        sut.beginLiveRecitation()
        XCTAssertTrue(sut.isLiveReciting)

        try await stream(["Husary_112001", "Husary_112002", "Husary_112003", "Husary_112004"], to: sut)

        // Partial reveals occurred before completion.
        XCTAssertTrue(masks.contains { $0?.partialVerse == verse(1) && ($0?.revealedWords ?? 0) > 0 })
        XCTAssertFalse(sut.isLiveReciting, "finishing the passage stops live recitation")
        guard case .finished(let progress) = sut.phase else {
            return XCTFail("Expected finished, got \(sut.phase)")
        }
        XCTAssertEqual(progress.lastGrade, .good)
        XCTAssertEqual(progress.gradedSessions, 1)
        XCTAssertNil(stateStore.draft)

        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 1)
        let sorted = history.evidence.sorted { $0.verse < $1.verse }
        XCTAssertEqual(sorted.map(\.verse.ayah), [1, 2, 3, 4])
        XCTAssertEqual(sorted.map(\.outcome), [.correct, .correct, .correct, .correct])
        XCTAssertTrue(sorted.allSatisfy { $0.provenance == .model })
    }

    func testManualHintsAndCheckOverrideLiveRecitation() async throws {
        try installModel()
        let sut = makeSUT()
        await sut.start()
        let prepared = await sut.prepareRecognizer()
        XCTAssertTrue(prepared)
        sut.beginLiveRecitation()

        // Manual hint + peek on 112:1, then live recitation finishes 112:1 -> recorded as `.hint` with `.model`.
        sut.showHint()
        sut.revealNextWord()
        XCTAssertEqual(sut.revealedWords, 1)
        try await stream(["Husary_112001"], to: sut)
        XCTAssertEqual(sut.currentVerse, verse(2))
        XCTAssertTrue(sut.isLiveReciting)

        // Manual Check on 112:2 stops live recitation and grades manually.
        sut.check()
        XCTAssertFalse(sut.isLiveReciting)
        XCTAssertEqual(sut.phase, .grading)
        await sut.grade(.mistake)

        // Listen & Repeat stops live recitation when restarted.
        sut.beginLiveRecitation()
        XCTAssertTrue(sut.isLiveReciting)
        sut.toggleListening()
        XCTAssertFalse(sut.isLiveReciting)
        XCTAssertTrue(sut.isListening)

        await sut.end()
        let evidence = try await persistence.history().evidence.sorted { $0.verse < $1.verse }
        XCTAssertEqual(evidence.map(\.outcome), [.hint, .mistake])
        XCTAssertEqual(evidence.map(\.assistance), [2, 0])
        XCTAssertEqual(evidence.map(\.provenance), [.model, .manual])
    }

    func testLiveRecitationWorksInCumulativeOrderAcrossStepBoundaries() async throws {
        try installModel()
        stateStore.order = .cumulative
        let sut = makeSUT(passage: Passage(verse(1), verse(2)))
        await sut.start()
        let prepared = await sut.prepareRecognizer()
        XCTAssertTrue(prepared)
        sut.beginLiveRecitation()

        // Step 0: [112:1]
        try await stream(["Husary_112001"], to: sut)
        XCTAssertEqual(sut.currentStep?.step, 1)
        XCTAssertEqual(sut.currentVerse, verse(2))

        // Step 1: [112:2]
        try await stream(["Husary_112002"], to: sut)
        XCTAssertEqual(sut.currentStep?.step, 2)
        XCTAssertEqual(sut.currentVerse, verse(1))

        // Step 2: [112:1, 112:2]
        try await stream(["Husary_112001", "Husary_112002"], to: sut)
        guard case .finished = sut.phase else {
            return XCTFail("Expected finished after cumulative step 2, got \(sut.phase)")
        }
        let history = try await persistence.history()
        XCTAssertEqual(history.evidence.count, 4, "112:1, 112:2, then 112:1 + 112:2")
    }

    func testLiveRecitationUpdatesLinePageCuesAsWordsAreRecited() async throws {
        try installModel()
        let sut = makeSUT()
        sut.usesLinePage = true
        await sut.start()
        let prepared = await sut.prepareRecognizer()
        XCTAssertTrue(prepared)
        sut.beginLiveRecitation()

        XCTAssertNil(sut.linePageCues)
        var sawPartialCue = false
        let clip = try samples("Husary_112001")
        let hop = RecitationAudio.sampleRate
        var end = hop
        while end <= clip.count + hop {
            let upper = min(end, clip.count)
            await sut.followLiveRecitation(Array(clip[0 ..< upper]))
            if sut.currentVerse == verse(1), let cues = sut.linePageCues, cues.contains("قُلۡ") {
                sawPartialCue = true
            }
            end += hop
        }
        XCTAssertTrue(sawPartialCue, "live recitation should uncover canonical words in the line-page cue bar")
        XCTAssertEqual(sut.currentVerse, verse(2))
    }

    func testLivePracticeHighlightsAndDisputesMistakesOnMask() async throws {
        try installModel()
        let sut = makeSUT()
        await sut.start()
        let prepared = await sut.prepareRecognizer()
        XCTAssertTrue(prepared)
        sut.beginLiveRecitation()

        // Recite 112:1, then stumble with 1:2 (wrong words from Al-Fatihah), then recover with 112:2..4.
        try await stream(["Husary_112001", "Alafasy_001002", "Husary_112002", "Husary_112003", "Husary_112004"], to: sut)

        XCTAssertFalse(sut.liveMistakes.isEmpty, "stumbling into 1:2 before 112:2 should flag a live mistake")
        XCTAssertNotNil(sut.liveAccuracyPercent)
        XCTAssertTrue(masks.contains { ($0?.mistakeWords.isEmpty) == false }, "live mistakes should appear on PracticeMask")

        // Toggling highlight mistakes off clears PracticeMask.mistakeWords while keeping liveMistakes.
        sut.highlightLiveMistakes = false
        XCTAssertEqual(masks.last??.mistakeWords, [])
        sut.highlightLiveMistakes = true
        XCTAssertEqual(masks.last??.mistakeWords, Set(sut.liveMistakes.map(\.word)))

        // Disputing clears the mistake from liveMistakes and the mask.
        let firstMistake = try XCTUnwrap(sut.liveMistakes.first)
        sut.disputeLiveMistake(firstMistake)
        XCTAssertFalse(sut.liveMistakes.contains(firstMistake))
        XCTAssertFalse(masks.last??.mistakeWords.contains(firstMistake.word) ?? false)
    }

    func testLiveRecitationHandlesLowVolumeSpeakerAudioAndTracksMovingActiveWord() async throws {
        try installModel()
        let sut = makeSUT()
        await sut.start()
        let prepared = await sut.prepareRecognizer()
        XCTAssertTrue(prepared)
        sut.beginLiveRecitation()
        XCTAssertNotNil(sut.liveRecitationStartedAt)

        // Attenuate studio audio by -30 dB (0.03x) to simulate holding an iPhone mic over a laptop speaker.
        try await stream(["Husary_112001", "Husary_112002", "Husary_112003", "Husary_112004"], to: sut, gain: 0.03)

        let activeWordsSeen = masks.compactMap { $0?.activeWord }
        XCTAssertFalse(activeWordsSeen.isEmpty, "moving activeWord cursor should update as words are recited")
        guard case .finished = sut.phase else {
            return XCTFail("Expected finished on -30 dB attenuated audio, got \(sut.phase)")
        }
    }

    // MARK: Private

    private static let cachedModel = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/recitation-model")

    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var stateStore: PracticeStateStore!
    private var modelDirectory: URL!
    private var masks: [PracticeMask?] = []
    private var listened: [AyahNumber] = []
    private var stoppedListening = 0
    private var closed = false
    private let downloadManager = DownloadManager(
        maxSimultaneousDownloads: 1,
        configuration: .ephemeral,
        downloadsURL: FileManager.default.temporaryDirectory.appendingPathComponent("hifz-practice-tests-\(UUID().uuidString).db")
    )

    private func verse(_ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: 112, ayah: ayah)!
    }

    private func makeSUT(passage: Passage? = nil, wordByWordDatabase: URL? = nil) -> HifzPracticeViewModel {
        let modelStore = RecitationModelStore(directory: modelDirectory)
        let loader = RecitationEngineLoader(
            store: modelStore,
            downloader: RecitationModelDownloader(downloadManager: downloadManager, store: modelStore),
            verseText: RecitationVerseText(
                quranUthmaniV2Database: QuranResources.quranUthmaniV2Database,
                wordByWordDatabase: wordByWordDatabase ?? TestResources.resourceURL("word_by_word.db")
            )
        )
        return HifzPracticeViewModel(
            passage: passage ?? Passage(verse(1), verse(4)),
            loader: loader,
            microphone: RecitationMicrophone(keepingLatestSeconds: HifzPracticeViewModel.liveWindowSeconds + 2),
            service: MemorizationService(persistence: persistence),
            store: stateStore,
            mask: { [weak self] in self?.masks.append($0) },
            listen: { [weak self] in self?.listened.append($0) },
            stopListening: { [weak self] in self?.stoppedListening += 1 },
            close: { [weak self] in self?.closed = true }
        )
    }

    private func samples(_ fixture: String) throws -> [Float] {
        try RecitationAudio.samples(contentsOf: TestResources.resourceURL("recitation/\(fixture).mp3"))
    }

    private func stream(_ fixtures: [String], to viewModel: HifzPracticeViewModel, gain: Float = 1.0) async throws {
        executionTimeAllowance = 300
        var audio: [Float] = []
        for fixture in fixtures {
            let clip = try samples(fixture)
            audio += (gain == 1.0 ? clip : clip.map { $0 * gain })
            audio += [Float](repeating: 0, count: RecitationAudio.sampleRate / 2)
        }
        let hop = RecitationAudio.sampleRate
        let window = Int(HifzPracticeViewModel.liveWindowSeconds) * RecitationAudio.sampleRate
        var end = hop
        while end < audio.count + hop {
            let upper = min(end, audio.count)
            await viewModel.followLiveRecitation(Array(audio[max(0, upper - window) ..< upper]))
            end += hop
        }
    }

    private func installModel() throws {
        let package = Self.cachedModel.appendingPathComponent(RecitationModelStore.packageName)
        let vocabulary = Self.cachedModel.appendingPathComponent("source/vocab.json")
        guard FileManager.default.fileExists(atPath: package.path), FileManager.default.fileExists(atPath: vocabulary.path) else {
            throw XCTSkip("No recitation model at \(package.path): run `make recitation-model` to build it.")
        }
        try FileManager.default.createSymbolicLink(
            at: modelDirectory.appendingPathComponent(RecitationModelStore.packageName),
            withDestinationURL: package
        )
        try FileManager.default.createSymbolicLink(
            at: modelDirectory.appendingPathComponent(RecitationModelStore.vocabularyName),
            withDestinationURL: vocabulary
        )
    }
}
