//
//  SimilarVersesViewModel.swift
//

import Foundation
import MemorizationService
import Observation
import QuranKit

@MainActor
@Observable
final class SimilarVersesViewModel {
    enum Drill {
        case continuation(SimilarVerseComparison.Continuation, choices: [SimilarVerseComparison.Verse])
        case ending(SimilarVerseComparison.Ending)
    }

    enum SaveState {
        case idle
        case saving
        case saved
        case failed
    }

    init(
        origin: AyahNumber,
        similarities: SimilarVerseService,
        memorization: MemorizationService,
        jump: @escaping (AyahNumber) -> Void,
        play: @escaping (AyahNumber) -> Void,
        stop: @escaping () -> Void
    ) {
        self.origin = origin
        self.similarities = similarities
        self.memorization = memorization
        jumpToAyah = jump
        playAyah = play
        stopAudio = stop
    }

    let origin: AyahNumber
    private(set) var matches: [AyahNumber]?
    var selection: AyahNumber?
    private(set) var comparison: SimilarVerseComparison?
    private(set) var loadFailed = false
    private(set) var drill: Drill?
    private(set) var isEndingRevealed = false
    private(set) var correct: Bool?
    private(set) var saveState: SaveState = .idle
    private(set) var controlsAudio = false

    func loadMatches() async {
        loadFailed = false
        do {
            let matches = try await similarities.matches(for: origin)
            guard !Task.isCancelled else { return }
            self.matches = matches
            selection = matches.first
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
        }
    }

    func compareSelection() async {
        guard let selection else { return }
        loadFailed = false
        comparison = nil
        do {
            let comparison = try await similarities.compare(origin, with: selection)
            guard !Task.isCancelled, self.selection == selection else { return }
            self.comparison = comparison
        } catch {
            guard !Task.isCancelled, self.selection == selection else { return }
            loadFailed = true
        }
    }

    func jump(to ayah: AyahNumber) {
        jumpToAyah(ayah)
        needsReturn = needsReturn || ayah != origin
    }

    func play(_ ayah: AyahNumber) {
        controlsAudio = true
        needsReturn = needsReturn || ayah != origin
        playAyah(ayah)
    }

    func stopPlayback() {
        guard controlsAudio else { return }
        controlsAudio = false
        stopAudio()
    }

    func close() {
        stopPlayback()
        if needsReturn {
            needsReturn = false
            jumpToAyah(origin)
        }
    }

    func startContinuation() {
        guard let continuation = comparison?.continuation else { return }
        let choices = [continuation.expected, continuation.alternative].shuffled()
        begin(.continuation(continuation, choices: choices))
    }

    func startEnding() {
        guard let ending = comparison?.ending else { return }
        begin(.ending(ending))
    }

    func endDrill() {
        guard saveState != .saving else { return }
        drill = nil
        correct = nil
        savedAnswer = nil
        isEndingRevealed = false
        saveState = .idle
    }

    func chooseContinuation(_ ayah: AyahNumber) async {
        guard case .continuation(let continuation, let choices) = drill,
              choices.contains(where: { $0.id == ayah })
        else { return }
        await submit(correct: ayah == continuation.expected.id, expected: continuation.expected.id)
    }

    func revealEnding() {
        if case .ending = drill {
            isEndingRevealed = true
        }
    }

    func gradeEnding(correct: Bool) async {
        guard case .ending = drill, isEndingRevealed else { return }
        await submit(correct: correct, expected: origin)
    }

    func retrySave() async {
        guard saveState == .failed else { return }
        await saveAnswer()
    }

    private let similarities: SimilarVerseService
    private let memorization: MemorizationService
    private let jumpToAyah: (AyahNumber) -> Void
    private let playAyah: (AyahNumber) -> Void
    private let stopAudio: () -> Void
    private var needsReturn = false
    private var drillStartedOn: Date?
    private var savedAnswer: VerseRecall?

    private func begin(_ drill: Drill) {
        guard self.drill == nil else { return }
        stopPlayback()
        drillStartedOn = Date()
        self.drill = drill
    }

    private func submit(correct: Bool, expected: AyahNumber) async {
        guard self.correct == nil else { return }
        self.correct = correct
        savedAnswer = VerseRecall(verse: expected, outcome: correct ? .correct : .mistake)
        await saveAnswer()
    }

    private func saveAnswer() async {
        guard let savedAnswer, let drillStartedOn else { return }
        saveState = .saving
        do {
            let verse = savedAnswer.verse
            try await memorization.recordSession(Passage(verse, verse), startedOn: drillStartedOn, recalls: [savedAnswer])
            saveState = .saved
        } catch {
            saveState = .failed
        }
    }
}
