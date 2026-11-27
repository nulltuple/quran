//
//  WordPointerViewModel.swift
//  Quran
//
//  Created by Afifi, Mohamed on 4/13/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import Crashing
import QuranKit
import ReadingService
import UIKit
import VLogging
import WordTextService

@MainActor
public protocol WordPointerListener: AnyObject {
    func onWordPointerPanBegan()
    func word(at point: CGPoint) -> Word?
    func highlightWord(_ position: Word?)
    /// Opens the word study sheet for `word`, numbered as in the ayah's text.
    func presentWordStudy(_ word: Word)
}

@MainActor
final class WordPointerViewModel {
    enum PanResult: Equatable {
        case none
        case hidePopover
        case showPopover(text: String)
    }

    // MARK: Lifecycle

    init(service: WordTextService) {
        self.service = service
    }

    // MARK: Internal

    weak var listener: WordPointerListener?

    func viewPanBegan() {
        listener?.onWordPointerPanBegan()
    }

    func viewPanned(to point: CGPoint) async -> PanResult {
        guard let word = listener?.word(at: point) else {
            logger.debug("No word found at position \(point)")
            unhighlightWord()
            return .hidePopover
        }
        logger.debug("Highlighting word \(word) at position: \(point)")
        listener?.highlightWord(word)
        highlightedWord = word

        if selectedWord == word {
            logger.debug("Same word selected before")
            return .none
        }
        do {
            let pointed = try await service.pointedWord(atImageGlyph: word, reading: readingPreferences.reading)
            // A newer pan event or the end of the drag superseded this lookup.
            guard !Task.isCancelled else {
                logger.debug("Dropping stale text lookup for word \(word)")
                return .none
            }
            if let pointed {
                logger.debug("Found text '\(pointed.text)' for word \(word)")
                selectedWord = word
                pointedWord = pointed
                return .showPopover(text: pointed.text)
            } else {
                logger.debug("No text found for word \(word)")
                pointedWord = nil
                return .hidePopover
            }
        } catch {
            guard !Task.isCancelled else {
                return .none
            }
            crasher.recordError(error, reason: "Error calling WordTextService")
            pointedWord = nil
            return .hidePopover
        }
    }

    /// The drag ended. Returns the word whose popover stays on screen, so a tap on it can open
    /// its word study; `nil` when the pointer is over no word (nothing stays).
    func viewPanEnded() -> PointedWord? {
        // A drag that ended before the last word's lookup finished shows no popover for it.
        guard let pointedWord, let selectedWord, selectedWord == highlightedWord else {
            unhighlightWord()
            return nil
        }
        return pointedWord
    }

    /// The released word's popover was tapped.
    func openReleasedWordStudy() {
        guard let pointedWord else {
            return
        }
        logger.info("WordPointer: open word study for \(pointedWord.word.verse.nonLocalizedDescription) word \(pointedWord.word.wordNumber)")
        unhighlightWord()
        listener?.presentWordStudy(pointedWord.word)
    }

    func unhighlightWord() {
        listener?.highlightWord(nil)
        highlightedWord = nil
        selectedWord = nil
        pointedWord = nil
    }

    // MARK: Private

    private let service: WordTextService
    private let readingPreferences = ReadingPreferences.shared

    private var selectedWord: Word?
    private var highlightedWord: Word?
    /// The word whose text the popover shows.
    private var pointedWord: PointedWord?
}
