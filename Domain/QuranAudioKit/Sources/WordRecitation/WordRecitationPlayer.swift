//
//  WordRecitationPlayer.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import AVFoundation
import VLogging

/// Plays one word's excerpt of a sura recording with its own `AVPlayer`. It leaves the main
/// recitation player, its queue, Now Playing and the remote commands untouched, and does not
/// change the audio session (the reader's `QueuePlayer` has set it to playback).
@MainActor
public final class WordRecitationPlayer {
    // MARK: Lifecycle

    public init() {
    }

    // MARK: Public

    public enum Outcome: Equatable, Sendable {
        /// The excerpt played to its end.
        case finished
        /// `stop()` or a newer `play(_:)` ended it.
        case stopped
        /// The file could not be loaded or played, such as a stream without a connection.
        case failed
    }

    /// Plays `recitation` from its start to its end and returns when it ends.
    public func play(_ recitation: WordRecitation) async -> Outcome {
        stop()
        logger.info("WordRecitationPlayer: playing \(recitation.word.verse.nonLocalizedDescription) word \(recitation.word.wordNumber), downloaded: \(recitation.isDownloaded)")
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            start(recitation)
        }
    }

    public func stop() {
        finish(.stopped)
    }

    // MARK: Private

    private var player: AVPlayer?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var boundaryObserver: Any?
    private var failureObserver: NSObjectProtocol?

    private func start(_ recitation: WordRecitation) {
        // No precise timing, like the main player: it makes an MP3 wait for a full scan or download,
        // and the word timings were cut against the same estimate the main player seeks with.
        let item = AVPlayerItem(asset: AVURLAsset(url: recitation.url))
        let player = AVPlayer(playerItem: item)
        self.player = player

        let start = CMTime(seconds: recitation.start, preferredTimescale: 1000)
        let end = CMTime(seconds: recitation.end, preferredTimescale: 1000)
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: end)], queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.finish(.finished) }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(.failed) }
        }
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor in
                self?.itemStatusChanged(status, player: player, start: start)
            }
        }
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, player: AVPlayer, start: CMTime) {
        // A stopped or replaced excerpt's late status is ignored.
        guard player === self.player else {
            return
        }
        switch status {
        case .readyToPlay:
            statusObservation = nil
            player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                Task { @MainActor in
                    guard completed, player === self?.player else {
                        return
                    }
                    player.play()
                }
            }
        case .failed:
            logger.error("WordRecitationPlayer: item failed. Error: \(String(describing: player.currentItem?.error))")
            finish(.failed)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func finish(_ outcome: Outcome) {
        if let player {
            player.pause()
            if let boundaryObserver {
                player.removeTimeObserver(boundaryObserver)
            }
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        statusObservation = nil
        boundaryObserver = nil
        failureObserver = nil
        player = nil
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
