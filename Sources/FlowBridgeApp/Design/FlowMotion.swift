import SwiftUI

/// Motion tokens: springs only, never fixed-duration easing curves
/// (KILLER_FEATURES §2.5). State changes use `.state`, direct-manipulation
/// feedback uses `.interactive`, payoff moments use `.celebrate`.
enum FlowMotion {
    static let state: Animation = .smooth(duration: 0.35)
    static let interactive: Animation = .snappy(duration: 0.28, extraBounce: 0.06)
    static let celebrate: Animation = .bouncy(duration: 0.5, extraBounce: 0.15)
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
