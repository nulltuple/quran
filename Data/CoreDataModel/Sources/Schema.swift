//
//  Schema.swift
//
//
//  Created by Mohamed Afifi on 2023-05-28.
//

import CoreDataPersistence

public enum Schema {
    public enum Note: String, CoreDataKey {
        case color, createdOn, modifiedOn, note, verses
    }

    public enum Verse: String, CoreDataKey {
        case ayah, sura, note
    }

    public enum PageBookmark: String, CoreDataKey {
        case color, createdOn, modifiedOn, mushafID, page
    }

    public enum LastPage: String, CoreDataKey {
        case createdOn, modifiedOn, mushafID, page
    }

    public enum Collection: String, CoreDataKey {
        case createdOn, id, isDefault, modifiedOn, name, verses
    }

    public enum CollectionVerse: String, CoreDataKey {
        case ayah, collection, createdOn, id, sura
    }

    public enum PracticeSession: String, CoreDataKey {
        case endedOn, firstAyah, firstSura, id, lastAyah, lastSura, startedOn
    }

    public enum RecallEvidence: String, CoreDataKey {
        case assistance, ayah, id, outcome, provenance, recordedOn, retractedOn, sessionID, sura, word
    }

    public enum MemorizedRange: String, CoreDataKey {
        case declaredOn, firstAyah, firstSura, id, lastAyah, lastSura, removedOn
    }

    public enum Passage: String, CoreDataKey {
        case createdOn, firstAyah, firstSura, id, lastAyah, lastSura, modifiedOn, removedOn, snoozedUntil
    }
}
