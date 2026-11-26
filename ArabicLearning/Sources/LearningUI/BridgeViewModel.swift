//
//  BridgeViewModel.swift
//  ArabicLearning (Arabican app)
//

import Foundation
import LearningContent
import LearningEngine
import LearningModel
import LearningPersistence
import Observation
import QuranKit

/// The Quran tab (milestone L5): the bridge suras, each read in learning mode, with meanings in
/// the profile's language and the profile's known words for progressive substitution (L7).
@MainActor
@Observable
public final class BridgeViewModel {
    // MARK: Lifecycle

    public init(content: LearningContentStore, progress: ProgressStore, meaningLanguage: MeaningLanguage) {
        self.content = content
        self.progress = progress
        self.meaningLanguage = meaningLanguage
    }

    // MARK: Public

    public enum State: Equatable {
        case loading
        case loaded([BridgeSura])
        case failed
    }

    public private(set) var state: State = .loading

    public func load() async {
        guard case .loading = state else { return }
        do {
            state = .loaded(try await content.bridgeSuras())
        } catch {
            state = .failed
        }
    }

    func reader(for sura: BridgeSura) -> BridgeReaderViewModel {
        BridgeReaderViewModel(sura: sura, content: content, progress: progress, meaningLanguage: meaningLanguage)
    }

    // MARK: Private

    private let content: LearningContentStore
    private let progress: ProgressStore
    private let meaningLanguage: MeaningLanguage
}

/// Learning-mode reading of one sura: the recitation with the recited word highlighted, any word
/// played and explained on tap, and record and compare per ayah.
@MainActor
@Observable
final class BridgeReaderViewModel {
    // MARK: Lifecycle

    init(sura: BridgeSura, content: LearningContentStore, progress: ProgressStore, meaningLanguage: MeaningLanguage) {
        self.sura = sura
        self.content = content
        self.progress = progress
        self.meaningLanguage = meaningLanguage
        player = RecitationPlayer(url: sura.recording)
    }

    // MARK: Internal

    /// A tapped word with its morphology, for the word sheet.
    struct SelectedWord: Identifiable, Equatable {
        let word: BridgeWord
        let segments: [WordSegment]

        var id: Word { word.word.word }
    }

    let sura: BridgeSura
    let meaningLanguage: MeaningLanguage
    let recorder = AyahRecorder()
    /// Words whose every lemma the learner has mastered (`ProgressiveSubstitution`); the meaning
    /// line shows them in Arabic.
    private(set) var knownWords: Set<Word> = []
    var selected: SelectedWord?
    /// The ayah the recorder belongs to; the controls of other ayahs offer a new recording.
    private(set) var recordingAyah: AyahNumber?

    var isPlaying: Bool { player.isPlaying }

    /// The word being recited, while the recitation plays.
    var recitedWord: Word? {
        player.isPlaying ? sura.word(at: player.currentTime) : nil
    }

    /// Loads the sura's morphology and the learner's evidence; runs each time the reader appears,
    /// so words mastered in Practice show in Arabic on return.
    func load() async {
        if segments.isEmpty {
            segments = (try? await content.wordSegments(sura: sura.sura)) ?? [:]
        }
        let evidence = (try? await progress.evidence()) ?? [:]
        knownWords = ProgressiveSubstitution.knownWords(segments: segments, evidence: evidence)
    }

    func meaning(_ word: BridgeWord) -> String {
        meaningLanguage.text(word.meaning)
    }

    /// A piece of an ayah's meaning line: a word's meaning, or a run of known words in Arabic.
    enum MeaningPiece: Hashable {
        case meaning(String)
        /// Consecutive known words as one Arabic string, so they read right to left in their own
        /// order inside the left-to-right line.
        case arabic(String)
    }

    /// The ayah's meaning word by word, known words in Arabic (progressive substitution).
    func meaningLine(_ ayah: BridgeAyah) -> [MeaningPiece] {
        var pieces: [MeaningPiece] = []
        for word in ayah.words {
            if knownWords.contains(word.word.word) {
                if case .arabic(let run) = pieces.last {
                    pieces[pieces.count - 1] = .arabic(run + " " + word.word.text.text)
                } else {
                    pieces.append(.arabic(word.word.text.text))
                }
            } else {
                pieces.append(.meaning(meaning(word)))
            }
        }
        return pieces
    }

    /// Plays the whole recitation, or pauses it; Play after a pause resumes where it paused.
    func togglePlayback() {
        if player.isPlaying {
            pausedAt = player.currentTime < sura.end ? player.currentTime : nil
            player.pause()
        } else {
            player.play(from: pausedAt ?? 0)
            pausedAt = nil
        }
    }

    func select(_ word: BridgeWord) {
        playWord(word)
        selected = SelectedWord(word: word, segments: segments[word.word.word] ?? [])
    }

    func playWord(_ word: BridgeWord) {
        pausedAt = nil
        player.play(from: word.start, to: word.end)
    }

    func playAyah(_ ayah: BridgeAyah) {
        pausedAt = nil
        player.play(from: ayah.start, to: ayah.end)
    }

    func toggleRecording(_ ayah: BridgeAyah) async {
        player.pause()
        if recorder.state == .recording, recordingAyah == ayah.ayah {
            recorder.stopRecording()
        } else {
            recordingAyah = ayah.ayah
            await recorder.record()
        }
    }

    func playRecording() {
        player.pause()
        recorder.playRecording()
    }

    /// Stops audio and deletes the recording; the reader calls this when it closes.
    func close() {
        player.stop()
        recorder.discard()
        recordingAyah = nil
    }

    // MARK: Private

    private let content: LearningContentStore
    private let progress: ProgressStore
    private let player: RecitationPlayer
    private var segments: [Word: [WordSegment]] = [:]
    private var pausedAt: TimeInterval?
}
