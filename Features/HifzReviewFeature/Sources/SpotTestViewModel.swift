//
//  SpotTestViewModel.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import MemorizationService
import Observation
import QuranKit
import VLogging

/// Drives H4 Spot Tests: setup (memorized, custom, presets Warm up/Weakest/Due/Recent/Old;
/// ayahs or lines; count or timer; start cue; hidden location; temporary mode),
/// active random-start exam with hints/skip/reveal/word-level grading, and strict + granular score report.
@MainActor
@Observable
public final class SpotTestViewModel {
    // MARK: Lifecycle

    public init(
        service: MemorizationService,
        textLoader: SpotTestTextLoader,
        quran: Quran = .hafsMadani1405,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        makeSeed: @escaping @Sendable () -> UInt64 = { UInt64.random(in: 1 ... UInt64.max) },
        practicePassage: @escaping (Passage) -> Void,
        openAyah: @escaping (AyahNumber) -> Void
    ) {
        self.service = service
        self.textLoader = textLoader
        self.quran = quran
        self.calendar = calendar
        self.now = now
        self.makeSeed = makeSeed
        self.practicePassage = practicePassage
        self.openAyah = openAyah
    }

    deinit {
        timerTask?.cancel()
    }

    // MARK: Public

    public enum ScreenPhase: Equatable {
        case setup
        case loading
        case testing
        case results(SpotTestScoreReport)
    }

    public enum SourceKind: Hashable {
        case memorized
        case custom
        case preset(SpotTestPreset)
    }

    public enum LengthUnit: Int, CaseIterable, Hashable {
        case ayahs
        case lines
    }

    public enum LimitMode: Int, CaseIterable, Hashable {
        case count
        case timer
    }

    public enum QuestionPhase: Equatable {
        case reciting
        case grading
        case markingMistakes
    }

    public let quran: Quran
    public private(set) var screenPhase: ScreenPhase = .setup

    // Setup state
    public var sourceKind: SourceKind = .memorized
    public var customRanges = AyahRangeSet()
    public var lengthUnit: LengthUnit = .ayahs
    public var ayahCount = 3
    public var lineCount = 3
    public var limitMode: LimitMode = .count
    public var questionCount = 5
    public var timerMinutes = 5
    public var startCue: SpotTestStartCue = .firstTwoWords
    public var hideLocation = false
    public var isTemporary = false

    public var isCustomRangePickerPresented = false
    public private(set) var availableVerseCount = 0
    public private(set) var presetVerseCounts: [SpotTestPreset: Int] = [:]
    public private(set) var memorizedVerseCount = 0
    public private(set) var isRefreshingPools = false
    public private(set) var errorMessage: String?

    // Active test state
    public private(set) var activeConfiguration = SpotTestConfiguration()
    public private(set) var questions: [SpotTestQuestion] = []
    public private(set) var currentIndex = 0
    public private(set) var results: [SpotTestQuestionResult] = []
    public private(set) var questionPhase: QuestionPhase = .reciting
    public private(set) var loadedWords: [AyahNumber: [SpotTestWordUnit]] = [:]
    public private(set) var extraRevealedWords = 0
    public private(set) var hintLetter: String?
    public private(set) var currentQuestionHints = 0
    public private(set) var markedMistakeWords: [AyahNumber: Set<Int>] = [:]
    public private(set) var forgotVerses: Set<AyahNumber> = []
    public private(set) var remainingSeconds = 0
    public private(set) var savedToHistory = false
    public private(set) var saveFailed = false

    public var currentQuestion: SpotTestQuestion? {
        guard currentIndex >= 0, currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    public var isTimedTest: Bool {
        if case .timer = activeConfiguration.limit {
            return true
        }
        return false
    }

    public var canStart: Bool {
        availableVerseCount > 0 && !isRefreshingPools
    }

    public var effectiveSetupCue: SpotTestStartCue {
        if hideLocation, startCue == .referenceOnly {
            return .firstWord
        }
        return startCue
    }

    public var currentConfiguration: SpotTestConfiguration {
        let source: SpotTestSource = switch sourceKind {
        case .memorized: .memorized
        case .custom: .custom(customRanges)
        case .preset(let preset): .preset(preset)
        }
        let length: SpotTestQuestionLength = switch lengthUnit {
        case .ayahs: .ayahs(ayahCount)
        case .lines: .lines(lineCount)
        }
        let limit: SpotTestLimit = switch limitMode {
        case .count: .count(questionCount)
        case .timer: .timer(seconds: timerMinutes * 60)
        }
        return SpotTestConfiguration(
            source: source,
            questionLength: length,
            limit: limit,
            startCue: startCue,
            hideLocation: hideLocation,
            isTemporary: isTemporary,
            seed: makeSeed()
        )
    }

    /// Units currently visible as prompt + revealed hints for the active question while reciting.
    /// Hidden words are excluded completely so VoiceOver never reads them.
    public var visiblePromptLines: [(verse: AyahNumber, words: [SpotTestWordUnit], hasMoreHidden: Bool)] {
        guard let question = currentQuestion else { return [] }
        let totalVisible = initialCueUnitCount(for: question) + extraRevealedWords
        var budget = totalVisible
        var output: [(verse: AyahNumber, words: [SpotTestWordUnit], hasMoreHidden: Bool)] = []
        for verse in question.verses {
            let units = loadedWords[verse] ?? []
            if budget <= 0 {
                break
            }
            let shownCount = min(budget, units.count)
            let shown = Array(units.prefix(shownCount))
            budget -= shownCount
            let isLastShownVerse = budget == 0
            let remainingInThisOrLater = shownCount < units.count || (isLastShownVerse && verse != question.verses.last)
            output.append((verse: verse, words: shown, hasMoreHidden: remainingInThisOrLater))
        }
        return output
    }

    /// Whether the active question still has hidden words available for First Letter / Next Word.
    public var hasHiddenWord: Bool {
        guard let question = currentQuestion else { return false }
        let totalUnits = question.verses.reduce(0) { $0 + (loadedWords[$1]?.count ?? 0) }
        return initialCueUnitCount(for: question) + extraRevealedWords < totalUnits
    }

    // MARK: - Setup actions

    public func refreshPools() async {
        isRefreshingPools = true
        errorMessage = nil
        do {
            let memorized = try await service.spotTestPool(for: .memorized, calendar: calendar)
            memorizedVerseCount = memorized.verseCount
            var counts: [SpotTestPreset: Int] = [:]
            for preset in SpotTestPreset.allCases {
                let pool = try await service.spotTestPool(for: .preset(preset), calendar: calendar)
                counts[preset] = pool.verseCount
            }
            presetVerseCounts = counts
            updateAvailableCount()
        } catch {
            logger.error("SpotTest: failed to refresh pools: \(error)")
            errorMessage = error.localizedDescription
        }
        isRefreshingPools = false
    }

    public func selectSource(_ kind: SourceKind) {
        sourceKind = kind
        updateAvailableCount()
    }

    public func setCustomRanges(_ ranges: AyahRangeSet) {
        customRanges = ranges
        sourceKind = .custom
        updateAvailableCount()
    }

    public func pageRangePreview(from startPage: Int, to endPage: Int) -> ClosedRange<AyahNumber>? {
        let low = max(1, min(quran.numberOfPages, min(startPage, endPage)))
        let high = max(1, min(quran.numberOfPages, max(startPage, endPage)))
        guard let first = Page(quran: quran, pageNumber: low)?.firstVerse,
              let last = Page(quran: quran, pageNumber: high)?.lastVerse
        else {
            return nil
        }
        return first ... last
    }

    // MARK: - Exam lifecycle

    public func startTest(overrideConfiguration: SpotTestConfiguration? = nil) async {
        timerTask?.cancel()
        timerTask = nil
        errorMessage = nil
        screenPhase = .loading

        let config = overrideConfiguration ?? currentConfiguration
        activeConfiguration = config
        startedOn = now()
        results = []
        currentIndex = 0
        savedToHistory = false
        saveFailed = false
        timerBatchIndex = 0

        do {
            let pool = try await service.spotTestPool(for: config.source, calendar: calendar)
            guard !pool.isEmpty else {
                screenPhase = .setup
                updateAvailableCount()
                return
            }
            activePool = pool
            if case .lines = config.questionLength {
                activeLineSpans = await textLoader.loadLineSpans(for: pool)
            } else {
                activeLineSpans = [:]
            }

            let sampled = try await service.generateSpotTest(
                configuration: config,
                lineSpans: activeLineSpans,
                calendar: calendar
            )
            guard !sampled.isEmpty else {
                screenPhase = .setup
                return
            }
            questions = sampled
            let allVerses = sampled.flatMap(\.verses)
            loadedWords = try await textLoader.loadWordUnits(for: allVerses)

            resetQuestionInteractionState()
            screenPhase = .testing

            if case .timer(let seconds) = config.limit.clamped {
                remainingSeconds = seconds
                startTimer()
            } else {
                remainingSeconds = 0
            }
        } catch {
            logger.error("SpotTest: failed to start test: \(error)")
            errorMessage = error.localizedDescription
            screenPhase = .setup
        }
    }

    public func showFirstLetterHint() {
        guard screenPhase == .testing, questionPhase == .reciting, let nextUnit = nextHiddenWordUnit() else {
            return
        }
        hintLetter = Self.firstLetter(of: nextUnit.text) ?? "…"
        currentQuestionHints += 1
    }

    public func revealNextWord() {
        guard screenPhase == .testing, questionPhase == .reciting, hasHiddenWord else {
            return
        }
        extraRevealedWords += 1
        hintLetter = nil
        currentQuestionHints += 1
    }

    public func revealAndGrade() {
        guard screenPhase == .testing, questionPhase == .reciting else { return }
        hintLetter = nil
        questionPhase = .grading
    }

    public func skipQuestion() async {
        guard screenPhase == .testing, let question = currentQuestion else { return }
        let skippedResult = SpotTestQuestionResult(
            question: question,
            verseOutcomes: [],
            skipped: true,
            hintsUsed: currentQuestionHints
        )
        results.append(skippedResult)
        await advanceAfterQuestion()
    }

    public func gradeCorrect() async {
        guard screenPhase == .testing, questionPhase == .grading, let question = currentQuestion else { return }
        let usedHelp = currentQuestionHints > 0
        let outcomes = question.verses.enumerated().map { index, verse in
            SpotTestVerseOutcome(
                verse: verse,
                totalWords: wordCount(for: verse),
                outcome: usedHelp ? .hint : .correct,
                assistance: index == 0 ? currentQuestionHints : 0,
                mistakenWords: []
            )
        }
        results.append(SpotTestQuestionResult(question: question, verseOutcomes: outcomes, skipped: false, hintsUsed: currentQuestionHints))
        await advanceAfterQuestion()
    }

    public func gradeForgot() async {
        guard screenPhase == .testing, questionPhase == .grading, let question = currentQuestion else { return }
        let outcomes = question.verses.enumerated().map { index, verse in
            SpotTestVerseOutcome(
                verse: verse,
                totalWords: wordCount(for: verse),
                outcome: .revealed,
                assistance: index == 0 ? currentQuestionHints : 0,
                mistakenWords: []
            )
        }
        results.append(SpotTestQuestionResult(question: question, verseOutcomes: outcomes, skipped: false, hintsUsed: currentQuestionHints))
        await advanceAfterQuestion()
    }

    public func beginMarkingMistakes() {
        guard screenPhase == .testing, questionPhase == .grading else { return }
        markedMistakeWords = [:]
        forgotVerses = []
        questionPhase = .markingMistakes
    }

    public func cancelMarkingMistakes() {
        guard screenPhase == .testing, questionPhase == .markingMistakes else { return }
        markedMistakeWords = [:]
        forgotVerses = []
        questionPhase = .grading
    }

    public func toggleMistakenWord(verse: AyahNumber, wordNumbers: [Int]) {
        guard screenPhase == .testing, questionPhase == .markingMistakes else { return }
        forgotVerses.remove(verse)
        var current = markedMistakeWords[verse] ?? []
        let target = Set(wordNumbers)
        if current.isSuperset(of: target) {
            current.subtract(target)
        } else {
            current.formUnion(target)
        }
        markedMistakeWords[verse] = current
    }

    public func toggleForgotVerse(_ verse: AyahNumber) {
        guard screenPhase == .testing, questionPhase == .markingMistakes else { return }
        if forgotVerses.contains(verse) {
            forgotVerses.remove(verse)
        } else {
            forgotVerses.insert(verse)
            markedMistakeWords[verse] = []
        }
    }

    public func saveMistakesAndAdvance() async {
        guard screenPhase == .testing, questionPhase == .markingMistakes, let question = currentQuestion else { return }
        let hasAnySelection = !forgotVerses.isEmpty || markedMistakeWords.values.contains { !$0.isEmpty }
        let outcomes = question.verses.enumerated().map { index, verse -> SpotTestVerseOutcome in
            let assistance = index == 0 ? currentQuestionHints : 0
            if forgotVerses.contains(verse) {
                return SpotTestVerseOutcome(
                    verse: verse,
                    totalWords: wordCount(for: verse),
                    outcome: .revealed,
                    assistance: assistance,
                    mistakenWords: []
                )
            }
            let mistakes = markedMistakeWords[verse] ?? []
            if !mistakes.isEmpty || (!hasAnySelection && index == 0) {
                return SpotTestVerseOutcome(
                    verse: verse,
                    totalWords: wordCount(for: verse),
                    outcome: .mistake,
                    assistance: assistance,
                    mistakenWords: mistakes
                )
            }
            return SpotTestVerseOutcome(
                verse: verse,
                totalWords: wordCount(for: verse),
                outcome: assistance > 0 ? .hint : .correct,
                assistance: assistance,
                mistakenWords: []
            )
        }
        results.append(SpotTestQuestionResult(question: question, verseOutcomes: outcomes, skipped: false, hintsUsed: currentQuestionHints))
        await advanceAfterQuestion()
    }

    public func endTestEarly() async {
        guard screenPhase == .testing else { return }
        await finishTest()
    }

    public func replaySameQuestions() async {
        await startTest(overrideConfiguration: activeConfiguration)
    }

    public func resetToSetup() async {
        timerTask?.cancel()
        timerTask = nil
        screenPhase = .setup
        await refreshPools()
    }

    public func practice(_ passage: Passage) {
        practicePassage(passage)
    }

    public func openInReader(_ ayah: AyahNumber) {
        openAyah(ayah)
    }

    // MARK: Internal

    static func firstLetter(of text: String) -> String? {
        text.first.map(String.init)
    }

    func tickTimerOnce() async {
        guard screenPhase == .testing, isTimedTest else { return }
        if remainingSeconds > 1 {
            remainingSeconds -= 1
        } else {
            remainingSeconds = 0
            await finishTest()
        }
    }

    // MARK: Private

    private let service: MemorizationService
    private let textLoader: SpotTestTextLoader
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let makeSeed: @Sendable () -> UInt64
    private let practicePassage: (Passage) -> Void
    private let openAyah: (AyahNumber) -> Void

    private var startedOn = Date()
    private var activePool = AyahRangeSet()
    private var activeLineSpans: [AyahNumber: VerseLineSpan] = [:]
    private var timerBatchIndex = 0
    @ObservationIgnored private nonisolated(unsafe) var timerTask: Task<Void, Never>?

    private func updateAvailableCount() {
        switch sourceKind {
        case .memorized:
            availableVerseCount = memorizedVerseCount
        case .custom:
            availableVerseCount = customRanges.verseCount
        case .preset(let preset):
            availableVerseCount = presetVerseCounts[preset] ?? 0
        }
    }

    private func resetQuestionInteractionState() {
        questionPhase = .reciting
        extraRevealedWords = 0
        hintLetter = nil
        currentQuestionHints = 0
        markedMistakeWords = [:]
        forgotVerses = []
    }

    private func wordCount(for verse: AyahNumber) -> Int {
        let units = loadedWords[verse] ?? []
        let canonicalMax = units.flatMap(\.wordNumbers).max() ?? 0
        return max(canonicalMax, units.count)
    }

    private func initialCueUnitCount(for question: SpotTestQuestion) -> Int {
        let firstUnits = question.verses.first.flatMap { loadedWords[$0] } ?? []
        switch activeConfiguration.effectiveStartCue {
        case .referenceOnly:
            return 0
        case .firstWord:
            return min(1, firstUnits.count)
        case .firstTwoWords:
            return min(2, firstUnits.count)
        case .firstAyah:
            if question.verses.count > 1 {
                return firstUnits.count
            }
            // Single-ayah question: reveal at most half (minimum 1) so recall is still tested.
            return max(1, min(firstUnits.count - 1, firstUnits.count / 2))
        }
    }

    private func nextHiddenWordUnit() -> SpotTestWordUnit? {
        guard let question = currentQuestion else { return nil }
        var skip = initialCueUnitCount(for: question) + extraRevealedWords
        for verse in question.verses {
            let units = loadedWords[verse] ?? []
            if skip < units.count {
                return units[skip]
            }
            skip -= units.count
        }
        return nil
    }

    private func advanceAfterQuestion() async {
        if currentIndex + 1 < questions.count {
            currentIndex += 1
            resetQuestionInteractionState()
            return
        }

        if isTimedTest, remainingSeconds > 0, !activePool.isEmpty {
            timerBatchIndex += 1
            let nextSeed = activeConfiguration.seed &+ UInt64(timerBatchIndex) &* 0x9E37_79B9
            let batch = SpotTestSampler.sampleQuestions(
                from: activePool,
                length: activeConfiguration.questionLength,
                count: min(max(10, activePool.verseCount), 30),
                seed: nextSeed,
                lineSpans: activeLineSpans
            )
            if !batch.isEmpty {
                let offset = questions.count
                let reindexed = batch.enumerated().map { idx, q in
                    SpotTestQuestion(id: offset + idx, passage: q.passage, targetLineCount: q.targetLineCount)
                }
                let missingVerses = reindexed.flatMap(\.verses).filter { loadedWords[$0] == nil }
                if !missingVerses.isEmpty, let moreWords = try? await textLoader.loadWordUnits(for: missingVerses) {
                    loadedWords.merge(moreWords) { existing, _ in existing }
                }
                questions.append(contentsOf: reindexed)
                currentIndex += 1
                resetQuestionInteractionState()
                return
            }
        }

        await finishTest()
    }

    private func finishTest() async {
        timerTask?.cancel()
        timerTask = nil

        let planned: Int? = switch activeConfiguration.limit.clamped {
        case .count:
            questions.count
        case .timer:
            nil
        }
        let report = SpotTestScorer.score(results: results, plannedQuestions: planned)

        if !activeConfiguration.isTemporary, !results.isEmpty {
            do {
                let savedIDs = try await service.recordSpotTest(results, startedOn: startedOn, isTemporary: false)
                savedToHistory = !savedIDs.isEmpty
                saveFailed = false
            } catch {
                logger.error("SpotTest: failed to save results: \(error)")
                savedToHistory = false
                saveFailed = true
            }
        } else {
            savedToHistory = false
            saveFailed = false
        }

        screenPhase = .results(report)
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await tickTimerOnce()
                if screenPhase != .testing {
                    return
                }
            }
        }
    }
}
