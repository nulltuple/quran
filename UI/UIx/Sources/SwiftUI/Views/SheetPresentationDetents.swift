//
//  SheetPresentationDetents.swift
//
//
//  Created by Mohamed Afifi on 2024-01-20.
//

import SwiftUI

public enum SheetPresentationDetent {
    case large
    case medium
    case height(CGFloat)

    var presentationDetent: PresentationDetent {
        switch self {
        case .large: .large
        case .medium: .medium
        case .height(let height): .height(height)
        }
    }
}

public enum SheetPresentationAdaptation {
    case none

    var presentationAdaptation: PresentationAdaptation {
        switch self {
        case .none: .none
        }
    }
}

private struct SheetPresentationBackground<S: ShapeStyle>: ViewModifier {
    let style: S

    func body(content: Content) -> some View {
        content
            .presentationBackground(style)
    }
}

private struct SheetPresentationDetents: ViewModifier {
    let detents: [SheetPresentationDetent]

    func body(content: Content) -> some View {
        content
            .presentationDetents(presentationDetents)
    }

    private var presentationDetents: Set<PresentationDetent> {
        let presentationDetents = detents.map { detent in
            detent.presentationDetent
        }
        return Set(presentationDetents)
    }
}

private struct SheetPresentationAdaptationModifier: ViewModifier {
    let presentationAdaptation: SheetPresentationAdaptation

    func body(content: Content) -> some View {
        content
            .presentationCompactAdaptation(presentationAdaptation.presentationAdaptation)
    }
}

extension View {
    public func sheetPresentationDetents(_ detents: [SheetPresentationDetent]) -> some View {
        modifier(SheetPresentationDetents(detents: detents))
    }

    public func sheetPresentationCompactAdaptation(_ adaptation: SheetPresentationAdaptation) -> some View {
        modifier(SheetPresentationAdaptationModifier(presentationAdaptation: adaptation))
    }

    public func sheetPresentationBackground(_ style: some ShapeStyle) -> some View {
        modifier(SheetPresentationBackground(style: style))
    }
}
