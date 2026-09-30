import FlowBridgeShared
import SwiftUI
import UIKit

/// App-side design system: scales, motion, and the reusable surfaces from
/// the flowbridge-design-system. Colors come from `FlowPalette` (shared);
/// this file owns what only the app renders.
enum FlowTheme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let page: CGFloat = 20
        static let stack: CGFloat = 18
        static let cardPad: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 28
        static let group: CGFloat = 24
        static let field: CGFloat = 16
        static let chip: CGFloat = 12
        static let cta: CGFloat = 18
    }

    enum Motion {
        /// The set's one curve: decisive spring-out, no bounce (0.32,0.72,0,1).
        static let fast = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.16)
        static let base = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)
        static let slow = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.42)
        static let pressScale: CGFloat = 0.97
    }

    /// Layered glass shadow (soft ambient + tight contact), adaptive.
    static let shadowAmbient = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.42)
            : UIColor(red: 18 / 255, green: 12 / 255, blue: 45 / 255, alpha: 0.10)
    })
    static let shadowContact = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.25)
            : UIColor(red: 18 / 255, green: 12 / 255, blue: 45 / 255, alpha: 0.04)
    })
}

// MARK: - Glass card

/// The card recipe from the design tokens: translucent tinted fill over
/// blur, hairline border, top inner highlight, layered soft shadow.
/// Falls back to an opaque card under Reduce Transparency.
private struct GlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .background {
                if reduceTransparency {
                    shape.fill(FlowPalette.surfaceCard)
                } else {
                    shape
                        .fill(FlowPalette.glassBackground)
                        .background(.ultraThinMaterial, in: shape)
                }
            }
            .overlay {
                shape.strokeBorder(FlowPalette.glassBorder, lineWidth: 1)
            }
            .overlay {
                // inset 0 1px 0 highlight: a border that fades below the top edge.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [FlowPalette.glassHighlight, .clear],
                        startPoint: .top, endPoint: .center
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: FlowTheme.shadowContact, radius: 1, y: 1)
            .shadow(color: FlowTheme.shadowAmbient, radius: 20, y: 16)
    }
}

extension View {
    func glassCard(radius: CGFloat = FlowTheme.Radius.group, padding: CGFloat = FlowTheme.Spacing.cardPad) -> some View {
        modifier(GlassCardModifier(radius: radius, padding: padding))
    }
}

// MARK: - Aurora background

/// The aurora page background: three fixed radial pools of the state hues
/// over the page base. Deliberately static — the motion budget belongs to
/// the mesh waveform, not the wallpaper.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            FlowPalette.surfacePage
            RadialGradient(
                colors: [FlowPalette.violet500.opacity(dark ? 0.26 : 0.15), .clear],
                center: UnitPoint(x: 0.12, y: -0.08),
                startRadius: 0, endRadius: 640
            )
            RadialGradient(
                colors: [FlowPalette.orange400.opacity(dark ? 0.12 : 0.09), .clear],
                center: UnitPoint(x: 1.08, y: 0.12),
                startRadius: 0, endRadius: 560
            )
            RadialGradient(
                colors: [FlowPalette.violet400.opacity(dark ? 0.20 : 0.13), .clear],
                center: UnitPoint(x: 0.5, y: 1.18),
                startRadius: 0, endRadius: 540
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Caps label (eyebrow)

/// Micro caps label with the waveform gesture: "READY TO BRIDGE" / "LISTENING".
struct CapsLabel: View {
    enum Tone {
        case accent, attention, privacy, stop
    }

    let text: String
    var tone: Tone = .accent
    var glyph: LineaVivaIcon.Glyph? = .waveform

    var body: some View {
        HStack(spacing: 5) {
            if let glyph {
                LineaVivaIcon(glyph)
                    .frame(width: 12, height: 12)
            }
            Text(text.uppercased())
                .font(.footnote.weight(.bold))
                .kerning(1.4)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .accessibilityLabel(text)
    }

    private var color: Color {
        switch tone {
        case .accent: return FlowPalette.accent
        case .attention: return FlowPalette.stateLive
        case .privacy: return FlowPalette.statePrivate
        case .stop: return FlowPalette.stateStop
        }
    }
}

// MARK: - Privacy dot

/// The iOS mic indicator, made brand: a small green dot with a soft glow.
struct PrivacyDot: View {
    var cloud = false
    var body: some View {
        Circle()
            .fill(cloud ? FlowPalette.stateLive : FlowPalette.statePrivate)
            .frame(width: 7, height: 7)
            .shadow(color: (cloud ? FlowPalette.stateLive : FlowPalette.statePrivate).opacity(0.7), radius: 4)
            .accessibilityLabel(cloud ? "Cloud transcription" : "Local transcription")
    }
}

// MARK: - CTA button style

/// The primary action: 60pt, state-toned vertical gradient, top highlight,
/// hue glow, press scale 0.97 on the set's curve.
struct FlowCTAButtonStyle: ButtonStyle {
    enum Tone {
        case accent, stop, working
    }

    var tone: Tone = .accent

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: FlowTheme.Radius.cta, style: .continuous)
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(gradient, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear],
                        startPoint: .top, endPoint: .center
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: glow.opacity(0.30), radius: 8, y: 6)
            .shadow(color: glow.opacity(0.30), radius: 22, y: 18)
            .opacity(tone == .working ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? FlowTheme.Motion.pressScale : 1)
            .animation(FlowTheme.Motion.fast, value: configuration.isPressed)
    }

    private var gradient: LinearGradient {
        switch tone {
        case .accent, .working: return FlowPalette.gradientAccent
        case .stop: return FlowPalette.gradientStop
        }
    }

    private var glow: Color {
        switch tone {
        case .accent, .working: return FlowPalette.violet500
        case .stop: return FlowPalette.red500
        }
    }
}

// MARK: - Settings row

/// A Form row in the Linea Viva language: 40pt tinted chip, 16pt title,
/// secondary subtitle (design turn 1c).
struct ChipRow: View {
    let glyph: LineaVivaIcon.Glyph
    var tone: LineaVivaChip.Tone = .violet
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: FlowTheme.Spacing.m) {
            LineaVivaChip(glyph, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FlowPalette.textBody)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(FlowPalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
