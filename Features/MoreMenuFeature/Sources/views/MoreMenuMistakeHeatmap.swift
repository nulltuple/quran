//
//  MoreMenuMistakeHeatmap.swift
//
//
//  Created by Antigravity on 2026-11-27.
//

import Localization
import SwiftUI

struct MoreMenuMistakeHeatmap: View {
    @Binding var enabled: Bool

    var body: some View {
        Toggle(l("menu.mistake_heatmap"), isOn: $enabled)
            .padding()
    }
}

#Preview {
    MoreMenuMistakeHeatmap(enabled: .constant(true))
}
