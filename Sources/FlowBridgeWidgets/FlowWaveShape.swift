import SwiftUI

/// Animatable vector over N scalars: lets a `Shape`'s control points tween
/// between Live Activity content states through the system's implicit
/// animation — the mechanism that turns 2Hz data frames into continuous
/// motion. Mismatched lengths pad with zero so cross-count interpolation
/// stays defined.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableVector { AnimatableVector(values: []) }

    static func + (lhs: Self, rhs: Self) -> Self {
        merged(lhs, rhs, +)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        merged(lhs, rhs, -)
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func merged(_ lhs: Self, _ rhs: Self, _ op: (Double, Double) -> Double) -> Self {
        let count = max(lhs.values.count, rhs.values.count)
        var out = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let a = index < lhs.values.count ? lhs.values[index] : 0
            let b = index < rhs.values.count ? rhs.values[index] : 0
            out[index] = op(a, b)
        }
        return AnimatableVector(values: out)
    }
}

/// One continuous voice ribbon — not bars. The levels drive a mirrored
/// amplitude envelope around the midline, smoothed Catmull-Rom, closed and
/// filled. An 8% amplitude floor keeps a resting ribbon visible; edges
/// taper so the wave breathes without slamming the borders.
struct FlowWaveShape: Shape {
    /// Levels 0…1, oldest→newest.
    var levels: [Double]
    /// Control points after downsampling (tiny variants use fewer).
    var controlPoints = 24

    var animatableData: AnimatableVector {
        get { AnimatableVector(values: levels) }
        set { levels = newValue.values }
    }

    func path(in rect: CGRect) -> Path {
        let samples = downsampled()
        guard samples.count >= 2, rect.width > 0, rect.height > 1 else { return Path() }

        let midY = rect.midY
        let amplitude = rect.height / 2
        let count = samples.count
        let xs = (0..<count).map { rect.minX + rect.width * CGFloat($0) / CGFloat(count - 1) }

        func envelope(_ index: Int) -> CGFloat {
            let level = max(0.08, min(1, samples[index]))
            return amplitude * CGFloat(level * edgeTaper(index, count: count))
        }

        let top = (0..<count).map { CGPoint(x: xs[$0], y: midY - envelope($0)) }
        let bottom = (0..<count).map { CGPoint(x: xs[$0], y: midY + envelope($0)) }

        var path = Path()
        path.move(to: top[0])
        addSmoothSegments(&path, through: top)
        path.addLine(to: bottom[count - 1])
        addSmoothSegments(&path, through: Array(bottom.reversed()))
        path.closeSubpath()
        return path
    }

    private func downsampled() -> [Double] {
        guard controlPoints > 1, !levels.isEmpty else { return [] }
        guard levels.count > controlPoints else { return levels }
        let bucket = Double(levels.count) / Double(controlPoints)
        return (0..<controlPoints).map { index in
            let start = Int(Double(index) * bucket)
            let end = max(start + 1, min(levels.count, Int(Double(index + 1) * bucket)))
            let slice = levels[start..<end]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    private func edgeTaper(_ index: Int, count: Int) -> Double {
        let t = Double(index) / Double(count - 1)
        let edge = min(t, 1 - t) * 2 // 0 at borders, 1 at center
        return 0.35 + 0.65 * min(1, edge * 2.2)
    }

    /// Catmull-Rom through the points, emitted as cubic Béziers.
    private func addSmoothSegments(_ path: inout Path, through points: [CGPoint]) {
        guard points.count > 1 else { return }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }
}
