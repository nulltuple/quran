//
//  MoreMenuWordByWord.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import Foundation
import Localization
import NoorUI
import QuranText
import SwiftUI

struct MoreMenuWordByWord: View {
    let language: WordByWordLanguage

    var body: some View {
        NoorListItem(
            title: .text(l("menu.word_by_word")),
            subtitle: .init(text: .text(language.localizedName), location: .trailing),
            accessory: .disclosureIndicator
        )
        .padding()
    }
}

extension WordByWordLanguage {
    /// The language's name in the reader's language, followed by its own name when they differ.
    var localizedName: String {
        guard let code = languageCode else {
            return l("menu.word_by_word.off")
        }
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        let nativeName = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        return name == nativeName ? name : "\(name) (\(nativeName))"
    }

    private var languageCode: String? {
        switch self {
        case .off: nil
        case .english: "en"
        case .bengali: "bn"
        }
    }
}

#Preview {
    VStack {
        MoreMenuWordByWord(language: .off)
        Divider()
        MoreMenuWordByWord(language: .bengali)
    }
}
