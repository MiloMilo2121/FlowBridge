import FlowBridgeShared
import SwiftUI

/// FlowBridge design tokens.
///
/// Discipline (KILLER_FEATURES §2): the violet accent means identity and
/// "listening", nothing else; success/danger stay system-semantic; content
/// sits on materials, glass belongs to interactive controls only. Views
/// honor Reduce Transparency by swapping materials for solid surfaces and
/// size type with `@ScaledMetric` (transcript hero: 22pt relative to
/// `.title2`).
///
/// Sound design (deliberately deferred): two earcons max — "pluck" ~80ms on
/// start, "resolve" ~120ms on ready — played `.ambient` so the silent switch
/// is respected, off by default. Haptics stay the primary eyes-free channel;
/// the audio session is in `.record` exactly when a start chime would play.
enum FlowTheme {
    // MARK: Color

    static let accent = FlowBridgeTheme.flowViolet
    static let accentDeep = FlowBridgeTheme.flowVioletDeep
    static let recording = FlowBridgeTheme.recordingWarm

    static let accentGradient = FlowBridgeTheme.accentGradient
    static let recordingGradient = FlowBridgeTheme.recordingGradient

    // MARK: Spacing

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space28: CGFloat = 28
    static let space40: CGFloat = 40

    // MARK: Radii (always `.continuous`)

    static let radiusControl: CGFloat = 12
    static let radiusCard: CGFloat = 20
    static let radiusSheet: CGFloat = 28

    // MARK: Typography

    /// Numbers that move — timers, tickers, stats. Rounded digits that never
    /// wobble in width.
    static func numeric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension View {
    /// Standard card surface: material (or solid under Reduce Transparency)
    /// on a continuous rounded rectangle.
    func flowCard(radius: CGFloat = FlowTheme.radiusCard) -> some View {
        modifier(FlowCardModifier(radius: radius))
    }
}

private struct FlowCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                    : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }
}
