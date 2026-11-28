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

    /// Keeps the first `seconds` recorded, then ignores the rest (recite and check: a passage).
    public init(maximumSeconds seconds: Double) {
        keepsLatest = false
        retainedSeconds = seconds
    }

    /// Keeps only the latest `seconds` recorded, however long it records (live follow).
    public init(keepingLatestSeconds seconds: Double) {
        keepsLatest = true
        retainedSeconds = seconds
    }

    // MARK: Public

    public static let maximumSeconds = 60.0

    public var isRecording: Bool {
        isActiveSession || engine.isRunning || simulatedFeed != nil
    }

    /// Monotonic counter incremented whenever new audio frames are appended to the buffer.
    /// Live streaming loops check this to avoid re-running Core ML on an unchanged buffer.
    public var sampleGeneration: Int {
        state.withCriticalRegion(\.generation)
    }

    /// Asks for microphone access the first time, then starts recording.
    public func start() async throws {
        guard !isRecording else { return }
        #if DEBUG
        if let files = Self.simulatedInputFiles() {
            try startSimulatedInput(files)
            return
        }
        #endif
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecitationMicrophoneError.permissionDenied
        }
        let session = AVAudioSession.sharedInstance()
        previousCategory = (session.category, session.mode, session.categoryOptions)
        // Use `.default` mode instead of `.measurement` so iOS applies standard microphone gain;
        // `.measurement` disables hardware AGC and leaves soft voice / external speaker playback ~20 dB quiet.
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let capacity = Int(max(1, engine.inputNode.outputFormat(forBus: 0).sampleRate) * retainedSeconds)
        state.withCriticalRegion { buffer in
            buffer.samples = []
            buffer.samples.reserveCapacity(keepsLatest ? 2 * capacity : capacity)
            buffer.generation = 0
        }
        do {
            try startEngineTap()
        } catch {
            restoreSession()
            throw error
        }
        isActiveSession = true
        installAudioObservers()
    }

    /// The loudest sample (0–1) of the last `seconds` recorded, for a level meter and for
    /// `EndOfRecitationDetector`; 0 when nothing is recorded.
    public func recentPeak(seconds: Double = 0.3) -> Float {
        let count = Int(inputSampleRate * seconds)
        return state.withCriticalRegion { buffer in
            var peak: Float = 0
            for sample in buffer.samples.suffix(count) {
                peak = max(peak, abs(sample))
            }
            return peak
        }
    }

    /// The latest `seconds` recorded, as 16 kHz mono samples, while recording goes on (live
    /// follow's window); empty when nothing is recorded.
    public func recentSamples(seconds: Double) throws -> [Float] {
        let count = Int(inputSampleRate * seconds)
        let samples = state.withCriticalRegion { Array($0.samples.suffix(count)) }
        return try RecitationAudio.resample(mono: samples, sampleRate: inputSampleRate)
    }

    /// Discards the audio buffered so far while keeping the microphone running (for example when
    /// cumulative practice jumps back to an earlier ayah and must not match what was just said).
    public func clearBuffer() {
        state.withCriticalRegion { buffer in
            buffer.samples.removeAll(keepingCapacity: true)
            buffer.generation &+= 1
        }
    }

    /// Stops recording and returns what was recorded, as 16 kHz mono samples. The recording is not
    /// kept.
    public func stop() throws -> [Float] {
        guard isRecording else { return [] }
        removeAudioObservers()
        isActiveSession = false
        if let simulatedFeed {
            simulatedFeed.cancel()
            self.simulatedFeed = nil
        } else {
            if hasInstalledTap {
                engine.inputNode.removeTap(onBus: 0)
                hasInstalledTap = false
            }
            engine.stop()
            restoreSession()
        }
        let samples = state.withCriticalRegion { buffer in
            defer { buffer.samples = [] }
            return buffer.samples
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

    // MARK: Simulated input

    /// The `UserDefaults` key of the developer loopback (debug builds only): comma-separated paths
    /// of audio files the recording plays in real time instead of the microphone, with
    /// `simulatedGapSeconds` of near-silence before each and after the last until `stop()`. Set it
    /// for the simulator with a launch argument (`xcrun simctl launch <udid> com.nulltup.memquran
    /// -RecitationSimulatedInput /path/a.mp3,/path/b.mp3`), so hands-on checks of voice search, live
    /// follow and recite-and-check hear the same clean audio on every run, without the Mac's
    /// speaker, microphone or room noise.
    public static let simulatedInputKey = "RecitationSimulatedInput"
    nonisolated static let simulatedGapSeconds = 1.0
    /// The near-silence between files: a quiet floor like a phone's in a still room, not zeros, so
    /// `SpeechLevel` measures a room as it does with a real microphone.
    nonisolated static let simulatedNoiseAmplitude: Float = 0.002

    static func simulatedInputFiles(_ defaults: UserDefaults = .standard) -> [URL]? {
        guard let value = defaults.string(forKey: simulatedInputKey), !value.isEmpty else {
            return nil
        }
        return value.split(separator: ",").map { URL(fileURLWithPath: String($0)) }
    }

    /// The samples a simulated recording plays: each file after a gap of quiet floor.
    nonisolated static func simulatedSignal(_ clips: [[Float]]) -> [Float] {
        let gap = Int(simulatedGapSeconds * Double(RecitationAudio.sampleRate))
        var generator = SystemRandomNumberGenerator()
        var signal: [Float] = []
        for clip in clips {
            signal += (0 ..< gap).map { _ in Float.random(in: -simulatedNoiseAmplitude ... simulatedNoiseAmplitude, using: &generator) }
            signal += clip
        }
        return signal
    }

    func startSimulatedInput(_ files: [URL]) throws {
        let signal = try Self.simulatedSignal(files.map(RecitationAudio.samples(contentsOf:)))
        inputSampleRate = Double(RecitationAudio.sampleRate)
        let capacity = Int(inputSampleRate * retainedSeconds)
        let keepsLatest = keepsLatest
        let state = state
        state.withCriticalRegion { buffer in
            buffer.samples = []
            buffer.generation = 0
        }
        let chunk = RecitationAudio.sampleRate / 10
        // Detached: the feed paces itself with the clock and writes under the lock, off the main actor.
        simulatedFeed = Task.detached {
            let clock = ContinuousClock()
            var next = clock.now
            var position = 0
            while !Task.isCancelled {
                let piece: [Float] = if position < signal.count {
                    Array(signal[position ..< min(position + chunk, signal.count)])
                } else {
                    (0 ..< chunk).map { _ in Float.random(in: -Self.simulatedNoiseAmplitude ... Self.simulatedNoiseAmplitude) }
                }
                position += chunk
                piece.withUnsafeBufferPointer { incoming in
                    state.withCriticalRegion { buffer in
                        Self.append(incoming, to: &buffer.samples, capacity: capacity, keepsLatest: keepsLatest)
                        buffer.generation &+= 1
                    }
                }
                next += .milliseconds(100)
                try? await clock.sleep(until: next)
            }
        }
    }

    // MARK: Private

    private struct BufferState {
        var samples: [Float] = []
        var generation = 0
    }

    private var simulatedFeed: Task<Void, Never>?
    private let keepsLatest: Bool
    private let retainedSeconds: Double
    private let engine = AVAudioEngine()
    private let state = ManagedCriticalState<BufferState>(BufferState())
    private var inputSampleRate = Double(RecitationAudio.sampleRate)
    private var previousCategory: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private var isActiveSession = false
    private var hasInstalledTap = false
    private var observerTokens: [NSObjectProtocol] = []

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func startEngineTap() throws {
        let input = engine.inputNode
        if hasInstalledTap {
            input.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecitationMicrophoneError.noInput
        }
        inputSampleRate = format.sampleRate
        let capacity = Int(format.sampleRate * retainedSeconds)
        let keepsLatest = keepsLatest
        let state = state
        // The tap runs on the audio thread: it only appends the first channel under the lock.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let incoming = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            state.withCriticalRegion { bufferState in
                Self.append(incoming, to: &bufferState.samples, capacity: capacity, keepsLatest: keepsLatest)
                bufferState.generation &+= 1
            }
        }
        hasInstalledTap = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            hasInstalledTap = false
            throw error
        }
    }

    private func installAudioObservers() {
        removeAudioObservers()
        let center = NotificationCenter.default
        let configToken = center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restartEngineIfActive()
            }
        }
        let interruptionToken = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }
        observerTokens = [configToken, interruptionToken]
    }

    private func removeAudioObservers() {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens = []
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard isActiveSession, let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }
        switch type {
        case .began:
            engine.pause()
        case .ended:
            let options = optionsRaw.map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            if options.contains(.shouldResume) || !engine.isRunning {
                restartEngineIfActive()
            }
        @unknown default:
            break
        }
    }

    private func restartEngineIfActive() {
        guard isActiveSession, simulatedFeed == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default)
        try? session.setActive(true)
        do {
            try startEngineTap()
        } catch {
            // Leave session active flag cleared only if stop() is called; caller may keep listening on recovery.
            engine.stop()
        }
    }

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
