//
//  StudyGoalsAndActivityTrackerTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import Foundation
import MemorizationPersistence
import QuranKit
import XCTest
@testable import MemorizationService

final class StudyGoalsAndActivityTrackerTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        store = TemporaryCoreDataStore()
        persistence = CoreDataMemorizationPersistence(stack: store.stack())
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDown() {
        persistence = nil
        store = nil
        super.tearDown()
    }

    func testPresetsCreateExpectedSchedulesAndTargets() async throws {
        // 2026-11-27 is a Friday in UTC.
        let friday = utcDate(2026, 11, 27, 9, 0)
        let service = makeService(now: { friday })

        let kahf = try await service.createPresetGoal(.fridayAlKahf, title: "Friday Al-Kahf", calendar: calendar)
        let ramadan = try await service.createPresetGoal(.ramadanKhatmah, title: "Ramadan Khatmah", calendar: calendar)
        let sevenPart = try await service.createPresetGoal(.sevenPartWeek, title: "7-Part Week", calendar: calendar)

        let plan = try await service.todayPlan(calendar: calendar)
        XCTAssertEqual(plan.goals.count, 3)

        let kahfSnap = try XCTUnwrap(plan.goals.first { $0.goal.id == kahf.id })
        XCTAssertTrue(kahfSnap.isScheduledToday)
        XCTAssertEqual(kahfSnap.todayTarget, 1)
        XCTAssertEqual(kahfSnap.goal.weekdayMask, WeekdaySchedule.friday.rawValue)
        XCTAssertEqual(kahfSnap.navigationTarget(in: .hafsMadani1405), AyahNumber(quran: .hafsMadani1405, sura: 18, ayah: 1))

        let ramadanSnap = try XCTUnwrap(plan.goals.first { $0.goal.id == ramadan.id })
        XCTAssertEqual(ramadanSnap.totalTarget, 604)
        XCTAssertEqual(ramadanSnap.remainingScheduledDays, 30)
        XCTAssertEqual(ramadanSnap.todayTarget, 21) // ceil(604 / 30)
        XCTAssertEqual(ramadanSnap.nextKhatmahPage, 1)
        XCTAssertEqual(ramadanSnap.todayKhatmahPageRange, 1 ... 21)

        let sevenSnap = try XCTUnwrap(plan.goals.first { $0.goal.id == sevenPart.id })
        XCTAssertEqual(sevenSnap.totalTarget, 604)
        XCTAssertEqual(sevenSnap.remainingScheduledDays, 7)
        XCTAssertEqual(sevenSnap.todayTarget, 87) // ceil(604 / 7)

        // On Saturday (next day), Friday Al-Kahf is a rest day.
        let saturday = utcDate(2026, 11, 28, 9, 0)
        let saturdayPlan = try await makeService(now: { saturday }).todayPlan(calendar: calendar)
        let kahfSaturday = try XCTUnwrap(saturdayPlan.goals.first { $0.goal.id == kahf.id })
        XCTAssertFalse(kahfSaturday.isScheduledToday)
        XCTAssertEqual(kahfSaturday.todayTarget, 0)
    }

    func testKhatmahReplanningPreservesCompletedHistoryAndRecalculatesDailyTarget() async throws {
        var current = utcDate(2026, 11, 1, 8, 0)
        let service = makeService(now: { current })

        let khatmah = try await service.createPresetGoal(.ramadanKhatmah, title: "Ramadan Khatmah", calendar: calendar)

        // Log 80 pages across the first 4 days (20 pages/day).
        for dayOffset in 0 ..< 4 {
            current = utcDate(2026, 11, 1 + dayOffset, 10, 0)
            _ = try await service.logManualProgress(for: khatmah, amount: 20, date: current)
        }

        // Day 6 (Nov 6): behind pace (80 logged vs ~100 expected), replan to extend deadline by 10 days (Dec 10).
        current = utcDate(2026, 11, 6, 9, 0)
        let newDeadline = utcDate(2026, 12, 10, 0, 0) // 35 scheduled days inclusive (Nov 6..Dec 10)
        let replanned = try await service.replanGoal(
            id: khatmah.id,
            deadline: newDeadline,
            weekdayMask: WeekdaySchedule.all.rawValue,
            workloadMode: .flexible
        )
        XCTAssertNotNil(replanned)

        let plan = try await service.todayPlan(calendar: calendar)
        let snap = try XCTUnwrap(plan.goals.first { $0.goal.id == khatmah.id })
        XCTAssertEqual(snap.totalCompleted, 80, "replanning must keep all previously completed pages")
        XCTAssertEqual(snap.totalRemaining, 524)
        XCTAssertEqual(snap.remainingScheduledDays, 35)
        XCTAssertEqual(snap.todayTarget, 15) // ceil(524 / 35) = 15
        XCTAssertEqual(snap.nextKhatmahPage, 81)
        XCTAssertEqual(snap.todayKhatmahPageRange, 81 ... 95)

        // Logging 10 pages today keeps todayTarget stable at 15 and advances nextKhatmahPage to 91.
        _ = try await service.logManualProgress(for: khatmah, amount: 10, date: current)
        let afterTodayLog = try await service.todayPlan(calendar: calendar)
        let snapAfter = try XCTUnwrap(afterTodayLog.goals.first { $0.goal.id == khatmah.id })
        XCTAssertEqual(snapAfter.todayTarget, 15)
        XCTAssertEqual(snapAfter.todayCompleted, 10)
        XCTAssertEqual(snapAfter.todayRemaining, 5)
        XCTAssertEqual(snapAfter.totalCompleted, 90)
        XCTAssertEqual(snapAfter.nextKhatmahPage, 91)
    }

    func testAllFourActivitiesContributeToMatchingGoalsWithoutMasteryLeak() async throws {
        let day1 = utcDate(2026, 11, 20, 9, 0)
        let day2 = utcDate(2026, 11, 21, 9, 0)
        var current = day1
        let service = makeService(now: { current })

        let readGoal = StudyGoalRecord(
            id: UUID(), title: "Read", kind: .habit, activity: .read, unit: .minutes,
            workloadMode: .fixed, targetAmount: 10, startDate: day1, createdOn: day1, modifiedOn: day1
        )
        let listenGoal = StudyGoalRecord(
            id: UUID(), title: "Listen", kind: .habit, activity: .listen, unit: .minutes,
            workloadMode: .fixed, targetAmount: 5, startDate: day1, createdOn: day1, modifiedOn: day1
        )
        let memorizeGoal = StudyGoalRecord(
            id: UUID(), title: "Memorize", kind: .habit, activity: .memorize, unit: .ayahs,
            workloadMode: .fixed, targetAmount: 4, startDate: day1, createdOn: day1, modifiedOn: day1
        )
        let reviewGoal = StudyGoalRecord(
            id: UUID(), title: "Review", kind: .habit, activity: .review, unit: .passages,
            workloadMode: .fixed, targetAmount: 1, startDate: day1, createdOn: day1, modifiedOn: day1
        )
        for goal in [readGoal, listenGoal, memorizeGoal, reviewGoal] {
            try await service.saveGoal(goal)
        }

        // Day 1: active reading (10 min), listening (6 min), and first-time practice of 112:1-4 (memorize).
        try await service.logActivity(ActivityLogRecord(
            id: UUID(), activity: .read, startedOn: day1, endedOn: day1.addingTimeInterval(600),
            durationSeconds: 600, pagesCount: 2, ayahsCount: 0
        ))
        try await service.logActivity(ActivityLogRecord(
            id: UUID(), activity: .listen, startedOn: day1, endedOn: day1.addingTimeInterval(360),
            durationSeconds: 360, pagesCount: 1, ayahsCount: 10
        ))
        let quran = Quran.hafsMadani1405
        let ikhlas = Passage(quran.suras[111].firstVerse, quran.suras[111].lastVerse)
        _ = try await service.recordSession(
            ikhlas,
            startedOn: day1.addingTimeInterval(-180),
            recalls: ikhlas.verses.map { VerseRecall(verse: $0, outcome: .correct) }
        )

        let planDay1 = try await service.todayPlan(calendar: calendar)
        XCTAssertEqual(planDay1.todayReadingSeconds, 600)
        XCTAssertEqual(planDay1.todayListeningSeconds, 360)
        XCTAssertEqual(planDay1.todayPracticeSeconds, 180)
        XCTAssertTrue(try XCTUnwrap(planDay1.goals.first { $0.goal.id == readGoal.id }).isTodayMet)
        XCTAssertTrue(try XCTUnwrap(planDay1.goals.first { $0.goal.id == listenGoal.id }).isTodayMet)
        XCTAssertTrue(try XCTUnwrap(planDay1.goals.first { $0.goal.id == memorizeGoal.id }).isTodayMet)
        XCTAssertFalse(try XCTUnwrap(planDay1.goals.first { $0.goal.id == reviewGoal.id }).isTodayMet)

        // Day 2: practicing the same passage again counts as review.
        current = day2
        _ = try await service.recordSession(
            ikhlas,
            startedOn: day2.addingTimeInterval(-120),
            recalls: ikhlas.verses.map { VerseRecall(verse: $0, outcome: .correct) }
        )
        let planDay2 = try await service.todayPlan(calendar: calendar)
        XCTAssertTrue(try XCTUnwrap(planDay2.goals.first { $0.goal.id == reviewGoal.id }).isTodayMet)

        // Reading & listening logs must never leak into recall evidence or mistake heatmaps.
        let history = try await persistence.history()
        XCTAssertEqual(history.sessions.count, 2)
        XCTAssertEqual(history.evidence.count, 8)
    }

    func testFridayAlKahfIgnoresBriefGlanceAndCompletesOnSubstantialReading() async throws {
        let friday = utcDate(2026, 11, 27, 10, 0)
        let service = makeService(now: { friday })
        let kahf = try await service.createPresetGoal(.fridayAlKahf, title: "Friday Al-Kahf", calendar: calendar)

        // Brief 1-page glance does not falsely mark Al-Kahf complete.
        try await service.logActivity(ActivityLogRecord(
            id: UUID(), activity: .read, startedOn: friday, endedOn: friday.addingTimeInterval(30),
            durationSeconds: 30, pagesCount: 1, ayahsCount: 0,
            first: MemorizationVerse(sura: 18, ayah: 1), last: MemorizationVerse(sura: 18, ayah: 10)
        ))
        var plan = try await service.todayPlan(calendar: calendar)
        XCTAssertFalse(try XCTUnwrap(plan.goals.first { $0.goal.id == kahf.id }).isTodayMet)

        // Substantial active reading through Al-Kahf completes it.
        try await service.logActivity(ActivityLogRecord(
            id: UUID(), activity: .read, startedOn: friday.addingTimeInterval(60), endedOn: friday.addingTimeInterval(900),
            durationSeconds: 840, pagesCount: 6, ayahsCount: 0,
            first: MemorizationVerse(sura: 18, ayah: 11), last: MemorizationVerse(sura: 18, ayah: 110)
        ))
        plan = try await service.todayPlan(calendar: calendar)
        XCTAssertTrue(try XCTUnwrap(plan.goals.first { $0.goal.id == kahf.id }).isTodayMet)
    }

    func testGentleStreakSkipsRestDaysAndAllowsOneGraceDayPerWeek() async throws {
        // Mon Nov 16 .. Fri Nov 27: schedule Mon-Fri only (Sat & Sun are rest days).
        let weekdaysMask: WeekdaySchedule = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let start = utcDate(2026, 11, 16, 8, 0)
        let today = utcDate(2026, 11, 27, 12, 0) // Friday
        let service = makeService(now: { today })

        let goal = StudyGoalRecord(
            id: UUID(), title: "Weekday Read", kind: .habit, activity: .read, unit: .minutes,
            workloadMode: .fixed, targetAmount: 10, weekdayMask: weekdaysMask.rawValue,
            startDate: start, createdOn: start, modifiedOn: start
        )
        try await service.saveGoal(goal)

        // Active on Mon 23, Tue 24, [missed Wed 25 = 1 grace day], Thu 26, Fri 27; plus Fri 20 (Sat 21 & Sun 22 rest days).
        for day in [20, 23, 24, 26, 27] {
            let t = utcDate(2026, 11, day, 9, 0)
            try await service.logActivity(ActivityLogRecord(
                id: UUID(), activity: .read, startedOn: t, endedOn: t.addingTimeInterval(300),
                durationSeconds: 300, pagesCount: 1
            ))
        }

        let plan = try await service.todayPlan(calendar: calendar)
        XCTAssertEqual(plan.streak.currentStreakDays, 5, "Sat/Sun rest days and 1 missed Wed grace day should not break the streak")
        XCTAssertTrue(plan.streak.graceDayUsedInCurrentStreak)
        XCTAssertTrue(plan.streak.isActiveToday)
        XCTAssertEqual(plan.streak.activeDaysThisWeek, 4) // Nov 21..27 -> 23, 24, 26, 27

        // Missing a second scheduled day in the same week (removing Tue 24) breaks the streak back to Thu+Fri (2).
        let history = try await persistence.history()
        let tueLog = try XCTUnwrap(history.activityLogs.first { calendar.component(.day, from: $0.startedOn) == 24 })
        try await service.retractActivityLog(id: tueLog.id)

        let afterSecondMiss = try await service.todayPlan(calendar: calendar)
        XCTAssertEqual(afterSecondMiss.streak.currentStreakDays, 2)
    }

    func testActiveTimeTrackerEnforcesIdleCutoffBackgroundPauseAndPlaybackOnly() throws {
        var now = utcDate(2026, 11, 27, 10, 0)
        let tracker = ActiveTimeTracker(
            idleCutoffSeconds: 120,
            minimumFlushSeconds: 5,
            periodicFlushSeconds: 600,
            pageDwellSeconds: 5,
            now: { now }
        )
        let quran = Quran.hafsMadani1405
        let page1 = quran.pages[0]
        let page2 = quran.pages[1]

        // Visible reading on page 1 for 45 seconds, then turn to page 2.
        tracker.readerDidAppear(pages: [page1])
        now = now.addingTimeInterval(45)
        XCTAssertNil(tracker.recordReadingInteraction(pages: [page2]))

        // User walks away for 45 minutes with screen awake: idle cutoff caps this span at 120 s.
        now = now.addingTimeInterval(45 * 60)
        let readLog = try XCTUnwrap(tracker.appWillResignActive())
        XCTAssertEqual(readLog.activity, .read)
        XCTAssertEqual(readLog.durationSeconds, 45 + 120, "idle cutoff must prevent 45 unattended minutes from counting")
        XCTAssertEqual(readLog.pagesCount, 2)

        // While app is inactive/backgrounded, reading interactions are ignored.
        now = now.addingTimeInterval(300)
        XCTAssertNil(tracker.recordReadingInteraction(pages: [page2]))
        XCTAssertNil(tracker.readerDidDisappear())

        // Audio playback counts ONLY actual playing time, even while app is in background.
        tracker.audioDidStartPlaying(ayah: quran.suras[0].verses[0])
        now = now.addingTimeInterval(20)
        tracker.audioDidPlay(ayah: quran.suras[0].verses[1])
        now = now.addingTimeInterval(25)
        let listenLog = try XCTUnwrap(tracker.audioDidPauseOrStop())
        XCTAssertEqual(listenLog.activity, .listen)
        XCTAssertEqual(listenLog.durationSeconds, 45)
        XCTAssertEqual(listenLog.ayahsCount, 2)
        XCTAssertEqual(listenLog.pagesCount, 1)

        // Paused time does not count when stopping again.
        now = now.addingTimeInterval(600)
        XCTAssertNil(tracker.audioDidPauseOrStop())
    }

    // MARK: Private

    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var calendar: Calendar!

    private func makeService(now: @escaping @Sendable () -> Date) -> MemorizationService {
        MemorizationService(persistence: persistence, quran: .hafsMadani1405, now: now)
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components)!
    }
}
