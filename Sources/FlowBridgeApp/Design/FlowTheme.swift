import FlowBridgeShared
import SwiftUI
import UIKit

/// FlowBridge design tokens.
///
/// Surface doctrine (the line between premium and web-glassmorphism kitsch):
/// `flowCard` = things you READ — opaque raised surfaces over the room,
/// never glass; `flowGlass` / `.buttonStyle(.glass)` = things you TAP.
/// Gradient lives in the Living Voice Field, chart fills, and brand glyphs
/// in empty states. No drop shadows on the room — depth comes
/// from fill luminance plus the top-lit hairline. Violet owns identity; the
/// ordered process spectrum narrates listening, understanding and delivery.
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

    /// Quiet semantic colors. Violet still owns identity; these only narrate
    /// outcomes and never become competing brand accents.
    static let success = Color.green
    static let caution = Color.orange

    /// Adaptive counterparts of the shared process spectrum. The shared
    /// values are luminous for Dynamic Island's black canvas; these variants
    /// deepen in light mode so labels keep AA-grade contrast.
    static let decoding = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.72, blue: 1.0, alpha: 1)
            : UIColor(red: 0.04, green: 0.36, blue: 0.66, alpha: 1)
    })

    static let refining = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.74, blue: 0.31, alpha: 1)
            : UIColor(red: 0.56, green: 0.31, blue: 0.0, alpha: 1)
    })

    static let delivered = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.33, green: 0.87, blue: 0.61, alpha: 1)
            : UIColor(red: 0.04, green: 0.43, blue: 0.25, alpha: 1)
    })

    static let paused = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.67, green: 0.66, blue: 1.0, alpha: 1)
            : UIColor(red: 0.28, green: 0.25, blue: 0.62, alpha: 1)
    })

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

    /// The Living Voice Field sits one luminance step above a standard
    /// reading card. It is still content, not glass: words remain crisp and
    /// Reduce Transparency can replace it with an opaque system surface.
    static let voiceSurface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.092, green: 0.086, blue: 0.145, alpha: 0.94)
            : UIColor.secondarySystemBackground.withAlphaComponent(0.92)
    })

    static let voiceSurfaceTop = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.075)
            : UIColor.white.withAlphaComponent(0.72)
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
    static let space24: CGFloat = 24
    static let space28: CGFloat = 28
    static let space32: CGFloat = 32
    static let space40: CGFloat = 40
    static let space48: CGFloat = 48

    // MARK: Radii (always `.continuous`)

    static let radiusControl: CGFloat = 12
    static let radiusRow: CGFloat = 16
    static let radiusCard: CGFloat = 20
    static let radiusField: CGFloat = 30
    static let radiusSheet: CGFloat = 28

    /// Optical inset for the 402pt iPhone 17 canvas. It remains safe on
    /// narrower Dynamic Type layouts while giving the field enough width to
    /// read as a membrane rather than a card stack.
    static let phoneInset: CGFloat = 18

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

    /// The field's compact state label. Rounded keeps it related to the
    /// timer without turning body copy into a novelty typeface.
    static func fieldLabel(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

// MARK: - Surface modifiers

extension View {
    /// Reading surface: opaque raised card over the room (solid under
    /// Reduce Transparency). Never glass — see the doctrine above.
    func flowCard(radius: CGFloat = FlowTheme.radiusCard) -> some View {
        modifier(FlowCardModifier(radius: radius))
    }

    /// The product's signature content surface. One instance owns the
    /// complete voice -> words -> action journey; never nest cards inside it.
    func flowVoiceSurface(
        tint: Color = FlowTheme.accent,
        secondaryTint: Color = FlowTheme.accentDeep,
        radius: CGFloat = FlowTheme.radiusField
    ) -> some View {
        modifier(FlowVoiceSurfaceModifier(tint: tint, secondaryTint: secondaryTint, radius: radius))
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

private struct FlowVoiceSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let tint: Color
    let secondaryTint: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        reduceTransparency
                            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                            : AnyShapeStyle(FlowTheme.voiceSurface)
                    )
                    .overlay {
                        LinearGradient(
                            colors: [FlowTheme.voiceSurfaceTop, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    }
                    .overlay {
                        LinearGradient(
                            colors: [
                                tint.opacity(reduceTransparency ? 0.055 : 0.11),
                                secondaryTint.opacity(reduceTransparency ? 0.025 : 0.065),
                                .clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FlowTheme.surfaceStroke, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Voice color story

/// The product's chromatic state machine. Color is never decorative here:
/// every take advances through this same ordered spectrum, giving the user a
/// peripheral answer to "is it listening, understanding, or done?".
enum FlowVoicePhase: String, Equatable {
    case resting
    case opening
    case listening
    case paused
    case finalizing
    case decoding
    case refining
    case delivering
    case delivered
    case attention

    static func resolve(
        state: FlowBridgeCoordinator.State,
        processingStage: FlowBridgeCoordinator.ProcessingStage?,
        pausedAt: Date?
    ) -> Self {
        switch state {
        case .idle: return .resting
        case .warming: return .opening
        case .recording: return pausedAt == nil ? .listening : .paused
        case .transcribing:
            switch processingStage {
            case .finalizingAudio: return .finalizing
            case .decodingSpeech, .none: return .decoding
            case .refiningText: return .refining
            case .delivering: return .delivering
            }
        case .ready: return .delivered
        case .failed: return .attention
        }
    }

    var primary: Color {
        switch self {
        case .resting, .opening: return FlowTheme.accent
        case .listening: return FlowTheme.recording
        case .paused: return FlowTheme.paused
        case .finalizing, .decoding: return FlowTheme.decoding
        case .refining: return FlowTheme.refining
        case .delivering, .delivered: return FlowTheme.delivered
        case .attention: return FlowTheme.caution
        }
    }

    var secondary: Color {
        switch self {
        case .resting: return FlowTheme.accentDeep
        case .opening: return FlowTheme.decoding
        case .listening: return FlowBridgeTheme.recordingHot
        case .paused: return FlowTheme.accent
        case .finalizing: return FlowTheme.accent
        case .decoding: return FlowTheme.accentDeep
        case .refining: return FlowTheme.accent
        case .delivering: return FlowTheme.decoding
        case .delivered: return Color.mint
        case .attention: return Color.red
        }
    }

    var title: String {
        switch self {
        case .resting: return "READY TO BRIDGE"
        case .opening: return "OPENING THE MIC"
        case .listening: return "LISTENING"
        case .paused: return "PAUSED"
        case .finalizing: return "SEALING THE TAKE"
        case .decoding: return "HEARING THE WORDS"
        case .refining: return "REFINING YOUR VOICE"
        case .delivering: return "MAKING IT USEFUL"
        case .delivered: return "DELIVERED"
        case .attention: return "NEEDS ATTENTION"
        }
    }

    var symbol: String {
        switch self {
        case .resting: return "waveform"
        case .opening: return "sparkles"
        case .listening: return "circle.fill"
        case .paused: return "pause.fill"
        case .finalizing: return "waveform.badge.checkmark"
        case .decoding: return "waveform.badge.magnifyingglass"
        case .refining: return "wand.and.sparkles"
        case .delivering: return "arrow.up.forward"
        case .delivered: return "checkmark"
        case .attention: return "exclamationmark"
        }
    }

    var defaultDetail: String {
        switch self {
        case .resting: return "Tap the field. Speak naturally."
        case .opening: return "Getting the on-device engine ready."
        case .listening: return "No commands to learn. Just keep talking."
        case .paused: return "Your words are safe. Resume when ready."
        case .finalizing: return "Closing the audio without losing a word."
        case .decoding: return "Your voice is becoming editable text."
        case .refining: return "Removing friction, never changing what you meant."
        case .delivering: return "Copying it and finding the most useful next step."
        case .delivered: return "Copied and ready wherever you need it."
        case .attention: return "Tap to try the bridge again."
        }
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
