import GRDB
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

    func test_meaningLanguageDefaultsToEnglishAndPersistsPerProfile() async throws {
        let store = try ProfileStore(directory: directory)
        let amina = try await store.create(name: "Amina", presentation: .child, now: now)
        let omar = try await store.create(name: "Omar", presentation: .adult, now: now.addingTimeInterval(1))
        XCTAssertEqual(amina.meaningLanguage, .english)
        try await store.setMeaningLanguage(.bengali, for: amina.id)
        let profiles = try await ProfileStore(directory: directory).profiles()
        XCTAssertEqual(profiles.map(\.meaningLanguage), [.bengali, .english])
        XCTAssertEqual(profiles.map(\.id), [amina.id, omar.id])
    }

    /// A profiles file written before L7 (migration "v1 profiles" only) keeps its profiles and
    /// active profile, which read meanings in English.
    func test_aVersionOneProfilesFileMigratesToEnglishMeanings() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let v1 = try DatabaseQueue(path: directory.appendingPathComponent("profiles.sqlite").path)
        try await v1.write { db in
            try db.execute(sql: """
            CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
            INSERT INTO grdb_migrations VALUES('v1 profiles');
            CREATE TABLE profile(id TEXT PRIMARY KEY, name TEXT NOT NULL, presentation TEXT NOT NULL, created_at DATETIME NOT NULL);
            CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
            try db.execute(
                sql: "INSERT INTO profile VALUES(?, 'Amina', 'child', '2027-01-15 08:00:00.000'); INSERT INTO meta VALUES('active_profile', ?)",
                arguments: [id.uuidString, id.uuidString]
            )
        }
        try v1.close()
        let store = try ProfileStore(directory: directory)
        let active = try await store.activeProfile()
        XCTAssertEqual(active?.id, id)
        XCTAssertEqual(active?.name, "Amina")
        XCTAssertEqual(active?.presentation, .child)
        XCTAssertEqual(active?.meaningLanguage, .english)
    }

    func test_placementsAreStoredPerUnitAndKeepTheLatestDate() async throws {
        let store = try ProfileStore(directory: directory)
        let profile = try await store.create(name: "Reader", presentation: .adult, now: now)
        let progress = try store.progress(for: profile.id)
        try await progress.recordPlacement(units: ["U1", "U2"], at: now)
        try await progress.recordPlacement(units: ["U2"], at: now.addingTimeInterval(60))
        let placements = try await store.progress(for: profile.id).placements()
        XCTAssertEqual(placements, ["U1": now, "U2": now.addingTimeInterval(60)])
    }

    /// A progress file written by L2/L3 (migration "v1 progress" only) opens, keeps its evidence
    /// and log, and gains the placement table.
    func test_aVersionOneProgressFileMigratesWithoutLosingData() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("v1.sqlite")
        let v1 = try DatabaseQueue(path: url.path)
        try await v1.write { db in
            try db.execute(sql: """
            CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
            INSERT INTO grdb_migrations VALUES('v1 progress');
            CREATE TABLE evidence(skill TEXT PRIMARY KEY, successes DOUBLE NOT NULL, scored_attempts DOUBLE NOT NULL,
                unscorable_attempts INTEGER NOT NULL, last_attempt DATETIME);
            CREATE TABLE review_card(skill TEXT PRIMARY KEY, card TEXT NOT NULL, due DATETIME NOT NULL);
            CREATE TABLE attempt(id INTEGER PRIMARY KEY AUTOINCREMENT, skill TEXT NOT NULL,
                outcome TEXT NOT NULL CHECK(outcome IN ('correct', 'incorrect', 'unscorable')), at DATETIME NOT NULL);
            INSERT INTO evidence VALUES('letter.recognize.ب', 2, 3, 1, '2027-01-15 08:00:00.000');
            INSERT INTO attempt(skill, outcome, at) VALUES('letter.recognize.ب', 'correct', '2027-01-15 08:00:00.000');
            """)
        }
        try v1.close()
        let progress = try ProgressStore(fileURL: url)
        let evidence = try await progress.evidence()
        XCTAssertEqual(evidence[ba]?.successes, 2)
        XCTAssertEqual(evidence[ba]?.scoredAttempts, 3)
        XCTAssertEqual(evidence[ba]?.unscorableAttempts, 1)
        let attempts = try await progress.attemptCount()
        XCTAssertEqual(attempts, 1)
        let placements = try await progress.placements()
        XCTAssertEqual(placements, [:])
        try await progress.recordPlacement(units: ["U2"], at: now)
        let recorded = try await progress.placements()
        XCTAssertEqual(recorded, ["U2": now])
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
