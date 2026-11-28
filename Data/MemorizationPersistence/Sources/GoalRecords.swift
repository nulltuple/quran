//
//  GoalRecords.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import CoreDataModel
import Foundation

/// Activity tracked by goals and active-time logging (roadmap H6). Stored as its raw value: never renumber.
public enum GoalActivity: Int, Codable, Hashable, Sendable, CaseIterable {
    case read = 0
    case listen = 1
    case memorize = 2
    case review = 3
}

/// Kind of study goal or plan (roadmap H6). Stored as its raw value: never renumber.
public enum GoalKind: Int, Codable, Hashable, Sendable, CaseIterable {
    /// Recurring habit goal (daily or selected weekdays).
    case habit = 0
    /// Full-Quran or multi-page completion plan with history-preserving replanning.
    case khatmah = 1
    /// Scheduled surah/range goal such as Friday Al-Kahf.
    case weeklySurah = 2
}

/// Measurement unit for a study goal (roadmap H6). Stored as its raw value: never renumber.
public enum GoalUnit: Int, Codable, Hashable, Sendable, CaseIterable {
    case minutes = 0
    case pages = 1
    case ayahs = 2
    case passages = 3
    case juzs = 4
    case completions = 5
}

/// Whether daily workload stays fixed per scheduled day or flexibly adjusts to remaining work before a deadline.
public enum GoalWorkloadMode: Int, Codable, Hashable, Sendable, CaseIterable {
    case fixed = 0
    case flexible = 1
}

/// Bitmask of scheduled weekdays (bit 0 = Sunday ... bit 6 = Saturday, matching `Calendar.component(.weekday)` 1...7).
public struct WeekdaySchedule: OptionSet, Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(rawValue: Int) {
        self.rawValue = rawValue & 0x7F
    }

    // MARK: Public

    public static let sunday = Self(rawValue: 1 << 0)
    public static let monday = Self(rawValue: 1 << 1)
    public static let tuesday = Self(rawValue: 1 << 2)
    public static let wednesday = Self(rawValue: 1 << 3)
    public static let thursday = Self(rawValue: 1 << 4)
    public static let friday = Self(rawValue: 1 << 5)
    public static let saturday = Self(rawValue: 1 << 6)

    public static let all: Self = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    public static let orderedDays: [Self] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

    public let rawValue: Int

    public var isEmpty: Bool { rawValue == 0 }

    /// Calendar weekday (1 = Sunday ... 7 = Saturday).
    public static func weekday(_ calendarWeekday: Int) -> Self {
        guard (1 ... 7).contains(calendarWeekday) else { return [] }
        return Self(rawValue: 1 << (calendarWeekday - 1))
    }

    public func contains(date: Date, calendar: Calendar) -> Bool {
        let day = calendar.component(.weekday, from: date)
        return contains(Self.weekday(day))
    }

    public var count: Int {
        rawValue.nonzeroBitCount
    }
}

/// A persisted reading, listening, memorization, review, or Khatmah goal (roadmap H6).
/// Soft-deleted via `removedOn` so backups and CloudKit sync merge idempotently.
public struct StudyGoalRecord: Hashable, Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        title: String,
        kind: GoalKind,
        activity: GoalActivity,
        unit: GoalUnit,
        workloadMode: GoalWorkloadMode,
        targetAmount: Int,
        weekdayMask: Int = WeekdaySchedule.all.rawValue,
        startDate: Date,
        deadline: Date? = nil,
        startPage: Int = 1,
        targetFirst: MemorizationVerse? = nil,
        targetLast: MemorizationVerse? = nil,
        presetID: String? = nil,
        isPaused: Bool = false,
        createdOn: Date,
        modifiedOn: Date,
        removedOn: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.activity = activity
        self.unit = unit
        self.workloadMode = workloadMode
        self.targetAmount = targetAmount
        self.weekdayMask = weekdayMask
        self.startDate = startDate
        self.deadline = deadline
        self.startPage = startPage
        self.targetFirst = targetFirst
        self.targetLast = targetLast
        self.presetID = presetID
        self.isPaused = isPaused
        self.createdOn = createdOn
        self.modifiedOn = modifiedOn
        self.removedOn = removedOn
    }

    // MARK: Public

    public let id: UUID
    public var title: String
    public var kind: GoalKind
    public var activity: GoalActivity
    public var unit: GoalUnit
    public var workloadMode: GoalWorkloadMode
    /// Fixed per-day target for `.fixed` goals, or total target (e.g. 604 pages) for `.flexible` / `.khatmah` goals.
    public var targetAmount: Int
    public var weekdayMask: Int
    public var startDate: Date
    public var deadline: Date?
    /// Starting Mushaf page (1...604) for Khatmah plans.
    public var startPage: Int
    /// Optional canonical range scope (e.g. 18:1...18:110 for Friday Al-Kahf).
    public var targetFirst: MemorizationVerse?
    public var targetLast: MemorizationVerse?
    public var presetID: String?
    public var isPaused: Bool
    public let createdOn: Date
    public var modifiedOn: Date
    public var removedOn: Date?

    public var schedule: WeekdaySchedule {
        get { WeekdaySchedule(rawValue: weekdayMask) }
        set { weekdayMask = newValue.rawValue }
    }
}

/// One append-only log of active visible reading, actual audio playback, or manual goal check-in (roadmap H6).
/// Never counts as memorization mastery or recall evidence.
public struct ActivityLogRecord: Hashable, Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        activity: GoalActivity,
        startedOn: Date,
        endedOn: Date,
        durationSeconds: Int,
        pagesCount: Int = 0,
        ayahsCount: Int = 0,
        first: MemorizationVerse? = nil,
        last: MemorizationVerse? = nil,
        goalID: UUID? = nil,
        retractedOn: Date? = nil
    ) {
        self.id = id
        self.activity = activity
        self.startedOn = startedOn
        self.endedOn = endedOn
        self.durationSeconds = durationSeconds
        self.pagesCount = pagesCount
        self.ayahsCount = ayahsCount
        self.first = first
        self.last = last
        self.goalID = goalID
        self.retractedOn = retractedOn
    }

    // MARK: Public

    public let id: UUID
    public let activity: GoalActivity
    public let startedOn: Date
    public let endedOn: Date
    public let durationSeconds: Int
    public let pagesCount: Int
    public let ayahsCount: Int
    public let first: MemorizationVerse?
    public let last: MemorizationVerse?
    public let goalID: UUID?
    public var retractedOn: Date?
}

// MARK: - Core Data mapping

extension StudyGoalRecord {
    /// `nil` for a record missing required fields or containing enums from a newer version.
    public init?(_ stored: MO_StudyGoal) {
        guard let id = stored.id,
              let createdOn = stored.createdOn,
              let kind = GoalKind(rawValue: Int(stored.kind)),
              let activity = GoalActivity(rawValue: Int(stored.activity)),
              let unit = GoalUnit(rawValue: Int(stored.unit)),
              let workloadMode = GoalWorkloadMode(rawValue: Int(stored.workloadMode))
        else {
            return nil
        }
        let first: MemorizationVerse? = if stored.targetFirstSura > 0, stored.targetFirstAyah > 0 {
            MemorizationVerse(sura: Int(stored.targetFirstSura), ayah: Int(stored.targetFirstAyah))
        } else {
            nil
        }
        let last: MemorizationVerse? = if stored.targetLastSura > 0, stored.targetLastAyah > 0 {
            MemorizationVerse(sura: Int(stored.targetLastSura), ayah: Int(stored.targetLastAyah))
        } else {
            nil
        }
        self.init(
            id: id,
            title: stored.title ?? "",
            kind: kind,
            activity: activity,
            unit: unit,
            workloadMode: workloadMode,
            targetAmount: Int(stored.targetAmount),
            weekdayMask: Int(stored.weekdayMask),
            startDate: stored.startDate ?? createdOn,
            deadline: stored.deadline,
            startPage: max(1, Int(stored.startPage)),
            targetFirst: first,
            targetLast: last,
            presetID: stored.presetID,
            isPaused: stored.isPaused,
            createdOn: createdOn,
            modifiedOn: stored.modifiedOn ?? createdOn,
            removedOn: stored.removedOn
        )
    }

    public func write(to stored: MO_StudyGoal) {
        stored.id = id
        stored.title = title
        stored.kind = Int16(kind.rawValue)
        stored.activity = Int16(activity.rawValue)
        stored.unit = Int16(unit.rawValue)
        stored.workloadMode = Int16(workloadMode.rawValue)
        stored.targetAmount = Int32(clamping: targetAmount)
        stored.weekdayMask = Int16(clamping: weekdayMask)
        stored.startDate = startDate
        stored.deadline = deadline
        stored.startPage = Int32(clamping: max(1, startPage))
        stored.targetFirstSura = Int32(targetFirst?.sura ?? 0)
        stored.targetFirstAyah = Int32(targetFirst?.ayah ?? 0)
        stored.targetLastSura = Int32(targetLast?.sura ?? 0)
        stored.targetLastAyah = Int32(targetLast?.ayah ?? 0)
        stored.presetID = presetID
        stored.isPaused = isPaused
        stored.createdOn = createdOn
        stored.modifiedOn = modifiedOn
        stored.removedOn = removedOn
    }
}

extension ActivityLogRecord {
    /// `nil` for a record missing required fields or containing an activity from a newer version.
    public init?(_ stored: MO_ActivityLog) {
        guard let id = stored.id,
              let startedOn = stored.startedOn,
              let activity = GoalActivity(rawValue: Int(stored.activity))
        else {
            return nil
        }
        let first: MemorizationVerse? = if stored.firstSura > 0, stored.firstAyah > 0 {
            MemorizationVerse(sura: Int(stored.firstSura), ayah: Int(stored.firstAyah))
        } else {
            nil
        }
        let last: MemorizationVerse? = if stored.lastSura > 0, stored.lastAyah > 0 {
            MemorizationVerse(sura: Int(stored.lastSura), ayah: Int(stored.lastAyah))
        } else {
            nil
        }
        self.init(
            id: id,
            activity: activity,
            startedOn: startedOn,
            endedOn: stored.endedOn ?? startedOn,
            durationSeconds: Int(stored.durationSeconds),
            pagesCount: Int(stored.pagesCount),
            ayahsCount: Int(stored.ayahsCount),
            first: first,
            last: last,
            goalID: stored.goalID,
            retractedOn: stored.retractedOn
        )
    }

    public func write(to stored: MO_ActivityLog) {
        stored.id = id
        stored.activity = Int16(activity.rawValue)
        stored.startedOn = startedOn
        stored.endedOn = endedOn
        stored.durationSeconds = Int32(clamping: durationSeconds)
        stored.pagesCount = Int32(clamping: pagesCount)
        stored.ayahsCount = Int32(clamping: ayahsCount)
        stored.firstSura = Int32(first?.sura ?? 0)
        stored.firstAyah = Int32(first?.ayah ?? 0)
        stored.lastSura = Int32(last?.sura ?? 0)
        stored.lastAyah = Int32(last?.ayah ?? 0)
        stored.goalID = goalID
        stored.retractedOn = retractedOn
    }
}
