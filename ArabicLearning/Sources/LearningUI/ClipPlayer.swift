//
//  ClipPlayer.swift
//  ArabicLearning (Arabican app)
//

import AVFoundation
import LearningModel

/// Plays one letter recording at a time. Clips are a few kilobytes of bundled AAC, so loading
/// them on the main actor costs well under a frame.
@MainActor
final class ClipPlayer {
    // MARK: Internal

    func play(_ clip: AudioClip) {
        if !sessionConfigured {
            // Playback, not ambient: a learner with the ringer off still needs to hear the letter.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            sessionConfigured = true
        }
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: clip.url)
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    // MARK: Private

    private var player: AVAudioPlayer?
    private var sessionConfigured = false
}
