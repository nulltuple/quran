//
//  NoorSystemImage.swift
//
//
//  Created by Mohamed Afifi on 2023-06-25.
//

import SwiftUI
import UIKit

public enum NoorSystemImage: String {
    case audio = "headphones"
    case downloads = "square.and.arrow.down"
    case download = "icloud.and.arrow.down"
    case cloud = "cloud.fill"
    case translation = "globe"
    case tafsir = "text.book.closed"
    case wordStudy = "character.book.closed"
    case hearWord = "speaker.wave.2"
    case heart
    case share = "square.and.arrow.up"
    case star
    case starFilled = "star.fill"
    case mail = "envelope"
    case privacy = "hand.raised"
    case checkmark_checked = "checkmark.circle.fill"
    case checkmark_unchecked = "circle"
    case checkmark_indeterminate = "minus.circle.fill"
    case checkmark
    case bookmarkOutline = "bookmark"
    case bookmark = "bookmark.fill"
    case book
    case bookFilled = "book.fill"
    case colorSwatch = "circle.fill"
    case plus
    case plusCircle = "plus.circle"
    case notes = "text.bubble"
    case notesFilled = "text.bubble.fill"
    case lastPage = "clock"
    case profile = "person.crop.circle"
    case settings = "gearshape"
    case settingsFilled = "gearshape.fill"
    case signOut = "rectangle.portrait.and.arrow.right"
    case search = "magnifyingglass"
    case mushafs = "books.vertical"
    case appearance = "circle.lefthalf.filled"
    case debug = "ant"
    case play = "play.fill"
    case stop = "stop.fill"
    case pause = "pause.fill"
    case audioOptions = "slider.horizontal.3"
    case edit = "pencil"
    case backward = "backward.fill"
    case forward = "forward.fill"
    case cancel = "xmark"
    case reciter = "music.mic"
    case playbackSpeed = "speedometer"
    case playUpTo = "arrow.right.to.line"
    case rangeStart = "text.line.first.and.arrowtriangle.forward"
    case rangeEnd = "text.line.last.and.arrowtriangle.forward"
    case repeatVerse = "repeat.1"
    case repeatRange = "repeat"
    case pauseDelay = "timer"
    case stream = "cloud"
    case dimOtherAyahs = "text.viewfinder"
    case infinity
    case storageFull = "externaldrive.badge.exclamationmark"
    case externalLink = "arrow.up.right"
    case rotateToPortrait = "rectangle.portrait.rotate"
    case rotateToLandscape = "rectangle.landscape.rotate"

    // MARK: Navigation and disclosure

    case navigateBack = "chevron.backward"
    case disclosure = "chevron.right"
    case expand = "chevron.down"
    case collapse = "chevron.up"
    case popUpMenu = "chevron.up.chevron.down"
    case more = "ellipsis"
    case moreCircle = "ellipsis.circle"
    case sortOrder = "arrow.up.arrow.down"
    /// Quran pages turn right to left, so the next verse points left and `previousVerse` points right.
    case nextVerse = "chevron.left"

    // MARK: Actions

    case copy = "doc.on.doc"
    case rename = "pencil.line"
    case closeCircle = "xmark.circle"
    case closeCircleFilled = "xmark.circle.fill"

    // MARK: Themes

    case lightTheme = "sun.horizon.fill"
    case darkTheme = "moon.stars.fill"

    // MARK: Reading selector

    case readingFeatureSupported = "checkmark.seal"
    case readingFeatureMissing = "xmark.seal"

    // MARK: Account and sync

    case cloudSyncInfo = "link.icloud"
    case syncSucceeded = "checkmark.circle"
    case syncStatusFailed = "exclamationmark.circle"
    case syncStatusHeld = "exclamationmark.triangle"
    case syncRunPartial = "arrow.down.circle"

    // MARK: Sync reveal

    case syncAcrossDevices = "arrow.triangle.2.circlepath"
    case iCloud = "icloud"
    case migrationArrow = "arrow.forward"
    case iPhone = "iphone"
    case iPad = "ipad"

    // MARK: Backup

    case backup = "externaldrive"
    case restoreBackup = "arrow.down.doc"

    // MARK: Voice search

    case voiceSearch = "mic"
    case listening = "mic.fill"
    case heardNothing = "mic.slash"

    // MARK: Hifz practice

    case hifzPractice = "eye.slash"
    case revealWord = "eye"
    case revealAyah = "chevron.left.2"
    case firstLetterHint = "lightbulb"
    case memorizationMap = "square.grid.2x2"
    case reschedule = "calendar"
    case skipPassage = "forward.end"
    case splitPassage = "scissors"
    case resetProgress = "arrow.counterclockwise"
    case spotTest = "checklist"
    case mistakeHeatmap = "flame"
    case repairQueue = "wrench.and.screwdriver"
    case studyGoal = "target"

    // MARK: Arabican tabs (ArabicLearning package)

    case learn = "graduationcap"
    case practice = "rectangle.stack"
    case learningProgress = "chart.bar"

    // MARK: Public

    // Raw values must be unique, so a symbol that means something else in another place is an alias.

    public static var previousVerse: NoorSystemImage { .disclosure }
    public static var delete: NoorSystemImage { .cancel }
    public static var autoTheme: NoorSystemImage { .appearance }
    public static var syncRunFailed: NoorSystemImage { .closeCircle }
    public static var study: NoorSystemImage { .book }
    public static var listenAndRepeat: NoorSystemImage { .hearWord }
    public static var stopListening: NoorSystemImage { .stop }
    public static var practiceOptions: NoorSystemImage { .audioOptions }
    public static var reviewQueue: NoorSystemImage { .practice }
    public static var declareMemorized: NoorSystemImage { .plusCircle }
    public static var reviewBudgets: NoorSystemImage { .audioOptions }
    public static var spotTestTimer: NoorSystemImage { .pauseDelay }
    public static var hideLocation: NoorSystemImage { .hifzPractice }
    public static var replayTest: NoorSystemImage { .resetProgress }
    public static var similarVerses: NoorSystemImage { .practice }
    public static var mistakeHistory: NoorSystemImage { .syncStatusHeld }
    public static var confirmMistake: NoorSystemImage { .syncSucceeded }
    public static var disputeMistake: NoorSystemImage { .closeCircle }
    public static var gentleStreak: NoorSystemImage { .mistakeHeatmap }
    public static var replanGoal: NoorSystemImage { .reschedule }
    public static var goalComplete: NoorSystemImage { .checkmark_checked }
    public static var website: NoorSystemImage { .translation }
    public static var exportBackup: NoorSystemImage { .share }
    /// Follow my recitation in the reader (V2a): the microphone, as voice search shows it.
    public static var reciteAlong: NoorSystemImage { .voiceSearch }

    public var image: Image {
        Image(systemName: rawValue)
    }

    public var uiImage: UIImage? {
        UIImage(systemName: rawValue)
    }
}
