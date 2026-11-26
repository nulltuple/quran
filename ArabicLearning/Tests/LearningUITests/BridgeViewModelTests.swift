import LearningContent
import LearningEngine
import LearningModel
import LearningPersistence
import XCTest
@testable import LearningUI

@MainActor
final class BridgeViewModelTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("arabican-bridge-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func progress() async throws -> ProgressStore {
        let store = try ProfileStore(directory: directory)
        let profile = try await store.create(name: "Reader", presentation: .adult, now: now)
        return try store.progress(for: profile.id)
    }

    func test_loadsTheBridgeSurasInLessonOrder() async throws {
        let viewModel = try await BridgeViewModel(content: LearningContentStore(), progress: progress(), meaningLanguage: .english)
        await viewModel.load()
        guard case .loaded(let suras) = viewModel.state else {
            return XCTFail("expected loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(suras.map(\.sura), [1, 112, 113, 114, 108, 103, 110, 111])
    }

    func test_reportsFailureForAMissingDatabase() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).sqlite")
        let viewModel = try await BridgeViewModel(content: LearningContentStore(fileURL: missing), progress: progress(), meaningLanguage: .english)
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .failed)
    }

    /// Mastering a lemma's meaning in Practice makes the reader show its words in Arabic; the
    /// meanings come in the profile's language.
    func test_readerShowsWordsWhoseLemmasAreMasteredInArabicAndMeaningsInTheProfileLanguage() async throws {
        let content = LearningContentStore()
        let progress = try await progress()
        let viewModel = BridgeViewModel(content: content, progress: progress, meaningLanguage: .bengali)
        await viewModel.load()
        guard case .loaded(let suras) = viewModel.state, let ikhlas = suras.first(where: { $0.sura == 112 }) else {
            return XCTFail("expected sura 112")
        }
        let reader = viewModel.reader(for: ikhlas)
        await reader.load()
        XCTAssertEqual(reader.knownWords, [])
        let first = try XCTUnwrap(ikhlas.words.first)
        XCTAssertEqual(reader.meaning(first), first.meaning.bengali)

        // قُلۡ (112:1:1, "Say") is one segment whose lemma is the verb قال.
        let segments = try await content.wordSegments(sura: 112)
        let lemmas = try XCTUnwrap(segments[first.word.word]).compactMap(\.lemma)
        XCTAssertFalse(lemmas.isEmpty)
        for lemma in lemmas {
            for _ in 0 ..< 4 {
                try await progress.record(.correct, for: ProgressiveSubstitution.skill(for: lemma)!, at: now, scheduler: ReviewScheduler())
            }
        }
        reader.close()
        await reader.load()
        XCTAssertTrue(reader.knownWords.contains(first.word.word))
        XCTAssertTrue(reader.knownWords.allSatisfy { word in ikhlas.words.contains { $0.word.word == word } })
    }

    /// Adjacent known words form one Arabic run, so they keep their right-to-left order.
    func test_meaningLineJoinsAdjacentKnownWordsIntoOneArabicRun() async throws {
        let content = LearningContentStore()
        let progress = try await progress()
        let suras = try await content.bridgeSuras()
        let fatihah = try XCTUnwrap(suras.first { $0.sura == 1 })
        let ayah2 = fatihah.ayahs[1]
        let segments = try await content.wordSegments(sura: 1)
        // 1:2 is الحمد لله رب العالمين: master the lemmas of words 2 and 3 only.
        for word in ayah2.words[1 ... 2] {
            for lemma in try XCTUnwrap(segments[word.word.word]).compactMap(\.lemma) {
                for _ in 0 ..< 4 {
                    try await progress.record(.correct, for: ProgressiveSubstitution.skill(for: lemma)!, at: now, scheduler: ReviewScheduler())
                }
            }
        }
        let reader = BridgeReaderViewModel(sura: fatihah, content: content, progress: progress, meaningLanguage: .english)
        await reader.load()
        let known = ayah2.words.filter { reader.knownWords.contains($0.word.word) }.map(\.word.text.text)
        XCTAssertEqual(known, ayah2.words[1 ... 2].map(\.word.text.text), "only the lemmas of words 2 and 3 are mastered")
        XCTAssertEqual(reader.meaningLine(ayah2), [
            .meaning(ayah2.words[0].meaning.english),
            .arabic(ayah2.words[1].word.text.text + " " + ayah2.words[2].word.text.text),
            .meaning(ayah2.words[3].meaning.english),
        ])
    }
}
