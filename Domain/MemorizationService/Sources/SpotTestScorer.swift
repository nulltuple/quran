//
//  SpotTestScorer.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Foundation

/// A ratio score that cannot exist when its denominator is zero (roadmap H4: "no score when the denominator is zero").
public struct SpotTestRatio: Equatable, Hashable, Sendable {
    // MARK: Lifecycle

    public init?(numerator: Int, denominator: Int) {
        guard denominator > 0 else { return nil }
        self.numerator = min(max(numerator, 0), denominator)
        self.denominator = denominator
    }

    // MARK: Public

    public let numerator: Int
    public let denominator: Int

    public var fraction: Double {
        Double(numerator) / Double(denominator)
    }
}

/// Complete strict and granular score breakdown for a spot test (roadmap H4).
public struct SpotTestScoreReport: Equatable, Sendable {
    // MARK: Public

    /// Planned questions for a count-limited test, or presented questions for a timer-limited test.
    public let plannedQuestions: Int
    /// Total questions reached (assessed + skipped).
    public let presentedQuestions: Int
    /// Questions graded (not skipped).
    public let assessedQuestions: Int
    /// Questions skipped (tracked separately from strict passes).
    public let skippedQuestions: Int
    /// Assessed questions with zero mistakes and zero assistance.
    public let strictPassedQuestions: Int
    /// Assessed questions where any hint, peek, or reveal was used.
    public let assistedQuestions: Int
    /// Assessed questions completed without hints, peeks, or reveals.
    public let unaidedQuestions: Int
    /// Total verses marked as revealed / forgot across assessed questions.
    public let revealedVerses: Int
    /// Total hint and peek actions used across all presented questions.
    public let totalHints: Int
    /// Total canonical words across assessed verses.
    public let assessedWords: Int
    /// Canonical words recalled cleanly across assessed verses.
    public let recalledWords: Int
    /// Longest run of consecutive strict error-free unassisted questions.
    public let bestStreak: Int

    /// Error-free unassisted questions / assessed questions (`nil` if 0 assessed).
    public let strictScore: SpotTestRatio?
    /// Correctly recalled target words / assessed target words (`nil` if 0 assessed words).
    public let wordRecallScore: SpotTestRatio?
    /// Assessed questions / planned (or presented) questions (`nil` if denominator is 0).
    public let coverageScore: SpotTestRatio?
    /// Assisted questions / assessed questions (`nil` if 0 assessed).
    public let assistanceRate: SpotTestRatio?
}

/// Pure scorer computing strict, word-recall, coverage, and assistance metrics for spot tests.
public enum SpotTestScorer {
    /// Scores `results`.
    /// - Parameters:
    ///   - results: Outcomes of all questions presented in the test (assessed and skipped).
    ///   - plannedQuestions: Configured question count for `.count(n)` tests, or `nil` for timed tests
    ///     (where coverage uses `results.count` as its denominator).
    public static func score(
        results: [SpotTestQuestionResult],
        plannedQuestions: Int? = nil
    ) -> SpotTestScoreReport {
        let presented = results.count
        let effectivePlanned = max(plannedQuestions ?? presented, presented)
        let coverageDenominator = plannedQuestions.map { max(0, $0) } ?? presented

        var assessed = 0
        var skipped = 0
        var strictPassed = 0
        var assisted = 0
        var unaided = 0
        var revealedVerses = 0
        var totalHints = 0
        var assessedWords = 0
        var recalledWords = 0
        var currentStreak = 0
        var bestStreak = 0

        for result in results {
            totalHints += result.hintsUsed
            if result.isAssessed {
                assessed += 1
                revealedVerses += result.revealedVerseCount
                assessedWords += result.assessedWords
                recalledWords += result.recalledWords
                if result.neededAssistance {
                    assisted += 1
                } else {
                    unaided += 1
                }
                if result.isStrictPerfect {
                    strictPassed += 1
                    currentStreak += 1
                    bestStreak = max(bestStreak, currentStreak)
                } else {
                    currentStreak = 0
                }
            } else {
                skipped += 1
                currentStreak = 0
            }
        }

        return SpotTestScoreReport(
            plannedQuestions: effectivePlanned,
            presentedQuestions: presented,
            assessedQuestions: assessed,
            skippedQuestions: skipped,
            strictPassedQuestions: strictPassed,
            assistedQuestions: assisted,
            unaidedQuestions: unaided,
            revealedVerses: revealedVerses,
            totalHints: totalHints,
            assessedWords: assessedWords,
            recalledWords: recalledWords,
            bestStreak: bestStreak,
            strictScore: SpotTestRatio(numerator: strictPassed, denominator: assessed),
            wordRecallScore: SpotTestRatio(numerator: recalledWords, denominator: assessedWords),
            coverageScore: SpotTestRatio(numerator: assessed, denominator: max(coverageDenominator, assessed)),
            assistanceRate: SpotTestRatio(numerator: assisted, denominator: assessed)
        )
    }
}
