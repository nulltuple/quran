//
//  TraceChecker.swift
//  ArabicLearning (Arabican app)
//

import LearningModel

/// Checks a traced letter against its stroke guide, deterministically: no handwriting
/// recognition (spec 03 §2). Paths must be drawn in the guide's order and direction and stay
/// close to it; dots may be tapped in any order.
public struct TraceChecker: Sendable {
    // MARK: Lifecycle

    /// `tolerance` is the largest distance, as a fraction of the canvas side, a drawn point may be
    /// from the guide (and a guide point from the drawing).
    public init(tolerance: Double = 0.15) {
        self.tolerance = tolerance
    }

    // MARK: Public

    public enum Result: Hashable, Sendable {
        case passed
        /// The drawing has a different number of paths or taps than the guide.
        case wrongStrokeCount
        /// Path `index` (from 0, among the guide's strokes) leaves the guide or misses part of it.
        case offPath(index: Int)
        /// Path `index` was drawn from its end to its start.
        case wrongDirection(index: Int)
        /// No tap landed on dot `index`.
        case missedDot(index: Int)
    }

    /// A drawn stroke shorter than this (a fraction of the canvas side) counts as a tap.
    public static let tapLength = 0.06

    public let tolerance: Double

    public func check(_ drawn: [[CanvasPoint]], against guide: [GuideStroke]) -> Result {
        let drawnPaths = drawn.filter { !$0.isEmpty && Self.length($0) >= Self.tapLength }
        let taps = drawn.filter { !$0.isEmpty && Self.length($0) < Self.tapLength }.map { $0[0] }
        let guidePaths = guide.enumerated().filter { $0.element.kind == .path }
        let guideDots = guide.enumerated().filter { $0.element.kind == .dot }
        guard drawnPaths.count == guidePaths.count, taps.count == guideDots.count else {
            return .wrongStrokeCount
        }
        for ((index, stroke), path) in zip(guidePaths, drawnPaths) {
            if let problem = compare(path, stroke.points, index: index) {
                return problem
            }
        }
        var unused = taps
        for (index, dot) in guideDots {
            guard let point = dot.points.first,
                  let match = unused.indices.min(by: { unused[$0].distance(to: point) < unused[$1].distance(to: point) }),
                  unused[match].distance(to: point) <= tolerance
            else {
                return .missedDot(index: index)
            }
            unused.remove(at: match)
        }
        return .passed
    }

    // MARK: Internal

    static func length(_ points: [CanvasPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Distance from `point` to the nearest point of the polyline `line`.
    static func distance(from point: CanvasPoint, to line: [CanvasPoint]) -> Double {
        guard let first = line.first else { return .infinity }
        guard line.count > 1 else { return point.distance(to: first) }
        return zip(line, line.dropFirst()).map { segmentDistance(point, $0.0, $0.1) }.min() ?? .infinity
    }

    /// `count` points spread evenly along `line` by length, both ends included.
    static func resample(_ line: [CanvasPoint], count: Int) -> [CanvasPoint] {
        let total = length(line)
        guard line.count > 1, total > 0, count > 1 else { return line }
        var result: [CanvasPoint] = []
        var segment = 0
        var walked = 0.0
        for step in 0 ..< count {
            let target = total * Double(step) / Double(count - 1)
            while segment < line.count - 2, walked + line[segment].distance(to: line[segment + 1]) < target {
                walked += line[segment].distance(to: line[segment + 1])
                segment += 1
            }
            let a = line[segment]
            let b = line[segment + 1]
            let span = a.distance(to: b)
            let t = span > 0 ? min(1, max(0, (target - walked) / span)) : 0
            result.append(CanvasPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return result
    }

    // MARK: Private

    private static let samples = 32

    private static func segmentDistance(_ p: CanvasPoint, _ a: CanvasPoint, _ b: CanvasPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return p.distance(to: CanvasPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    private func compare(_ path: [CanvasPoint], _ guide: [CanvasPoint], index: Int) -> Result? {
        let guideSamples = Self.resample(guide, count: Self.samples)
        let drawnSamples = Self.resample(path, count: Self.samples)
        let covers = guideSamples.allSatisfy { Self.distance(from: $0, to: path) <= tolerance }
        let stays = drawnSamples.allSatisfy { Self.distance(from: $0, to: guide) <= tolerance }
        guard covers, stays else {
            return .offPath(index: index)
        }
        // A closed shape (start near end) has no direction to check from its ends.
        guard let start = guide.first, let end = guide.last, let drawnStart = path.first,
              start.distance(to: end) > tolerance
        else {
            return nil
        }
        return drawnStart.distance(to: start) <= drawnStart.distance(to: end) ? nil : .wrongDirection(index: index)
    }
}
