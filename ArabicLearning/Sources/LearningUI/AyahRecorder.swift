//
//  AyahRecorder.swift
//  ArabicLearning (Arabican app)
//

import AVFoundation
import Observation

/// Record and compare (spec 03 §2): the learner records themself and plays it back next to the
/// reciter. Nothing is scored. The recording is one temporary file on this device; a new recording
/// replaces it and `discard()` deletes it, which the reader calls when it closes (risk 9: discard by
/// default, never uploaded, never saved).
@MainActor
@Observable
final class AyahRecorder {
    // MARK: Lifecycle

    init(fileURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("arabican-recording.m4a")) {
        self.fileURL = fileURL
    }

    // MARK: Internal

    enum State: Equatable {
        case idle
        case recording
        case recorded
        case denied
    }

    private(set) var state: State = .idle

    func record() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied
            return
        }
        discard()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: fileURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 22050,
                AVNumberOfChannelsKey: 1,
            ])
            guard recorder.record() else {
                state = .idle
                return
            }
            self.recorder = recorder
            state = .recording
        } catch {
            state = .idle
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        ClipPlayer.usePlaybackSession()
        state = FileManager.default.fileExists(atPath: fileURL.path) ? .recorded : .idle
    }

    func playRecording() {
        guard state == .recorded else { return }
        ClipPlayer.usePlaybackSession()
        player = try? AVAudioPlayer(contentsOf: fileURL)
        player?.play()
    }

    /// Stops and deletes the recording.
    func discard() {
        recorder?.stop()
        recorder = nil
        player?.stop()
        player = nil
        try? FileManager.default.removeItem(at: fileURL)
        if state != .denied {
            state = .idle
        }
    }

    // MARK: Private

    private let fileURL: URL
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
}
