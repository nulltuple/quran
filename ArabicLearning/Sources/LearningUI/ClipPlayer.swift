//
//  ClipPlayer.swift
//  ArabicLearning (Arabican app)
//

import AVFoundation
import LearningModel

/// Plays one recording at a time: a letter clip, or a stretch of a bundled sura recitation (a word
/// or an ayah). Clips are a few kilobytes of bundled AAC and recitations under 1 MB of MP3, so
/// loading them on the main actor costs well under a frame.
@MainActor
final class ClipPlayer {
    // MARK: Internal

    func play(_ clip: AudioClip) {
        start(clip.url, from: 0, until: nil)
    }

    func play(_ segment: RecitationSegment) {
        start(segment.url, from: segment.start, until: segment.end)
    }

    func stop() {
        stopTask?.cancel()
        player?.stop()
        player = nil
    }

    /// Playback, not ambient: a learner with the ringer off still needs to hear the letter.
    static func usePlaybackSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: Private

    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?
    private var sessionConfigured = false

    private func start(_ url: URL, from start: TimeInterval, until end: TimeInterval?) {
        if !sessionConfigured {
            Self.usePlaybackSession()
            sessionConfigured = true
        }
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player = player
        player.currentTime = start
        player.play()
        if let end {
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, end - start)))
                guard !Task.isCancelled, self?.player === player else { return }
                player.stop()
            }
        }
    }
}
