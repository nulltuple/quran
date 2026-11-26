import LearningEngine
import LearningModel
import LearningPersistence
import XCTest

final class LearningPersistenceTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let ba = SkillID("letter.recognize.ب")!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("arabican-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_createdProfileBecomesActiveAndSurvivesReopening() async throws {
        let store = try ProfileStore(directory: directory)
        let amina = try await store.create(name: "Amina", presentation: .child, now: now)
        let reopened = try ProfileStore(directory: directory)
        let profiles = try await reopened.profiles()
        XCTAssertEqual(profiles, [amina])
        let active = try await reopened.activeProfile()
        XCTAssertEqual(active, amina)
    }

    func test_profilesKeepSeparateProgress() async throws {
        let store = try ProfileStore(directory: directory)
        let child = try await store.create(name: "Child", presentation: .child, now: now)
        let adult = try await store.create(name: "Adult", presentation: .adult, now: now)
        try await store.progress(for: child.id).record(.correct, for: ba, at: now, scheduler: ReviewScheduler())
        let childEvidence = try await store.progress(for: child.id).evidence()
        let adultEvidence = try await store.progress(for: adult.id).evidence()
        XCTAssertEqual(childEvidence[ba]?.scoredAttempts, 1)
        XCTAssertNil(adultEvidence[ba])
        XCTAssertNotEqual(store.progressURL(for: child.id), store.progressURL(for: adult.id))
    }

    /// "Progress survives kill/relaunch" (spec 03 L2): a new store on the same file sees every attempt.
    func test_progressSurvivesReopeningTheFile() async throws {
        let store = try ProfileStore(directory: directory)
        let profile = try await store.create(name: "Me", presentation: .adult, now: now)
        let progress = try store.progress(for: profile.id)
        for offset in 0 ..< 4 {
            try await progress.record(.correct, for: ba, at: now.addingTimeInterval(Double(offset)), scheduler: ReviewScheduler())
        }
        try await progress.record(.unscorable, for: SkillID("orientation.rtl")!, at: now, scheduler: ReviewScheduler())

        let reopened = try ProfileStore(directory: directory).progress(for: profile.id)
        let evidence = try await reopened.evidence()
        XCTAssertEqual(evidence[ba]?.state(), .mastered)
        XCTAssertEqual(evidence[SkillID("orientation.rtl")!]?.state(), .uncertain)
        let attempts = try await reopened.attemptCount()
        XCTAssertEqual(attempts, 5)
        let due = try await reopened.dueDates()
        XCTAssertNotNil(due[ba], "recall skills get an FSRS card")
        XCTAssertNil(due[SkillID("orientation.rtl")!], "orientation is not scheduled")
    }

    func test_deletingAProfileRemovesItsProgressFile() async throws {
        let store = try ProfileStore(directory: directory)
        let profile = try await store.create(name: "Gone", presentation: .adult, now: now)
        try await store.progress(for: profile.id).record(.correct, for: ba, at: now, scheduler: ReviewScheduler())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.progressURL(for: profile.id).path))
        try await store.delete(profile.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.progressURL(for: profile.id).path))
        let profiles = try await store.profiles()
        XCTAssertEqual(profiles, [])
        let active = try await store.activeProfile()
        XCTAssertNil(active)
    }
}
