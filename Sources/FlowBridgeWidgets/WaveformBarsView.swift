import FlowBridgeShared
import SwiftUI

/// The island's waveform: capsules whose heights are real mic levels
/// (`ContentState.levels`). Plain capsule frames — not `Canvas` — so the
/// system spring-interpolates between content states; that interpolation is
/// what makes the 2Hz update cadence read as continuous motion.
struct WaveformBarsView: View {
    /// Levels 0…100, oldest→newest.
    let levels: [UInt8]
    var barCount = 24
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2.5
    var maxHeight: CGFloat = 22
    var tint = AnyShapeStyle(FlowBridgeTheme.recordingGradient)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(luminanceReduced ? AnyShapeStyle(FlowBridgeTheme.flowVioletDeep.opacity(0.7)) : tint)
                    .frame(width: barWidth, height: height(at: index) * (luminanceReduced ? 0.8 : 1))
            }
        }
        .frame(height: maxHeight)
        // 0.55 spans the whole 500ms tick gap: motion without dead stops.
        .animation(reduceMotion || luminanceReduced ? .linear(duration: 0.2) : .smooth(duration: 0.55), value: levels)
    }

    /// Renders the newest `barCount` values so small variants (compact,
    /// minimal) show the "now" while the wide strip shows the 2s history.
    /// A 14% floor keeps resting bars visible as dots.
    private func height(at index: Int) -> CGFloat {
        let floor = maxHeight * 0.14
        let tail = Array(levels.suffix(barCount))
        let offset = index - (barCount - tail.count)
        guard offset >= 0, offset < tail.count else { return floor }
        return max(floor, maxHeight * CGFloat(tail[offset]) / 100)
    }
}
