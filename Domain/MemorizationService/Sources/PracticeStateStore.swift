//
//  PracticeStateStore.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Foundation
import MemorizationPersistence
import QuranKit

/// A practice session not yet saved: where it stands and the ayahs graded so far, so it can resume
/// after the app is killed (roadmap H2, slice b).
public struct PracticeDraft: Hashable, Sendable {
    // MARK: Lifecycle

    public init(passage: Passage, order: PracticeOrder, position: Int, startedOn: Date, recalls: [VerseRecall]) {
        self.passage = passage
        self.order = order
        self.position = position
        self.startedOn = startedOn
        self.recalls = recalls
    }

    // MARK: Public

    public let passage: Passage
    public let order: PracticeOrder
    /// The index of the ayah being recited among the plan's ayahs, every step's in turn.
    public let position: Int
    public let startedOn: Date
    public let recalls: [VerseRecall]
}

/// The practice choices and the unsaved session, in user defaults. The draft is device-local and
/// transient: it is not part of backups, and a saved session clears it.
public final class PracticeStateStore: @unchecked Sendable {
    // MARK: Lifecycle

    public init(userDefaults: UserDefaults = .standard, quran: Quran = .hafsMadani1405) {
        self.userDefaults = userDefaults
        self.quran = quran
    }

    // MARK: Public

    public var cueLevel: PracticeCueLevel {
        get { userDefaults.string(forKey: Keys.cueLevel).flatMap(PracticeCueLevel.init(rawValue:)) ?? .none }
        set { userDefaults.set(newValue.rawValue, forKey: Keys.cueLevel) }
    }

    public var order: PracticeOrder {
        get { userDefaults.string(forKey: Keys.order).flatMap(PracticeOrder.init(rawValue:)) ?? .straight }
        set { userDefaults.set(newValue.rawValue, forKey: Keys.order) }
    }

    /// The unsaved session, or `nil` when there is none or it cannot be read (a newer format).
    public var draft: PracticeDraft? {
        guard let data = userDefaults.data(forKey: Keys.draft),
              let stored = try? JSONDecoder().decode(StoredDraft.self, from: data),
              StoredDraft.supportedVersions.contains(stored.version)
        else {
            return nil
        }
        return stored.draft(quran: quran)
    }

    public func saveDraft(_ draft: PracticeDraft) throws {
        let data = try JSONEncoder().encode(StoredDraft(draft))
        userDefaults.set(data, forKey: Keys.draft)
    }

    public func clearDraft() {
        userDefaults.removeObject(forKey: Keys.draft)
    }

    // MARK: Private

    private enum Keys {
        static let cueLevel = "hifzPractice.cueLevel"
        static let order = "hifzPractice.order"
        static let draft = "hifzPractice.draft"
    }

    private let userDefaults: UserDefaults
    private let quran: Quran
}

/// The draft's stored form. Its field names are a persisted format: change them only with a new version.
private struct StoredDraft: Codable {
    // MARK: Lifecycle

    init(_ draft: PracticeDraft) {
        version = Self.currentVersion
        first = MemorizationVerse(draft.passage.first)
        last = MemorizationVerse(draft.passage.last)
        order = draft.order
        position = draft.position
        startedOn = draft.startedOn
        recalls = draft.recalls.map {
            Recall(
                verse: MemorizationVerse($0.verse),
                outcome: $0.outcome,
                assistance: $0.assistance,
                mistakenWords: $0.mistakenWords,
                provenance: $0.provenance
            )
        }
    }

    // MARK: Internal

    struct Recall: Codable {
        let verse: MemorizationVerse
        let outcome: RecallOutcome
        let assistance: Int
        let mistakenWords: [Int]
        let provenance: EvidenceProvenance?
    }

    static let currentVersion = 2
    static let supportedVersions = 1 ... currentVersion

    let version: Int
    let first: MemorizationVerse
    let last: MemorizationVerse
    let order: PracticeOrder
    let position: Int
    let startedOn: Date
    let recalls: [Recall]

    func draft(quran: Quran) -> PracticeDraft? {
        guard let first = first.ayah(in: quran), let last = last.ayah(in: quran), position >= 0 else {
            return nil
        }
        let recalls = recalls.compactMap { recall in
            recall.verse.ayah(in: quran).map {
                VerseRecall(
                    verse: $0,
                    outcome: recall.outcome,
                    assistance: recall.assistance,
                    mistakenWords: recall.mistakenWords,
                    provenance: recall.provenance ?? .manual
                )
            }
        }
        return PracticeDraft(passage: Passage(first, last), order: order, position: position, startedOn: startedOn, recalls: recalls)
    }
}

private extension MemorizationVerse {
    init(_ ayah: AyahNumber) {
        self.init(sura: ayah.sura.suraNumber, ayah: ayah.ayah)
    }

    func ayah(in quran: Quran) -> AyahNumber? {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)
    }
}
