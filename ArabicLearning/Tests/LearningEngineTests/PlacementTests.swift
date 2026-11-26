import LearningEngine
import LearningModel
import XCTest

final class PlacementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func skill(_ raw: String) -> SkillID {
        SkillID(raw)!
    }

    /// U1 (explanations, no check), U2 and U3, each ending with its check lesson.
    private lazy var curriculum = Curriculum(
        units: [LearningUnit(id: "U1", title: "One"), LearningUnit(id: "U2", title: "Two"), LearningUnit(id: "U3", title: "Three")],
        lessons: [
            Lesson(id: "u1.l01", unit: "U1", ordinal: 1, title: "A", teaches: [skill("orientation.rtl")], requires: []),
            Lesson(id: "u2.l01", unit: "U2", ordinal: 2, title: "B", teaches: [skill("letter.recognize.a")], requires: [skill("orientation.rtl")]),
            Lesson(id: "u2.check", unit: "U2", ordinal: 3, title: "Check", teaches: [skill("check.U2")], requires: [skill("letter.recognize.a")]),
            Lesson(id: "u3.l01", unit: "U3", ordinal: 4, title: "C", teaches: [skill("letter.form.a.final")], requires: [skill("check.U2")]),
            Lesson(id: "u3.check", unit: "U3", ordinal: 5, title: "Check", teaches: [skill("check.U3")], requires: [skill("letter.form.a.final")]),
        ],
        prerequisites: [
            skill("letter.recognize.a"): [skill("orientation.rtl")],
            skill("check.U2"): [skill("letter.recognize.a")],
            skill("letter.form.a.final"): [skill("check.U2")],
            skill("check.U3"): [skill("letter.form.a.final")],
        ]
    )

    func test_startsWithTheFirstCheckAndPassingPlacesTheUnitsBeforeIt() {
        var test = PlacementTest(curriculum: curriculum)
        XCTAssertEqual(test.current, skill("check.U2"))
        [AttemptOutcome.correct, .incorrect, .correct, .correct].forEach { test.record($0) }
        XCTAssertEqual(test.placedUnits, ["U1", "U2"])
        XCTAssertEqual(test.current, skill("check.U3"))
    }

    func test_threeRightAnswersPassEarlyAndTwoMissesFailEarly() {
        var test = PlacementTest(curriculum: curriculum)
        (0 ..< 3).forEach { _ in test.record(.correct) }
        XCTAssertEqual(test.current, skill("check.U3"), "no fourth question once three are right")
        test.record(.incorrect)
        test.record(.unscorable)
        XCTAssertTrue(test.isFinished, "a skip is not right; three right answers are now impossible")
        XCTAssertEqual(test.placedUnits, ["U1", "U2"])
    }

    func test_passingEveryCheckPlacesEveryUnit() {
        var test = PlacementTest(curriculum: curriculum)
        while !test.isFinished {
            test.record(.correct)
        }
        XCTAssertEqual(test.placedUnits, ["U1", "U2", "U3"])
    }

    func test_placedSkillsCountAsMasteredUntilPracticedAgain() {
        var before = SkillEvidence()
        before.record(.incorrect, at: now.addingTimeInterval(-60))
        var after = SkillEvidence()
        after.record(.incorrect, at: now.addingTimeInterval(60))
        let mastery = PlacementMastery.mastery(
            evidence: [skill("letter.recognize.a"): before, skill("check.U2"): after],
            placements: ["U1": now, "U2": now],
            curriculum: curriculum
        )
        XCTAssertEqual(mastery[skill("orientation.rtl")], .mastered)
        XCTAssertEqual(mastery[skill("letter.recognize.a")], .mastered, "evidence from before the placement is superseded")
        XCTAssertEqual(mastery[skill("check.U2")], .learning, "practice after the placement decides")
        XCTAssertNil(mastery[skill("letter.form.a.final")], "U3 was not placed")
    }

    func test_plannerSkipsPlacedUnitsAndAsksACheckFiveTimes() {
        let planner = SessionPlanner(graph: SkillGraph(curriculum: curriculum))
        let placed = planner.plan(profile: .adult, evidence: [:], dueReviews: [:], placements: ["U1": now, "U2": now], now: now)
        XCTAssertEqual(placed.map(\.skill), [skill("letter.form.a.final"), skill("letter.form.a.final")])

        var mastered = SkillEvidence()
        (0 ..< 4).forEach { _ in mastered.record(.correct, at: now) }
        let atCheck = planner.plan(
            profile: .adult,
            evidence: [skill("letter.form.a.final"): mastered],
            dueReviews: [:],
            placements: ["U1": now, "U2": now],
            now: now
        )
        XCTAssertEqual(atCheck.map(\.skill), Array(repeating: skill("check.U3"), count: SessionPlanner.checkItems))
    }
}
