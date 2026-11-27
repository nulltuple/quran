//
//  RecitationMicrophone.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import AVFoundation
import Utilities

/// Records from the microphone into memory for recognition: up to `maximumSeconds`, never to a
/// file. While it records, the audio session is set to record; `stop()` puts back the category the
/// app had (`QueuePlayer` sets `.playback` once, at launch).
@MainActor
public final class RecitationMicrophone {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public static let maximumSeconds = 60.0

    public var isRecording: Bool {
        engine.isRunning
    }

    /// Asks for microphone access the first time, then starts recording.
    public func start() async throws {
        guard !engine.isRunning else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecitationMicrophoneError.permissionDenied
        }
        let session = AVAudioSession.sharedInstance()
        previousCategory = (session.category, session.mode, session.categoryOptions)
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            restoreSession()
            throw RecitationMicrophoneError.noInput
        }
        inputSampleRate = format.sampleRate
        let maximumFrames = Int(format.sampleRate * Self.maximumSeconds)
        let recorded = recorded
        recorded.withCriticalRegion { samples in
            samples = []
            samples.reserveCapacity(maximumFrames)
        }
        // The tap runs on the audio thread: it only appends the first channel under the lock.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            recorded.withCriticalRegion { samples in
                let room = maximumFrames - samples.count
                if room > 0 {
                    samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: min(frames, room)))
                }
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            restoreSession()
            throw error
        }
    }

    /// The loudest sample (0–1) of the last `seconds` recorded, for a level meter and for
    /// `EndOfRecitationDetector`; 0 when nothing is recorded.
    public func recentPeak(seconds: Double = 0.3) -> Float {
        let count = Int(inputSampleRate * seconds)
        return recorded.withCriticalRegion { samples in
            var peak: Float = 0
            for sample in samples.suffix(count) {
                peak = max(peak, abs(sample))
            }
            return peak
        }
    }

    /// Stops recording and returns what was recorded, as 16 kHz mono samples. The recording is not
    /// kept.
    public func stop() throws -> [Float] {
        guard engine.isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        restoreSession()
        let samples = recorded.withCriticalRegion { samples in
            defer { samples = [] }
            return samples
        }
        return try RecitationAudio.resample(mono: samples, sampleRate: inputSampleRate)
    }

    // MARK: Private

    private let engine = AVAudioEngine()
    private let recorded = ManagedCriticalState<[Float]>([])
    private var inputSampleRate = Double(RecitationAudio.sampleRate)
    private var previousCategory: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    private func restoreSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if let (category, mode, options) = previousCategory {
            try? session.setCategory(category, mode: mode, options: options)
        }
        previousCategory = nil
    }
}

public enum RecitationMicrophoneError: Error, Equatable {
    /// The user has not allowed microphone access (Settings > Privacy & Security > Microphone).
    case permissionDenied
    /// The device has no audio input.
    case noInput
}
