//
//  SpeechLevel.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

/// Tells speech from the room's noise in a stream of microphone windows, with the thresholds of
/// `EndOfRecitationDetector`: speech is a peak at least `speechOverNoise` times the room's noise
/// (about 10 dB above it) and above `speechFloor` (about −40 dBFS). Live
/// follow uses it so a pause in a noisy room, which the model may still hear as a few words, is
/// not taken for recitation elsewhere.
public struct SpeechLevel: Equatable, Sendable {
    // MARK: Lifecycle

    public init(speechFloor: Float = 0.01, speechOverNoise: Float = 3) {
        self.speechFloor = speechFloor
        self.speechOverNoise = speechOverNoise
    }

    // MARK: Public

    /// Whether the last second of `window` (16 kHz mono samples) is speech. The room's noise is
    /// the quietest tenth of a second heard so far: recitation pauses between words and for
    /// breath, so even a window recited throughout holds the room's level somewhere.
    public mutating func isSpeech(window: [Float]) -> Bool {
        let chunk = RecitationAudio.sampleRate / 10
        var start = window.startIndex
        while start + chunk <= window.endIndex {
            let peak = Self.peak(of: window[start ..< start + chunk])
            // Digital silence (a window before the first samples arrive) says nothing about the room.
            if peak > 0 {
                noise = min(noise, peak)
            }
            start += chunk
        }
        let latest = Self.peak(of: window.suffix(RecitationAudio.sampleRate))
        return latest >= max(speechFloor, noise * speechOverNoise)
    }

    /// The loudest sample of `samples`, 0 for none.
    public static func peak(of samples: some Collection<Float>) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    // MARK: Private

    private let speechFloor: Float
    private let speechOverNoise: Float
    private var noise: Float = 1
}
