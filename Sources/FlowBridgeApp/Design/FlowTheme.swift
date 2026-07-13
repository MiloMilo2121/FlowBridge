import FlowBridgeShared
import SwiftUI
import UIKit

/// FlowBridge design tokens.
///
/// Surface doctrine (the line between premium and web-glassmorphism kitsch):
/// `flowCard` = things you READ — opaque raised surfaces over the room,
/// never glass; `flowGlass` / `.buttonStyle(.glass)` = things you TAP.
/// Gradient lives in exactly three homes: the orb glyph, chart fills, and
/// brand glyphs in empty states. No drop shadows on the room — depth comes
/// from fill luminance plus the top-lit hairline. The violet accent means
/// identity and "listening", nothing else.
///
/// Serif (New York italic) is rationed to "things you said": the transcript
/// panel label, empty states, one Stats flavor line, onboarding titles.
///
/// Sound design (deliberately deferred): two earcons max — "pluck" ~80ms on
/// start, "resolve" ~120ms on ready — played `.ambient`, off by default.
enum FlowTheme {
    // MARK: Color — brand

    static let accent = FlowBridgeTheme.flowViolet
    static let accentDeep = FlowBridgeTheme.flowVioletDeep
    static let recording = FlowBridgeTheme.recordingWarm

    static let accentGradient = FlowBridgeTheme.accentGradient
    static let recordingGradient = FlowBridgeTheme.recordingGradient

    // MARK: Color — the room (scheme-aware; dark pair promoted from the
    // recap card, which was the room all along)

    static let roomTop = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.063, green: 0.059, blue: 0.102, alpha: 1) // #100F1A
            : UIColor.systemBackground
    })

    static let roomBottom = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.043, green: 0.043, blue: 0.071, alpha: 1) // #0B0B12
            : UIColor.secondarySystemBackground
    })

    // MARK: Color — surfaces (scheme-aware raised fills)

    static let surfaceRaised = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.055)
            : UIColor.black.withAlphaComponent(0.04)
    })

    private static let strokeStart = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.13)
            : UIColor.black.withAlphaComponent(0.08)
    })

    private static let strokeEnd = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.04)
            : UIColor.black.withAlphaComponent(0.03)
    })

    /// Top-lit hairline: the one border in the app.
    static var surfaceStroke: LinearGradient {
        LinearGradient(
            colors: [strokeStart, strokeEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

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
    static let radiusRow: CGFloat = 16
    static let radiusCard: CGFloat = 20
    static let radiusSheet: CGFloat = 28

    // MARK: Typography

    /// Transcript-grade display text; ≥20pt system renders SF Pro Display.
    /// Pair with `@ScaledMetric(relativeTo: .title2)` at the call site.
    static func hero(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    /// New York italic — "things you said" flavor moments only.
    static func serifFlavor(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif).italic()
    }

    /// Numbers that move — timers, tickers, stats. Rounded digits that never
    /// wobble in width.
    static func numeric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// MARK: - Surface modifiers

extension View {
    /// Reading surface: opaque raised card over the room (solid under
    /// Reduce Transparency). Never glass — see the doctrine above.
    func flowCard(radius: CGFloat = FlowTheme.radiusCard) -> some View {
        modifier(FlowCardModifier(radius: radius))
    }

    /// Control-layer glass for interactive clusters and pills. RT-safe.
    func flowGlass(interactive: Bool = false) -> some View {
        modifier(FlowGlassModifier(interactive: interactive))
    }

    /// Tracked-uppercase structural label (section headers).
    func flowEyebrow() -> some View {
        font(.caption.weight(.semibold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
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
                    : AnyShapeStyle(FlowTheme.surfaceRaised),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FlowTheme.surfaceStroke, lineWidth: 1)
            )
    }
}

private struct FlowGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let interactive: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                Color(uiColor: .secondarySystemBackground),
                in: Capsule(style: .continuous)
            )
        } else {
            content.glassEffect(.regular.interactive(interactive), in: Capsule(style: .continuous))
        }
    }
}
