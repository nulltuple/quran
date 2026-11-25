//
//  MoreMenuWordByWordTransliteration.swift
//
//
//  Created by Claude Code on 2026-11-24.
//

import Localization
import SwiftUI

/// Shows each word's transliteration under it in the translation view's word-by-word meanings.
struct MoreMenuWordByWordTransliteration: View {
    @Binding var enabled: Bool

    var body: some View {
        Toggle(l("translation.text-type.transliteration"), isOn: $enabled)
            .padding()
    }
}

#Preview {
    MoreMenuWordByWordTransliteration(enabled: .constant(true))
}
