import SwiftUI

/// Motion tokens: springs only, never fixed-duration easing curves
/// (KILLER_FEATURES §2.5). State changes use `.state`, direct-manipulation
/// feedback uses `.interactive`, payoff moments use `.celebrate`.
enum FlowMotion {
    static let state: Animation = .smooth(duration: 0.35)
    static let interactive: Animation = .snappy(duration: 0.28, extraBounce: 0.06)
    static let celebrate: Animation = .bouncy(duration: 0.5, extraBounce: 0.15)
    /// Press → listening bloom.
    static let ignition: Animation = .snappy(duration: 0.38, extraBounce: 0.12)
    /// The raw→polished text morph.
    static let reveal: Animation = .smooth(duration: 0.55)
    /// Room intensity swells.
    static let drift: Animation = .smooth(duration: 1.6)
    /// Ticker/stat roll.
    static let tick: Animation = .smooth(duration: 0.8)
    /// One geometry from invitation -> listening -> transcript rail.
    /// Slightly slower than a button response so the eye can follow it.
    static let fieldMorph: Animation = .spring(duration: 0.48, bounce: 0.06)
    /// Controls fuse and separate inside one GlassEffectContainer.
    static let glassMorph: Animation = .spring(duration: 0.34, bounce: 0.08)
    /// A transcript has weight; it settles instead of bouncing.
    static let settle: Animation = .spring(duration: 0.42, bounce: 0.02)
}

/// One clock for the stop→reveal→tick choreography: every element of the
/// payoff sequence reads its cue from here, so the beats can never drift
/// apart.
enum RevealBeat {
    /// Verbatim continuity hold before the polished morph.
    static let rawHold: Duration = .milliseconds(350)
    /// Ticker roll stagger after the reveal lands.
    static let tickerDelay: Double = 0.45
    /// The once-a-day "day N" whisper dwell.
    static let whisperDwell: Duration = .seconds(2.8)
}

/// Press feedback for tappable controls: subtle scale, subtle fade, one soft
/// haptic on the press-down edge.
struct FlowPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: configuration.isPressed) { oldValue, newValue in
                !oldValue && newValue
            }
    }
}
