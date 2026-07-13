import FlowBridgeShared
import SwiftUI

/// The recording moment. A breathing glass disc that reacts to the real
/// microphone level: idle it breathes slowly, recording it grows a ring of
/// level-driven bars with ripples on speech, polishing it spins a shimmer
/// arc, ready it crystallizes with a spring pulse.
///
/// Every state has a Reduce Motion variant that keeps the information (the
/// glow still follows the voice) with the decorative motion removed. The
/// level is read per-frame from `AudioLevelMeter` inside `TimelineView` —
/// no `@Published` storm at display rate.
struct OrbView: View {
    let state: FlowBridgeCoordinator.State
    var diameter: CGFloat = 220
    /// Increment when entering `.recording` — drives the ignition kick.
    var ignitionPulse = 0
    /// Increment when entering `.ready` — drives the crystallize pulse.
    var readyPulse = 0
    /// Increment when entering `.failed` — drives the shake.
    var failPulse = 0
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var canvasSize: CGFloat { diameter + 76 }

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: timelineInterval, paused: timelinePaused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let level = CGFloat(AudioLevelMeter.shared.latestLevel)

                ZStack {
                    energyLayer(t: t, level: level)
                    disc(level: level)
                        .scaleEffect(breathScale(t: t))
                    centerSymbol
                }
                .frame(width: canvasSize, height: canvasSize)
            }
        }
        .buttonStyle(OrbPressStyle(reduceMotion: reduceMotion))
        .phaseAnimator([1.0, 1.045, 1.0], trigger: ignitionPulse) { view, scale in
            view.scaleEffect(reduceMotion ? 1.0 : scale)
        } animation: { _ in
            FlowMotion.ignition
        }
        .phaseAnimator([1.0, 1.06, 1.0], trigger: readyPulse) { view, scale in
            view.scaleEffect(reduceMotion ? 1.0 : scale)
        } animation: { _ in
            FlowMotion.celebrate
        }
        .phaseAnimator([0, -5, 5, -2, 0], trigger: failPulse) { view, offset in
            view.offset(x: reduceMotion ? 0 : offset)
        } animation: { _ in
            .snappy(duration: 0.1)
        }
        .animation(FlowMotion.state, value: stateKey)
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isBusy ? "" : "Double tap to toggle")
    }

    // MARK: - Layers

    /// Everything that moves with the voice: ring bars, ripples, shimmer arc.
    @ViewBuilder
    private func energyLayer(t: TimeInterval, level: CGFloat) -> some View {
        switch state {
        case .recording(let startedAt):
            if reduceMotion {
                // Information without motion: the halo tracks the voice.
                Circle()
                    .stroke(FlowTheme.accent.opacity(0.25 + 0.6 * level), lineWidth: 3)
                    .frame(width: diameter + 22, height: diameter + 22)
            } else {
                RecordingRing(
                    t: t,
                    level: level,
                    diameter: diameter,
                    accent: FlowTheme.accent,
                    ignitionAge: t - startedAt.timeIntervalSinceReferenceDate
                )
                // Ignition blooms outward; condensing contracts back — the
                // ring enters and leaves as the same organism.
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.82).combined(with: .opacity),
                    removal: .scale(scale: 0.85).combined(with: .opacity)
                ))
            }
        case .warming, .transcribing:
            if reduceMotion {
                ProgressView()
                    .tint(FlowTheme.accent)
                    .offset(y: -(diameter / 2 + 26))
            } else {
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        AngularGradient(
                            colors: [FlowTheme.accent.opacity(0), FlowTheme.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: diameter + 26, height: diameter + 26)
                    .rotationEffect(.radians(t * 2 * .pi * 0.9))
            }
        case .ready:
            Circle()
                .stroke(Color.green.opacity(0.4), lineWidth: 2)
                .frame(width: diameter + 22, height: diameter + 22)
        case .failed:
            Circle()
                .stroke(Color.orange.opacity(0.4), lineWidth: 2)
                .frame(width: diameter + 22, height: diameter + 22)
        case .idle:
            EmptyView()
        }
    }

    /// The glass disc itself, with a voice-reactive glow behind it.
    private func disc(level: CGFloat) -> some View {
        Circle()
            .fill(
                reduceTransparency
                    ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .background(
                Circle()
                    .fill(tint)
                    .opacity(glowOpacity(level: level))
                    .blur(radius: 26)
                    .scaleEffect(1 + 0.08 * level)
            )
            .frame(width: diameter, height: diameter)
    }

    private var centerSymbol: some View {
        Image(systemName: symbolName)
            .font(.system(size: diameter * 0.22, weight: .medium))
            .foregroundStyle(symbolTint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: readyPulse)
            .opacity(showsSymbol ? 1 : 0)
    }

    // MARK: - State mapping

    private var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    private var isBusy: Bool {
        switch state {
        case .warming, .transcribing: return true
        default: return false
        }
    }

    private var stateKey: String {
        switch state {
        case .idle: return "idle"
        case .warming: return "warming"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        case .ready: return "ready"
        case .failed: return "failed"
        }
    }

    private var symbolName: String {
        switch state {
        case .idle: return "mic.fill"
        case .warming, .recording: return "waveform"
        case .transcribing: return "waveform"
        case .ready: return "checkmark"
        case .failed: return "exclamationmark"
        }
    }

    private var showsSymbol: Bool {
        switch state {
        case .transcribing, .warming: return false // the shimmer arc narrates
        default: return true
        }
    }

    private var symbolTint: AnyShapeStyle {
        switch state {
        case .ready: return AnyShapeStyle(Color.green)
        case .failed: return AnyShapeStyle(Color.orange)
        default: return AnyShapeStyle(FlowTheme.accentGradient)
        }
    }

    private var tint: Color {
        switch state {
        case .ready: return .green
        case .failed: return .orange
        default: return FlowTheme.accent
        }
    }

    private func glowOpacity(level: CGFloat) -> Double {
        switch state {
        case .idle: return 0.16
        case .warming: return 0.22
        case .recording: return 0.2 + 0.5 * Double(level)
        case .transcribing: return 0.3
        case .ready: return 0.35
        case .failed: return 0.25
        }
    }

    /// Slow 4.2s sine breath while idle; still while working (the energy
    /// layer owns the motion there).
    private func breathScale(t: TimeInterval) -> CGFloat {
        guard case .idle = state, !reduceMotion else { return 1 }
        return 1 + 0.02 * CGFloat(sin(2 * .pi * t / 4.2))
    }

    private var timelineInterval: TimeInterval? {
        switch state {
        case .idle: return 1 / 20 // a breath needs no ProMotion
        case .recording, .warming, .transcribing: return nil
        case .ready, .failed: return 1
        }
    }

    private var timelinePaused: Bool {
        switch state {
        case .ready, .failed: return true
        case .idle: return reduceMotion
        case .warming, .recording, .transcribing: return false
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .idle: return "Ready"
        case .warming: return "Preparing"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .ready: return "Transcript copied"
        case .failed: return "Failed"
        }
    }
}

/// The 48-bar radial ring: bar length follows the live level with a touch of
/// per-bar deterministic noise, plus ripples that expand while speech flows.
private struct RecordingRing: View {
    let t: TimeInterval
    let level: CGFloat
    let diameter: CGFloat
    let accent: Color
    /// Seconds since recording began — drives the one-shot ignition
    /// shockwave, deterministically (replays correct on re-render).
    var ignitionAge: TimeInterval = .infinity

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let innerRadius = diameter / 2 + 9
            let barCount = 48
            let slice = Int(t * 3)

            // Ignition shockwave: one ring expanding +52pt over the first
            // 700ms of the session.
            if ignitionAge >= 0, ignitionAge < 0.7 {
                let p = ignitionAge / 0.7
                let eased = p * p * (3 - 2 * p)
                let radius = innerRadius + CGFloat(eased) * 52
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(
                    Circle().path(in: rect),
                    with: .color(accent.opacity((1 - eased) * 0.5)),
                    style: StrokeStyle(lineWidth: 2)
                )
            }

            for index in 0..<barCount {
                let angle = (2 * .pi / CGFloat(barCount)) * CGFloat(index) - .pi / 2
                let jitter = Self.noise(index: index, slice: slice)
                let length = 5 + level * 24 + jitter * 7 * level
                let from = CGPoint(
                    x: center.x + cos(angle) * innerRadius,
                    y: center.y + sin(angle) * innerRadius
                )
                let to = CGPoint(
                    x: center.x + cos(angle) * (innerRadius + length),
                    y: center.y + sin(angle) * (innerRadius + length)
                )
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(
                    path,
                    with: .color(accent.opacity(0.45 + 0.55 * Double(level))),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
            }

            // Two staggered ripples, purely time-driven, weighted by the
            // level so silence stays calm.
            guard level > 0.06 else { return }
            let cycle: TimeInterval = 1.4
            for k in 0..<2 {
                let phase = ((t / cycle) + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                let radius = innerRadius + 16 + CGFloat(phase) * 38
                let opacity = (1 - phase) * 0.32 * Double(level)
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(
                    Circle().path(in: rect),
                    with: .color(accent.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 1.5)
                )
            }
        }
    }

    /// Deterministic per-bar wiggle: no Math.random, stable across frames
    /// within a time slice.
    private static func noise(index: Int, slice: Int) -> CGFloat {
        let hash = (index &* 73_856_093) ^ (slice &* 19_349_663)
        return CGFloat(abs(hash % 1000)) / 1000
    }
}

/// Press style tuned for the Orb: a deeper squeeze than standard controls.
private struct OrbPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(.snappy(duration: 0.22), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: configuration.isPressed) { oldValue, newValue in
                !oldValue && newValue
            }
    }
}
