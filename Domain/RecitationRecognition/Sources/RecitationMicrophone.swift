//
//  RecitationMicrophone.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import AVFoundation
import Utilities

/// Records from the microphone into memory for recognition, never to a file: the first
/// `maximumSeconds` of a recording, or, for live follow, only the latest `keepingLatestSeconds`.
/// While it records, the audio session is set to record; `stop()` puts back the category the app
/// had (`QueuePlayer` sets `.playback` once, at launch).
@MainActor
public final class RecitationMicrophone {
    // MARK: Lifecycle

    /// Keeps the first `maximumSeconds` recorded, then ignores the rest.
    public init() {
        keepsLatest = false
        retainedSeconds = Self.maximumSeconds
    }

    /// Keeps only the latest `seconds` recorded, however long it records (live follow).
    public init(keepingLatestSeconds seconds: Double) {
        keepsLatest = true
        retainedSeconds = seconds
    }

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
        let capacity = Int(format.sampleRate * retainedSeconds)
        let keepsLatest = keepsLatest
        let recorded = recorded
        recorded.withCriticalRegion { samples in
            samples = []
            samples.reserveCapacity(keepsLatest ? 2 * capacity : capacity)
        }
        // The tap runs on the audio thread: it only appends the first channel under the lock.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let incoming = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            recorded.withCriticalRegion { samples in
                Self.append(incoming, to: &samples, capacity: capacity, keepsLatest: keepsLatest)
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

    /// The latest `seconds` recorded, as 16 kHz mono samples, while recording goes on (live
    /// follow's window); empty when nothing is recorded.
    public func recentSamples(seconds: Double) throws -> [Float] {
        let count = Int(inputSampleRate * seconds)
        let samples = recorded.withCriticalRegion { Array($0.suffix(count)) }
        return try RecitationAudio.resample(mono: samples, sampleRate: inputSampleRate)
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

    // MARK: Internal

    /// Appends `incoming` to `samples`: up to `capacity` in all, or, when `keepsLatest`, dropping
    /// the oldest so the latest `capacity` remain. The drop happens once twice `capacity` would be
    /// held, so the audio thread copies the buffer only every `capacity` samples.
    nonisolated static func append(_ incoming: UnsafeBufferPointer<Float>, to samples: inout [Float], capacity: Int, keepsLatest: Bool) {
        guard keepsLatest else {
            let room = capacity - samples.count
            if room > 0 {
                samples.append(contentsOf: incoming.prefix(room))
            }
            return
        }
        if samples.count + incoming.count > 2 * capacity {
            samples.removeFirst(min(samples.count, samples.count + incoming.count - capacity))
        }
        samples.append(contentsOf: incoming.suffix(capacity))
    }

    // MARK: Private

    private let keepsLatest: Bool
    private let retainedSeconds: Double
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
