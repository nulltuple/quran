//
//  TracingCanvas.swift
//  ArabicLearning (Arabican app)
//

import ExerciseKit
import LearningModel
import Localization
import NoorUI
import SwiftUI

/// A square canvas that shows a letter's stroke guide (faint paths, numbered starts, dots) and
/// records the learner's strokes as canvas fractions. `TraceChecker` grades them.
struct TracingCanvas: View {
    // MARK: Internal

    let guide: [GuideStroke]
    let accessibilityName: String
    /// Nil while tracing; after grading, whether the trace passed.
    let passed: Bool?
    let submit: ([[CanvasPoint]]) -> Void

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                canvas(side: side)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: maxCanvasSide)
            .environment(\.layoutDirection, .leftToRight)
            if passed == nil {
                HStack {
                    Button(String(localized: "trace.clear", bundle: .module)) {
                        strokes = []
                        current = []
                    }
                    .disabled(strokes.isEmpty)
                    Button(String(localized: "practice.check", bundle: .module)) { submit(strokes) }
                        .buttonStyle(.borderedProminent)
                        .disabled(strokes.isEmpty)
                }
            }
        }
    }

    // MARK: Private

    @ScaledMetric private var maxCanvasSide = 320.0
    @ScaledMetric private var markerSize = 22.0
    @State private var strokes: [[CanvasPoint]] = []
    @State private var current: [CanvasPoint] = []

    private func canvas(side: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground))
            ForEach(Array(guide.enumerated()), id: \.offset) { index, stroke in
                guideMark(stroke, number: index + 1, side: side)
            }
            ForEach(Array((strokes + [current]).enumerated()), id: \.offset) { _, points in
                path(points, side: side)
                    .stroke(inkColor, style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round, lineJoin: .round))
            }
        }
        .contentShape(Rectangle())
        .gesture(passed == nil ? drawing(side: side) : nil)
        .accessibilityElement()
        .accessibilityLabel(String(format: String(localized: "trace.canvas", bundle: .module), accessibilityName))
    }

    private var inkColor: Color {
        switch passed {
        case .some(true): .green
        case .some(false): .secondary
        case nil: .accentColor
        }
    }

    @ViewBuilder
    private func guideMark(_ stroke: GuideStroke, number: Int, side: Double) -> some View {
        if let start = stroke.points.first {
            if stroke.kind == .path {
                path(stroke.points, side: side)
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: side * 0.06, lineCap: .round, lineJoin: .round))
            }
            Text(NumberFormatter.shared.format(number))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: markerSize, height: markerSize)
                .background(Circle().fill(stroke.kind == .dot ? Color.orange : Color.accentColor))
                .position(x: start.x * side, y: start.y * side)
                .accessibilityHidden(true)
        }
    }

    private func path(_ points: [CanvasPoint], side: Double) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: first.x * side, y: first.y * side))
            if points.count == 1 {
                path.addLine(to: CGPoint(x: first.x * side + 0.5, y: first.y * side))
            }
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * side, y: point.y * side))
            }
        }
    }

    private func drawing(side: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = min(1, max(0, value.location.x / side))
                let y = min(1, max(0, value.location.y / side))
                current.append(CanvasPoint(x: x, y: y))
            }
            .onEnded { _ in
                if !current.isEmpty {
                    strokes.append(current)
                }
                current = []
            }
    }
}
