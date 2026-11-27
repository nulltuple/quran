//
//  EndOfRecitationDetector.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

/// Decides when someone has finished reciting, from the microphone's level sampled a few times a
/// second: after they have said something, a pause of `pauseSeconds` ends the recitation. "Quiet" is
/// a level in the lowest `quietFraction` of the range between the room's noise (the quietest level
/// heard) and the loudest, so it adapts to the room and the microphone. Speech is a level at least
/// `speechOverNoise` times the room's noise (about 10 dB above it) and above `speechFloor` (about
/// −40 dBFS): a noisy room alone is never speech.
public struct EndOfRecitationDetector: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        pauseSeconds: Double = 2,
        minimumSeconds: Double = 2,
        maximumSeconds: Double = 30,
        silentGiveUpSeconds: Double = 8,
        quietFraction: Float = 0.2,
        speechFloor: Float = 0.01,
        speechOverNoise: Float = 3
    ) {
        self.pauseSeconds = pauseSeconds
        self.minimumSeconds = minimumSeconds
        self.maximumSeconds = maximumSeconds
        self.silentGiveUpSeconds = silentGiveUpSeconds
        self.quietFraction = quietFraction
        self.speechFloor = speechFloor
        self.speechOverNoise = speechOverNoise
    }

    // MARK: Public

    public enum Decision: Equatable, Sendable {
        case keepListening
        /// Speech was heard and then a pause, or the time limit was reached.
        case finished
        /// Nothing louder than the room (or the speech floor) was heard in `silentGiveUpSeconds`.
        case heardNothing
    }

    /// True once speech has been heard: a level well above the room's noise.
    public private(set) var heardSpeech = false

    /// Takes the peak level (0–1) of the last fraction of a second, `elapsed` seconds after
    /// recording started.
    public mutating func update(elapsed: Double, peak: Float) -> Decision {
        loudest = max(loudest, peak)
        // A window before the first samples arrive reads 0; it says nothing about the room.
        if peak > 0 {
            noise = min(noise, peak)
        }
        // Noise only falls and the loudest only rises, so once true this stays true; judging the
        // loudest level against the latest noise also counts speech that began in the first window.
        if loudest >= max(speechFloor, noise * speechOverNoise) {
            heardSpeech = true
        }
        if elapsed >= maximumSeconds {
            return heardSpeech ? .finished : .heardNothing
        }
        guard heardSpeech else {
            return elapsed >= silentGiveUpSeconds ? .heardNothing : .keepListening
        }
        if peak < noise + (loudest - noise) * quietFraction {
            let start = quietSince ?? elapsed
            quietSince = start
            if elapsed - start >= pauseSeconds, elapsed >= minimumSeconds {
                return .finished
            }
        } else {
            quietSince = nil
        }
        return .keepListening
    }

    // MARK: Private

    private let pauseSeconds: Double
    private let minimumSeconds: Double
    private let maximumSeconds: Double
    private let silentGiveUpSeconds: Double
    private let quietFraction: Float
    private let speechFloor: Float
    private let speechOverNoise: Float
    private var loudest: Float = 0
    private var noise: Float = 1
    private var quietSince: Double?
}
