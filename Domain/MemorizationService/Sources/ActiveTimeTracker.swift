//
//  ActiveTimeTracker.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import QuranKit

/// Tracks active visible reading time (with an idle cutoff so an open unattended Mushaf never inflates
/// study time) and actual audio playback time (counting only `.playing`, never downloading/paused/stopped).
///
/// Pure and deterministic: the clock and UUID generator are injected so every edge case is unit-tested.
/// Recorded `ActivityLogRecord`s never create `RecallEvidenceRecord`s or alter Hifz mastery.
public final class ActiveTimeTracker {
    // MARK: Lifecycle

    public init(
        idleCutoffSeconds: TimeInterval = 120,
        minimumFlushSeconds: Int = 5,
        periodicFlushSeconds: Int = 60,
        pageDwellSeconds: TimeInterval = 5,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> UUID = UUID.init
    ) {
        self.idleCutoffSeconds = max(10, idleCutoffSeconds)
        self.minimumFlushSeconds = max(1, minimumFlushSeconds)
        self.periodicFlushSeconds = max(minimumFlushSeconds, periodicFlushSeconds)
        self.pageDwellSeconds = max(0, pageDwellSeconds)
        self.now = now
        self.makeID = makeID
    }

    // MARK: Public

    public let idleCutoffSeconds: TimeInterval
    public let minimumFlushSeconds: Int
    public let periodicFlushSeconds: Int
    public let pageDwellSeconds: TimeInterval

    /// Whether visible foreground reading is currently being timed.
    public var isReadingActive: Bool {
        isReaderVisible && isAppActive && readingSessionStartedOn != nil
    }

    /// Whether actual audio playback is currently being timed.
    public var isListeningActive: Bool {
        listeningStartedOn != nil
    }

    // MARK: - Visible Reading Tracking

    /// Called when the reader screen appears on screen.
    public func readerDidAppear(pages: [Page]) {
        let timestamp = now()
        isReaderVisible = true
        if isAppActive {
            beginReadingSpanIfNeeded(pages: pages, at: timestamp)
        }
    }

    /// Called when the reader screen disappears; flushes any accumulated active reading span.
    public func readerDidDisappear() -> ActivityLogRecord? {
        let timestamp = now()
        let record = finalizeReadingSpan(at: timestamp)
        isReaderVisible = false
        return record
    }

    /// Called when the app returns to the active foreground state.
    public func appDidBecomeActive(visiblePages: [Page]) {
        let timestamp = now()
        isAppActive = true
        if isReaderVisible {
            beginReadingSpanIfNeeded(pages: visiblePages, at: timestamp)
        }
    }

    /// Called when the app resigns active or enters background; pauses reading timing and flushes.
    public func appWillResignActive() -> ActivityLogRecord? {
        let timestamp = now()
        let record = finalizeReadingSpan(at: timestamp)
        isAppActive = false
        return record
    }

    /// Called on reader interaction (page turn, scroll, tap, word pointer, live follow) to credit active
    /// reading time up to `idleCutoffSeconds` and optionally flush periodically.
    public func recordReadingInteraction(pages: [Page]) -> ActivityLogRecord? {
        let timestamp = now()
        guard isReaderVisible, isAppActive else { return nil }
        if readingSessionStartedOn == nil {
            beginReadingSpanIfNeeded(pages: pages, at: timestamp)
            return nil
        }
        creditReadingElapsed(upTo: timestamp)
        updateVisiblePages(pages, at: timestamp)
        lastReadingHeartbeat = timestamp

        if Int(accumulatedReadingSeconds) >= periodicFlushSeconds {
            let flushed = buildReadingLog(endedOn: timestamp)
            resetReadingAccumulators(keepingPages: pages, at: timestamp)
            return flushed
        }
        return nil
    }

    // MARK: - Actual Audio Playback Tracking

    /// Called when audio transitions into `.playing` (never `.downloading` or `.paused`).
    public func audioDidStartPlaying(ayah: AyahNumber? = nil) {
        let timestamp = now()
        if listeningStartedOn == nil {
            listeningStartedOn = timestamp
            listeningLastTick = timestamp
            accumulatedListeningSeconds = 0
            listenedVerses = []
            listenedPages = []
            listeningFirstVerse = nil
            listeningLastVerse = nil
        }
        if let ayah {
            recordListenedAyah(ayah)
        }
    }

    /// Called when the audio player advances to a playing verse.
    public func audioDidPlay(ayah: AyahNumber) {
        let timestamp = now()
        if listeningStartedOn == nil {
            audioDidStartPlaying(ayah: ayah)
            return
        }
        creditListeningElapsed(upTo: timestamp)
        recordListenedAyah(ayah)
    }

    /// Called when audio transitions to `.paused`, `.stopped`, or completes; flushes actual playback time.
    public func audioDidPauseOrStop() -> ActivityLogRecord? {
        let timestamp = now()
        guard let startedOn = listeningStartedOn else { return nil }
        creditListeningElapsed(upTo: timestamp)
        let seconds = Int(accumulatedListeningSeconds.rounded(.down))
        let record: ActivityLogRecord? = if seconds >= minimumFlushSeconds {
            ActivityLogRecord(
                id: makeID(),
                activity: .listen,
                startedOn: startedOn,
                endedOn: timestamp,
                durationSeconds: seconds,
                pagesCount: listenedPages.count,
                ayahsCount: listenedVerses.count,
                first: listeningFirstVerse,
                last: listeningLastVerse,
                goalID: nil
            )
        } else {
            nil
        }
        listeningStartedOn = nil
        listeningLastTick = nil
        accumulatedListeningSeconds = 0
        listenedVerses = []
        listenedPages = []
        listeningFirstVerse = nil
        listeningLastVerse = nil
        return record
    }

    // MARK: Private

    private let now: () -> Date
    private let makeID: () -> UUID

    // Reading state
    private var isReaderVisible = false
    private var isAppActive = true
    private var readingSessionStartedOn: Date?
    private var lastReadingHeartbeat: Date?
    private var accumulatedReadingSeconds: TimeInterval = 0
    private var currentVisiblePages: [Page] = []
    private var currentPagesShownAt: Date?
    private var creditedPages: Set<Int> = []
    private var readingFirstVerse: MemorizationVerse?
    private var readingLastVerse: MemorizationVerse?

    // Listening state
    private var listeningStartedOn: Date?
    private var listeningLastTick: Date?
    private var accumulatedListeningSeconds: TimeInterval = 0
    private var listenedVerses: Set<MemorizationVerse> = []
    private var listenedPages: Set<Int> = []
    private var listeningFirstVerse: MemorizationVerse?
    private var listeningLastVerse: MemorizationVerse?

    private func beginReadingSpanIfNeeded(pages: [Page], at timestamp: Date) {
        if readingSessionStartedOn == nil {
            readingSessionStartedOn = timestamp
            lastReadingHeartbeat = timestamp
            accumulatedReadingSeconds = 0
            creditedPages = []
            readingFirstVerse = nil
            readingLastVerse = nil
            currentVisiblePages = pages
            currentPagesShownAt = pages.isEmpty ? nil : timestamp
        } else {
            updateVisiblePages(pages, at: timestamp)
        }
    }

    private func creditReadingElapsed(upTo timestamp: Date) {
        guard let last = lastReadingHeartbeat else { return }
        let delta = timestamp.timeIntervalSince(last)
        guard delta > 0 else { return }
        // Idle cutoff: if the user stepped away from an open Mushaf, never credit beyond idleCutoffSeconds.
        accumulatedReadingSeconds += min(delta, idleCutoffSeconds)
    }

    private func updateVisiblePages(_ pages: [Page], at timestamp: Date) {
        let oldNumbers = currentVisiblePages.map(\.pageNumber)
        let newNumbers = pages.map(\.pageNumber)
        if oldNumbers != newNumbers {
            creditCurrentPagesIfDwelled(at: timestamp)
            currentVisiblePages = pages
            currentPagesShownAt = pages.isEmpty ? nil : timestamp
        } else if !pages.isEmpty {
            creditCurrentPagesIfDwelled(at: timestamp)
        }
    }

    private func creditCurrentPagesIfDwelled(at timestamp: Date) {
        guard !currentVisiblePages.isEmpty, let shownAt = currentPagesShownAt else { return }
        let dwell = min(timestamp.timeIntervalSince(shownAt), idleCutoffSeconds)
        guard dwell >= pageDwellSeconds else { return }
        for page in currentVisiblePages {
            creditedPages.insert(page.pageNumber)
            let first = MemorizationVerse(sura: page.firstVerse.sura.suraNumber, ayah: page.firstVerse.ayah)
            let last = MemorizationVerse(sura: page.lastVerse.sura.suraNumber, ayah: page.lastVerse.ayah)
            if let existingFirst = readingFirstVerse {
                readingFirstVerse = min(existingFirst, first)
            } else {
                readingFirstVerse = first
            }
            if let existingLast = readingLastVerse {
                readingLastVerse = max(existingLast, last)
            } else {
                readingLastVerse = last
            }
        }
    }

    private func finalizeReadingSpan(at timestamp: Date) -> ActivityLogRecord? {
        guard readingSessionStartedOn != nil else { return nil }
        creditReadingElapsed(upTo: timestamp)
        creditCurrentPagesIfDwelled(at: timestamp)
        let record = buildReadingLog(endedOn: timestamp)
        readingSessionStartedOn = nil
        lastReadingHeartbeat = nil
        accumulatedReadingSeconds = 0
        currentVisiblePages = []
        currentPagesShownAt = nil
        creditedPages = []
        readingFirstVerse = nil
        readingLastVerse = nil
        return record
    }

    private func buildReadingLog(endedOn: Date) -> ActivityLogRecord? {
        guard let startedOn = readingSessionStartedOn else { return nil }
        let seconds = Int(accumulatedReadingSeconds.rounded(.down))
        guard seconds >= minimumFlushSeconds else { return nil }
        let effectiveEnd = max(startedOn.addingTimeInterval(TimeInterval(seconds)), min(endedOn, startedOn.addingTimeInterval(TimeInterval(seconds))))
        return ActivityLogRecord(
            id: makeID(),
            activity: .read,
            startedOn: startedOn,
            endedOn: effectiveEnd,
            durationSeconds: seconds,
            pagesCount: creditedPages.count,
            ayahsCount: 0,
            first: readingFirstVerse,
            last: readingLastVerse,
            goalID: nil
        )
    }

    private func resetReadingAccumulators(keepingPages pages: [Page], at timestamp: Date) {
        readingSessionStartedOn = timestamp
        lastReadingHeartbeat = timestamp
        accumulatedReadingSeconds = 0
        creditedPages = []
        readingFirstVerse = nil
        readingLastVerse = nil
        currentVisiblePages = pages
        currentPagesShownAt = pages.isEmpty ? nil : timestamp
    }

    private func creditListeningElapsed(upTo timestamp: Date) {
        guard let last = listeningLastTick else { return }
        let delta = timestamp.timeIntervalSince(last)
        if delta > 0 {
            accumulatedListeningSeconds += delta
        }
        listeningLastTick = timestamp
    }

    private func recordListenedAyah(_ ayah: AyahNumber) {
        let verse = MemorizationVerse(sura: ayah.sura.suraNumber, ayah: ayah.ayah)
        listenedVerses.insert(verse)
        listenedPages.insert(ayah.page.pageNumber)
        if let existingFirst = listeningFirstVerse {
            listeningFirstVerse = min(existingFirst, verse)
        } else {
            listeningFirstVerse = verse
        }
        if let existingLast = listeningLastVerse {
            listeningLastVerse = max(existingLast, verse)
        } else {
            listeningLastVerse = verse
        }
    }
}
