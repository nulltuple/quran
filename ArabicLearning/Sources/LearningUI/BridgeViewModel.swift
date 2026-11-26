//
//  BridgeViewModel.swift
//  ArabicLearning (Arabican app)
//

import Foundation
import LearningContent
import LearningModel
import Observation
import QuranKit

/// The Quran tab (milestone L5): the bridge suras, each read in learning mode.
@MainActor
@Observable
public final class BridgeViewModel {
    // MARK: Lifecycle

    public init(content: LearningContentStore) {
        self.content = content
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
        BridgeReaderViewModel(sura: sura, content: content)
    }

    // MARK: Private

    private let content: LearningContentStore
}

/// Learning-mode reading of one sura: the recitation with the recited word highlighted, any word
/// played and explained on tap, and record and compare per ayah.
@MainActor
@Observable
final class BridgeReaderViewModel {
    // MARK: Lifecycle

    init(sura: BridgeSura, content: LearningContentStore) {
        self.sura = sura
        self.content = content
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
    let recorder = AyahRecorder()
    var selected: SelectedWord?
    /// The ayah the recorder belongs to; the controls of other ayahs offer a new recording.
    private(set) var recordingAyah: AyahNumber?

    var isPlaying: Bool { player.isPlaying }

    /// The word being recited, while the recitation plays.
    var recitedWord: Word? {
        player.isPlaying ? sura.word(at: player.currentTime) : nil
    }

    func loadSegments() async {
        segments = (try? await content.wordSegments(sura: sura.sura)) ?? [:]
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
    private let player: RecitationPlayer
    private var segments: [Word: [WordSegment]] = [:]
    private var pausedAt: TimeInterval?
}
