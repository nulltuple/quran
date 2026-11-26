import FSRS
import LearningEngine
import LearningModel
import XCTest

final class MasteryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func test_noEvidenceIsNotAssessedAndUnscorableIsUncertainNotWrong() {
        var evidence = SkillEvidence()
        XCTAssertEqual(evidence.state(), .notAssessed)
        evidence.record(.unscorable, at: start)
        evidence.record(.unscorable, at: start)
        XCTAssertEqual(evidence.state(), .uncertain)
        XCTAssertEqual(evidence.scoredAttempts, 0)
        XCTAssertEqual(evidence.successRate, 0.5, "unscorable attempts never lower the estimate")
    }

    func test_fourCorrectAnswersMasterASkillAndOneMistakeDoesNot() {
        var evidence = SkillEvidence()
        for _ in 0 ..< 3 {
            evidence.record(.correct, at: start)
        }
        XCTAssertEqual(evidence.state(), .learning)
        evidence.record(.correct, at: start)
        XCTAssertEqual(evidence.state(), .mastered)

        var mixed = SkillEvidence()
        [AttemptOutcome.correct, .incorrect, .correct, .correct].forEach { mixed.record($0, at: start) }
        XCTAssertEqual(mixed.state(), .learning)
    }

    func test_readingAnExplanationMastersIt() {
        var evidence = SkillEvidence()
        evidence.record(.correct, at: start)
        XCTAssertEqual(evidence.state(for: SkillID("orientation.rtl")!), .mastered)
        XCTAssertEqual(evidence.state(for: SkillID("letter.recognize.ب")!), .learning)
    }

    func test_masteryFadesWithoutPractice() {
        var evidence = SkillEvidence()
        for _ in 0 ..< 4 {
            evidence.record(.correct, at: start)
        }
        XCTAssertEqual(evidence.state(), .mastered)
        evidence.record(.correct, at: start.addingTimeInterval(120 * 24 * 3600))
        XCTAssertEqual(evidence.state(), .learning, "four half-lives later the old evidence counts for little")
    }
}

final class SkillGraphTests: XCTestCase {
    private func skill(_ raw: String) -> SkillID {
        SkillID(raw)!
    }

    private lazy var curriculum = Curriculum(
        units: [LearningUnit(id: "U1", title: "One")],
        lessons: [
            Lesson(id: "u1.l01", unit: "U1", ordinal: 1, title: "A", teaches: [skill("letter.recognize.a"), skill("letter.sound.a")], requires: []),
            Lesson(id: "u1.l02", unit: "U1", ordinal: 2, title: "B", teaches: [skill("letter.recognize.b")], requires: [skill("letter.recognize.a")]),
        ],
        prerequisites: [skill("letter.sound.a"): [skill("letter.recognize.a")], skill("letter.recognize.b"): [skill("letter.recognize.a")]]
    )

    func test_unlockingFollowsPrerequisites() {
        let graph = SkillGraph(curriculum: curriculum)
        XCTAssertEqual(graph.unlockedUnmastered(mastery: [:]), [skill("letter.recognize.a")])
        XCTAssertEqual(graph.nextLesson(mastery: [:])?.id, "u1.l01")
        let mastery: [SkillID: MasteryState] = [skill("letter.recognize.a"): .mastered, skill("letter.sound.a"): .mastered]
        XCTAssertEqual(graph.unlockedUnmastered(mastery: mastery), [skill("letter.recognize.b")])
        XCTAssertEqual(graph.nextLesson(mastery: mastery)?.id, "u1.l02")
        XCTAssertTrue(graph.isComplete(curriculum.lessons[0], mastery: mastery))
    }

    func test_plannerPutsDueReviewsFirstThenTheNextLessonAndIsDeterministic() {
        let planner = SessionPlanner(graph: SkillGraph(curriculum: curriculum))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var practiced = SkillEvidence()
        practiced.record(.incorrect, at: now)
        let plan = planner.plan(
            profile: .child,
            evidence: [skill("letter.recognize.a"): practiced],
            dueReviews: [skill("letter.sound.a"): now.addingTimeInterval(-60), skill("letter.recognize.b"): now.addingTimeInterval(3600)],
            now: now
        )
        // u1.l01's skills were planned as review and weak skill; the lesson adds its second round.
        XCTAssertEqual(plan.map(\.skill), [skill("letter.sound.a"), skill("letter.recognize.a"),
                                           skill("letter.recognize.a"), skill("letter.sound.a")])
        XCTAssertEqual(plan.map(\.reason), [.dueReview, .weakSkill, .newLesson, .newLesson])
        XCTAssertEqual(plan, planner.plan(
            profile: .child,
            evidence: [skill("letter.recognize.a"): practiced],
            dueReviews: [skill("letter.sound.a"): now.addingTimeInterval(-60),
                         skill("letter.recognize.b"): now.addingTimeInterval(3600)],
            now: now
        ))
        XCTAssertLessThanOrEqual(plan.count, SessionPlanner.itemCap(for: .child))
    }

    func test_aFreshLearnerStartsWithTheFirstLesson() {
        let planner = SessionPlanner(graph: SkillGraph(curriculum: curriculum))
        let plan = planner.plan(profile: .adult, evidence: [:], dueReviews: [:], now: Date())
        XCTAssertEqual(plan.map(\.skill), [skill("letter.recognize.a"), skill("letter.sound.a"),
                                           skill("letter.recognize.a"), skill("letter.sound.a")], "two rounds")
        XCTAssertTrue(plan.allSatisfy { $0.reason == .newLesson })
    }
}

final class ReviewSchedulerTests: XCTestCase {
    func test_correctPushesTheDueDateOutAndIncorrectBringsItBack() throws {
        let scheduler = ReviewScheduler()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var card = scheduler.newCard(now: now)
        for day in 0 ..< 4 {
            card = try scheduler.review(card, outcome: .correct, at: max(card.due, now.addingTimeInterval(Double(day) * 86400)))
        }
        let goodDue = card.due
        XCTAssertGreaterThan(goodDue.timeIntervalSince(now), 2 * 86400)
        let lapsed = try scheduler.review(card, outcome: .incorrect, at: goodDue)
        XCTAssertLessThan(lapsed.due.timeIntervalSince(goodDue), 86400)
        XCTAssertEqual(lapsed.lapses, card.lapses + 1)
        XCTAssertEqual(try scheduler.review(card, outcome: .unscorable, at: goodDue), card)
    }

    func test_schedulingIsDeterministic() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try ReviewScheduler().review(ReviewScheduler().newCard(now: now), outcome: .correct, at: now)
        let b = try ReviewScheduler().review(ReviewScheduler().newCard(now: now), outcome: .correct, at: now)
        XCTAssertEqual(a, b)
    }

    func test_onlyRecallSkillsAreScheduled() {
        XCTAssertTrue(ReviewScheduler.isScheduled(SkillID("letter.recognize.ب")!))
        XCTAssertFalse(ReviewScheduler.isScheduled(SkillID("orientation.rtl")!))
    }
}
