import LearningContent
import LearningModel
import LearningPersistence
import XCTest
@testable import LearningUI

/// Performance budgets (milestone L7) for the loads a learner waits on: starting a practice
/// session (the whole compiled curriculum, letters, words, recitations, lemmas and tajweed
/// examples become one generator) and opening the Quran tab and a reader. Measured on the
/// iPhone 18 Pro Max simulator (2026-11-26): 37 ms, 3 ms and 1 ms. Budgets leave 10x or more of
/// headroom, so they catch a regression (an unindexed query, a load per word), not noise; a
/// device is slower (UNVERIFIED on hardware). Trail: 2026-11-26-arabican-l7-polish.md.
@MainActor
final class PerformanceBudgetTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("arabican-perf-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func seconds(_ block: () async throws -> Void) async rethrows -> Double {
        let clock = ContinuousClock()
        let elapsed = try await clock.measure { try await block() }
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    func test_practiceSessionStartsWithinBudget() async throws {
        let store = try ProfileStore(directory: directory)
        let profile = try await store.create(name: "Perf", presentation: .adult)
        let viewModel = try PracticeViewModel(profile: profile, content: LearningContentStore(), progress: store.progress(for: profile.id))
        let elapsed = await seconds { await viewModel.start() }
        print("[budget] practice start: \(elapsed) s")
        guard case .exercise = viewModel.state else { return XCTFail("\(viewModel.state)") }
        XCTAssertLessThan(elapsed, 0.5)
    }

    func test_quranTabAndReaderLoadWithinBudget() async throws {
        let store = try ProfileStore(directory: directory)
        let profile = try await store.create(name: "Perf", presentation: .adult)
        let bridge = try BridgeViewModel(content: LearningContentStore(), progress: store.progress(for: profile.id), meaningLanguage: .english)
        let list = await seconds { await bridge.load() }
        guard case .loaded(let suras) = bridge.state, let fatihah = suras.first else { return XCTFail("\(bridge.state)") }
        let reader = bridge.reader(for: fatihah)
        let open = await seconds { await reader.load() }
        print("[budget] bridge list: \(list) s, reader: \(open) s")
        XCTAssertLessThan(list, 0.25)
        XCTAssertLessThan(open, 0.1)
    }
}
