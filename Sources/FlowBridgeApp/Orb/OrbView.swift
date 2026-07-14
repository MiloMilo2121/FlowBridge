import FlowBridgeShared
import SwiftUI

/// FlowBridge's signature object: one horizontal membrane that survives the
/// entire session. It invites speech, reacts to real microphone energy,
/// condenses while the engine works, and settles into a quiet delivered rail.
/// The parent transcript surface never swaps it for another hero.
struct LivingVoiceField: View {
    let state: FlowBridgeCoordinator.State
    var elapsed: TimeInterval?
    var pausedAt: Date?
    var statusMessage: String?
    var processingStage: FlowBridgeCoordinator.ProcessingStage?
    var ignitionPulse = 0
    var readyPulse = 0
    var failPulse = 0
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button {
            guard isInteractive else { return }
            action()
        } label: {
            TimelineView(.animation(minimumInterval: timelineInterval, paused: timelinePaused)) { timeline in
                VStack(alignment: .leading, spacing: FlowTheme.space12) {
                    header

                    VoiceMembrane(
                        state: state,
                        phase: voicePhase,
                        time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate,
                        level: CGFloat(AudioLevelMeter.shared.latestLevel),
                        reduceMotion: reduceMotion
                    )
                    .frame(height: membraneHeight)
                    .accessibilityHidden(true)

                    HStack(alignment: .firstTextBaseline, spacing: FlowTheme.space8) {
                        Text(detailText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: FlowTheme.space8)
                        if isInteractive {
                            Label("Speak", systemImage: "arrow.up.right")
                                .labelStyle(.iconOnly)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(FlowTheme.accent)
                                .frame(width: 34, height: 34)
                                .flowGlass(interactive: true)
                        }
                    }
                }
                .padding(FlowTheme.space20)
            }
        }
        .buttonStyle(LivingFieldPressStyle(enabled: isInteractive, reduceMotion: reduceMotion))
        .disabled(!isInteractive)
        .phaseAnimator([0, -5, 5, -2, 0], trigger: failPulse) { view, offset in
            view.offset(x: reduceMotion ? 0 : offset)
        } animation: { _ in
            .snappy(duration: 0.1)
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: ignitionPulse)
        .sensoryFeedback(.success, trigger: readyPulse)
        .sensoryFeedback(.error, trigger: failPulse)
        .animation(FlowMotion.fieldMorph, value: stateKey)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(detailText)
        .accessibilityHint(isInteractive ? "Double tap to start a dictation" : "")
    }

    private var header: some View {
        HStack(spacing: FlowTheme.space8) {
            Image(systemName: stateSymbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(stateTint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: readyPulse)

            Text(stateTitle)
                .font(FlowTheme.fieldLabel())
                .tracking(1.15)
                .foregroundStyle(stateTint)
                .contentTransition(.opacity)

            Spacer(minLength: FlowTheme.space8)

            if let elapsed {
                Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                    .font(FlowTheme.numeric(15))
                    .contentTransition(.numericText(value: elapsed))
                    .foregroundStyle(pausedAt == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(voicePhase.primary))
            } else {
                Text("VOICE → TEXT")
                    .font(FlowTheme.fieldLabel(10))
                    .tracking(0.9)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var membraneHeight: CGFloat {
        switch state {
        case .idle: return 68
        case .warming: return 58
        case .recording: return pausedAt == nil ? 82 : 48
        case .transcribing: return 52
        case .ready: return 32
        case .failed: return 42
        }
    }

    private var isInteractive: Bool {
        switch state {
        case .idle, .ready, .failed: return true
        case .warming, .recording, .transcribing: return false
        }
    }

    private var stateTitle: String {
        voicePhase.title
    }

    private var stateSymbol: String {
        voicePhase.symbol
    }

    private var stateTint: AnyShapeStyle {
        AnyShapeStyle(voicePhase.primary)
    }

    private var detailText: String {
        if let statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        return voicePhase.defaultDetail
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle, .ready, .failed: return "Start dictation"
        case .warming: return "Preparing dictation"
        case .recording where pausedAt != nil: return "Dictation paused"
        case .recording: return "Dictation recording"
        case .transcribing: return "Transcribing dictation"
        }
    }

    private var stateKey: String {
        voicePhase.rawValue
    }

    private var voicePhase: FlowVoicePhase {
        .resolve(state: state, processingStage: processingStage, pausedAt: pausedAt)
    }

    private var timelineInterval: TimeInterval? {
        guard !reduceMotion else { return 1 }
        switch state {
        case .recording: return 1 / 30
        case .warming, .transcribing: return 1 / 24
        case .idle, .ready, .failed: return 1 / 15
        }
    }

    private var timelinePaused: Bool {
        reduceMotion || stateKey == "ready" || stateKey == "failed" || stateKey == "paused"
    }
}

/// A filled ribbon rather than equalizer bars. Its outer contour follows the
/// real level, so the product has one recognizable silhouette in the app,
/// widgets and Dynamic Island.
private struct VoiceMembrane: View {
    let state: FlowBridgeCoordinator.State
    let phase: FlowVoicePhase
    let time: TimeInterval
    let level: CGFloat
    let reduceMotion: Bool

    var body: some View {
        Canvas { context, size in
            let ribbon = membranePath(in: size)

            var glow = context
            glow.addFilter(.blur(radius: 13))
            glow.opacity = glowOpacity
            glow.fill(ribbon, with: fillShading(in: size))

            context.fill(ribbon, with: fillShading(in: size))
            context.stroke(
                ribbon,
                with: .color(edgeColor.opacity(0.72)),
                style: StrokeStyle(lineWidth: 1, lineJoin: .round)
            )

            var spine = Path()
            spine.move(to: CGPoint(x: 0, y: size.height / 2))
            spine.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                spine,
                with: .linearGradient(
                    Gradient(colors: [.clear, edgeColor.opacity(0.42), .clear]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 1)
            )
        }
        .animation(FlowMotion.fieldMorph, value: phaseKey)
    }

    private func membranePath(in size: CGSize) -> Path {
        let samples = 44
        let centerY = size.height / 2
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []

        for index in 0...samples {
            let progress = CGFloat(index) / CGFloat(samples)
            let x = size.width * progress
            let envelope = pow(sin(.pi * progress), 0.58)
            let energy = amplitude(at: progress) * envelope
            let drift = reduceMotion ? 0 : CGFloat(sin(time * 2.1 + Double(progress) * 9.4)) * energy * 0.13
            top.append(CGPoint(x: x, y: centerY - energy + drift))
            bottom.append(CGPoint(x: x, y: centerY + energy + drift))
        }

        var path = Path()
        if let first = top.first {
            path.move(to: first)
            for point in top.dropFirst() { path.addLine(to: point) }
            for point in bottom.reversed() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }

    private func amplitude(at progress: CGFloat) -> CGFloat {
        switch state {
        case .idle:
            return 4.5 + (reduceMotion ? 0 : 2.5 * CGFloat(sin(time * 1.45 + Double(progress) * 7)))
        case .warming:
            let focus = 1 - abs(progress - 0.5) * 1.5
            return 5 + max(0, focus) * (8 + 4 * CGFloat(sin(time * 3.2)))
        case .recording:
            let live = max(0.06, min(1, level))
            let harmonic = 0.58 + 0.42 * abs(CGFloat(sin(time * 5.2 + Double(progress) * 14)))
            return 5 + live * 28 * harmonic
        case .transcribing:
            let inward = 1 - abs(progress - 0.5) * 2
            let pulse = reduceMotion ? 0.65 : 0.65 + 0.35 * CGFloat(sin(time * 3.6))
            return 4 + max(0, inward) * 12 * pulse
        case .ready:
            return 2.6
        case .failed:
            return 4 + 2 * abs(CGFloat(sin(Double(progress) * 18)))
        }
    }

    private func fillShading(in size: CGSize) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(colors: fillColors),
            startPoint: CGPoint(x: 0, y: size.height / 2),
            endPoint: CGPoint(x: size.width, y: size.height / 2)
        )
    }

    private var fillColors: [Color] {
        [phase.secondary.opacity(0.26), phase.primary, phase.secondary.opacity(0.72)]
    }

    private var edgeColor: Color {
        phase.primary
    }

    private var glowOpacity: Double {
        switch state {
        case .idle: return 0.28
        case .warming: return 0.38
        case .recording: return 0.38 + 0.38 * Double(level)
        case .transcribing: return 0.42
        case .ready: return 0.28
        case .failed: return 0.25
        }
    }

    private var phaseKey: String {
        phase.rawValue
    }
}

private struct LivingFieldPressStyle: ButtonStyle {
    let enabled: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && enabled && !reduceMotion ? 0.985 : 1)
            .brightness(configuration.isPressed && enabled ? 0.025 : 0)
            .animation(FlowMotion.interactive, value: configuration.isPressed)
    }
}
