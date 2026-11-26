//
//  RecitationPlayer.swift
//  ArabicLearning (Arabican app)
//

import AVFoundation
import Observation

/// Plays a bundled sura recitation and publishes its clock while it plays, so the reader can
/// highlight the recited word. The clock is polled ten times a second, only during playback.
@MainActor
@Observable
final class RecitationPlayer {
    // MARK: Lifecycle

    init(url: URL) {
        self.url = url
    }

    // MARK: Internal

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0

    /// Plays from `start` to `end` (the recording's end when nil).
    func play(from start: TimeInterval, to end: TimeInterval? = nil) {
        ClipPlayer.usePlaybackSession()
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
        }
        guard let player else { return }
        player.currentTime = start
        player.play()
        isPlaying = true
        currentTime = start
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let player = self.player else { return }
                currentTime = player.currentTime
                if !player.isPlaying || (end.map { player.currentTime >= $0 } ?? false) {
                    pause()
                    return
                }
            }
        }
    }

    func pause() {
        clock?.cancel()
        clock = nil
        player?.pause()
        isPlaying = false
    }

    func stop() {
        pause()
        player = nil
        currentTime = 0
    }

    // MARK: Private

    private let url: URL
    private var player: AVAudioPlayer?
    private var clock: Task<Void, Never>?
}
