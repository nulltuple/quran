//
//  GoalsViewModelTests.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreDataPersistence
import CoreDataPersistenceTestSupport
import Foundation
import MemorizationPersistence
import MemorizationService
import QuranKit
import XCTest
@testable import HifzReviewFeature

@MainActor
final class GoalsViewModelTests: XCTestCase {
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

    func testPresetsManualProgressReplanPauseAndNavigationFlow() async throws {
        let friday = utcDate(2026, 11, 27, 9, 0)
        let service = MemorizationService(persistence: persistence, quran: .hafsMadani1405, now: { friday })
        var openedAyahs: [AyahNumber] = []
        var openedMemorization = 0

        let viewModel = GoalsViewModel(
            service: service,
            openAyah: { openedAyahs.append($0) },
            openMemorization: { openedMemorization += 1 },
            practicePassage: { _ in },
            calendar: calendar,
            now: { friday }
        )

        await viewModel.addPreset(.ramadanKhatmah)
        await viewModel.addPreset(.fridayAlKahf)
        XCTAssertEqual(viewModel.plan.goals.count, 2)
        XCTAssertTrue(viewModel.hasActivePreset(.ramadanKhatmah))
        XCTAssertTrue(viewModel.hasActivePreset(.fridayAlKahf))

        // Log 25 pages on Ramadan Khatmah and verify next page advances to 26.
        let khatmahSnap = try XCTUnwrap(viewModel.plan.goals.first { $0.goal.kind == .khatmah })
        await viewModel.logProgress(for: khatmahSnap, amount: 25)
        let updatedKhatmah = try XCTUnwrap(viewModel.plan.goals.first { $0.goal.kind == .khatmah })
        XCTAssertEqual(updatedKhatmah.totalCompleted, 25)
        XCTAssertEqual(updatedKhatmah.nextKhatmahPage, 26)
        XCTAssertTrue(updatedKhatmah.isTodayMet)

        // Open Khatmah navigates directly to page 26's first verse.
        viewModel.openGoalAction(updatedKhatmah)
        let expectedPage26First = try XCTUnwrap(Page(quran: .hafsMadani1405, pageNumber: 26)?.firstVerse)
        XCTAssertEqual(openedAyahs.last?.sura.suraNumber, expectedPage26First.sura.suraNumber)
        XCTAssertEqual(openedAyahs.last?.ayah, expectedPage26First.ayah)

        // Replan keeps all 25 completed pages while adjusting the deadline.
        let extendedDeadline = utcDate(2027, 1, 25, 0, 0)
        await viewModel.replan(
            updatedKhatmah,
            deadline: extendedDeadline,
            weekdayMask: WeekdaySchedule.all.rawValue,
            workloadMode: .flexible,
            targetAmount: 604
        )
        let replanned = try XCTUnwrap(viewModel.plan.goals.first { $0.goal.kind == .khatmah })
        XCTAssertEqual(replanned.totalCompleted, 25)
        XCTAssertEqual(replanned.goal.deadline, extendedDeadline)

        // Pause and delete leave historical activity intact.
        await viewModel.togglePaused(replanned.goal)
        XCTAssertTrue(try XCTUnwrap(viewModel.plan.goals.first { $0.goal.id == replanned.goal.id }).goal.isPaused)
        await viewModel.confirmRemove(replanned.goal)
        XCTAssertEqual(viewModel.plan.goals.count, 1)
        XCTAssertEqual(viewModel.plan.todayPagesRead, 25, "deleting a goal must not erase historical activity")

        viewModel.openReview()
        XCTAssertEqual(openedMemorization, 1)
    }

    // MARK: Private

    private var store: TemporaryCoreDataStore!
    private var persistence: CoreDataMemorizationPersistence!
    private var calendar: Calendar!

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
