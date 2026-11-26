//
//  Translation+UI.swift
//  Quran
//
//  Created by Afifi, Mohamed on 10/29/21.
//  Copyright © 2021 Quran.com. All rights reserved.
//

import NoorUI
import QuranText
import SwiftUI

extension Translation {
    public var textFont: Font {
        languageCode == "ar" ? .arabicTafseer() : .body
    }

    public var footnoteFont: Font {
        languageCode == "ar" ? .arabicTafseerFootnote() : .footnote
    }

    public var characterDirection: Locale.LanguageDirection {
        Locale.characterDirection(forLanguage: languageCode)
    }
}
