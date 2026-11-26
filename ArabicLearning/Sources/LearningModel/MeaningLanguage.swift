//
//  MeaningLanguage.swift
//  ArabicLearning (Arabican app)
//

/// The language a profile reads meanings in: word meanings in the reader, and the options of
/// meaning exercises. The compiled content has English and Bengali for every bridge word and
/// vocabulary lemma (QUL word by word, QuranicWords and `glosses.toml`). The app's interface
/// stays English.
public enum MeaningLanguage: String, CaseIterable, Sendable, Codable {
    case english
    case bengali

    // MARK: Public

    public func text(_ meaning: WordMeaning) -> String {
        switch self {
        case .english: meaning.english
        case .bengali: meaning.bengali
        }
    }

    public func gloss(_ lemma: Lemma) -> String {
        switch self {
        case .english: lemma.english
        case .bengali: lemma.bengali
        }
    }
}
