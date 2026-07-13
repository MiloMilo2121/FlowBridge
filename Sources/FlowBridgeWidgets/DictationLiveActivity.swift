import ActivityKit
import FlowBridgeShared
import SwiftUI
import WidgetKit

/// The dictation session in the Dynamic Island and on the Lock Screen.
///
/// The waveform is real: `ContentState.levels` carries quantized mic RMS
/// history, pushed by the app's island tick (4Hz burst at start, then 2Hz,
/// change-gated so silence costs nothing). Between updates the island stays
/// alive on budget-free primitives: `Text(timerInterval:)` and repeating
/// `symbolEffect`s. Phase narrative: red live wave → violet frozen wave
/// while polishing → green check with "N words · Ns" → auto-dismiss.
struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(state: context.state, isStale: context.isStale)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: context.state)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    TranscriptHero(state: context.state, isStale: context.isStale, lineLimit: 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: context.state, isStale: context.isStale)
                        .padding(.top, 4)
                }
            } compactLeading: {
                CompactLeading(state: context.state, isStale: context.isStale)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                MinimalGlyph(state: context.state)
            }
            .keylineTint(FlowBridgeTheme.flowViolet)
        }
        // One implementation, four surfaces: the small family relays the
        // activity to the Apple Watch Smart Stack and CarPlay for free.
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - The wave

/// One continuous voice ribbon (owner's call: "non le solite lineette").
/// Falls back to the battle-tested bars under Reduce Motion and on the
/// always-on display.
private struct LiveWave: View {
    let levels: [UInt8]
    var controlPoints = 24
    var height: CGFloat = 26
    var tint = AnyShapeStyle(FlowBridgeTheme.recordingGradient)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        if reduceMotion || luminanceReduced {
            WaveformBarsView(
                levels: levels,
                barCount: min(controlPoints, 24),
                barWidth: 3,
                spacing: 2.5,
                maxHeight: height,
                tint: tint
            )
        } else {
            FlowWaveShape(
                levels: levels.map { Double($0) / 100 },
                controlPoints: controlPoints
            )
            .fill(tint)
            .frame(height: height)
            .animation(.smooth(duration: 0.55), value: levels)
        }
    }
}

/// The island visibly runs out of time: a self-updating ring over the last
/// sixty seconds before the recording cap. Zero payload — derived entirely
/// from existing fields.
private struct CapRing: View {
    let startedAt: Date

    var body: some View {
        let capEnd = startedAt.addingTimeInterval(FlowBridgeConstants.maxRecordingSeconds)
        ProgressView(
            timerInterval: capEnd.addingTimeInterval(-60)...capEnd,
            countsDown: true
        ) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(.orange)
        .frame(width: 16, height: 16)
    }
}

// MARK: - Phase styling

private enum PhaseStyle {
    static func waveTint(for phase: DictationActivityAttributes.ContentState.Phase) -> AnyShapeStyle {
        switch phase {
        case .recording:
            return AnyShapeStyle(FlowBridgeTheme.recordingGradient)
        case .transcribing:
            return AnyShapeStyle(FlowBridgeTheme.accentGradient)
        case .ready:
            return AnyShapeStyle(Color.green.gradient)
        case .failed:
            return AnyShapeStyle(Color.orange.gradient)
        }
    }
}

// MARK: - Compact & minimal

private struct CompactLeading: View {
    let state: DictationActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        switch state.phase {
        case .recording:
            // A live mini-ribbon — optically matched to the trailing side.
            LiveWave(
                levels: state.levels,
                controlPoints: 6,
                height: 14,
                tint: PhaseStyle.waveTint(for: .recording)
            )
            .frame(width: 26)
            .opacity(isStale ? 0.35 : 1)
        case .transcribing:
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(FlowBridgeTheme.flowViolet)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct CompactTrailing: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 3) {
            if state.phase == .recording {
                if state.capWarning {
                    CapRing(startedAt: state.startedAt)
                        .frame(width: 14, height: 14)
                } else {
                    RecordingDot()
                }
            }
            TimerText(state: state)
                .font(.caption.monospacedDigit())
        }
        .frame(maxWidth: 56)
    }
}

private struct MinimalGlyph: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(FlowBridgeTheme.recordingWarm)
                .symbolEffect(.pulse, options: .repeating)
        case .transcribing:
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(FlowBridgeTheme.flowViolet)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Expanded regions

private struct ExpandedLeading: View {
    let state: DictationActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        switch state.phase {
        case .recording:
            LiveWave(
                levels: state.levels,
                controlPoints: 7,
                height: 30,
                tint: PhaseStyle.waveTint(for: .recording)
            )
            .opacity(isStale ? 0.35 : 1)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        case .transcribing:
            Image(systemName: "ellipsis")
                .font(.title2)
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(FlowBridgeTheme.flowViolet)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: state.phase)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        }
    }
}

private struct ExpandedTrailing: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                if state.phase == .recording {
                    if state.capWarning {
                        CapRing(startedAt: state.startedAt)
                    } else {
                        RecordingDot()
                    }
                }
                TimerText(state: state)
                    .font(.title3.monospacedDigit())
            }
            Text(microLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            if state.phase == .recording, let words = state.wordCount {
                Text("\(words) words")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private var microLabel: String {
        switch state.phase {
        case .recording: return state.capWarning ? "ENDING SOON" : "REC"
        case .transcribing: return "POLISHING"
        case .ready: return "DONE"
        case .failed: return "FAILED"
        }
    }
}

private struct ExpandedBottom: View {
    let state: DictationActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        switch state.phase {
        case .recording:
            if isStale {
                // The app process is gone: a Stop button would lie. Tapping
                // the island opens the app, where safety-buffer recovery
                // picks the dictation up.
                Label("Open FlowBridge to recover", systemImage: "arrow.up.forward.app")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 12) {
                    LiveWave(
                        levels: state.levels,
                        controlPoints: 24,
                        height: 26,
                        tint: PhaseStyle.waveTint(for: .recording)
                    )
                    .frame(maxWidth: .infinity)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))

                    Button(intent: StopDictationIntent()) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .animation(.snappy(duration: 0.38, extraBounce: 0.12), value: state.phase)
            }
        case .transcribing:
            // The wave freezes at its last real levels and turns violet:
            // same organism, new phase.
            LiveWave(
                levels: state.levels,
                controlPoints: 24,
                height: 26,
                tint: PhaseStyle.waveTint(for: .transcribing)
            )
            .frame(maxWidth: .infinity)
        case .ready:
            SummaryLine(state: state)
        case .failed:
            EmptyView()
        }
    }
}

// MARK: - Shared pieces

private struct RecordingDot: View {
    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(FlowBridgeTheme.recordingWarm)
            .symbolEffect(.pulse, options: .repeating)
    }
}

private struct TimerText: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording:
            // Self-updating, costs no update budget. Inside the last minute
            // before the cap it flips into an amber countdown.
            Text(
                timerInterval: state.startedAt...state.startedAt.addingTimeInterval(FlowBridgeConstants.maxRecordingSeconds),
                countsDown: state.capWarning
            )
            .foregroundStyle(state.capWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
        case .transcribing, .ready, .failed:
            if let seconds = state.recordedSeconds {
                Text("\(seconds)s")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TranscriptHero: View {
    let state: DictationActivityAttributes.ContentState
    let isStale: Bool
    var lineLimit = 2
    var font: Font = .title3

    var body: some View {
        Text(displayText)
            .font(font)
            .fontDesign(.rounded)
            .fontWeight(state.phase == .ready ? .semibold : .medium)
            .italic(!hasText)
            .minimumScaleFactor(0.9)
            .lineLimit(lineLimit)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(hasText && !interrupted ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .contentTransition(.interpolate)
            .animation(.smooth(duration: 0.3), value: state.transcriptPreview)
    }

    private var hasText: Bool { !state.transcriptPreview.isEmpty }
    private var interrupted: Bool { isStale && state.phase == .recording }

    private var displayText: String {
        if interrupted {
            return "Recording interrupted — open FlowBridge"
        }
        if hasText {
            return state.transcriptPreview
        }
        switch state.phase {
        case .recording: return "Listening…"
        case .transcribing: return "Polishing…"
        case .ready: return "Copied to clipboard"
        case .failed: return "Something went wrong"
        }
    }
}

private struct SummaryLine: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        if !summaryText.isEmpty {
            Label {
                Text(summaryText)
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "text.word.spacing")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var summaryText: String {
        var parts: [String] = []
        if let words = state.wordCount {
            parts.append("\(words) words")
        }
        if let seconds = state.recordedSeconds {
            parts.append("\(seconds)s")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Lock Screen, StandBy, Watch

private struct LockScreenView: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<DictationActivityAttributes>

    var body: some View {
        switch family {
        case .small:
            WatchView(state: context.state)
        case .medium:
            FullLockView(state: context.state, isStale: context.isStale)
        @unknown default:
            FullLockView(state: context.state, isStale: context.isStale)
        }
    }
}

private struct FullLockView: View {
    let state: DictationActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LiveWave(
                    levels: state.levels,
                    controlPoints: 7,
                    height: 16,
                    tint: PhaseStyle.waveTint(for: state.phase)
                )
                .frame(width: 44)
                .opacity(isStale && state.phase == .recording ? 0.35 : 1)
                Text("FlowBridge")
                    .font(.headline)
                Spacer()
                if state.phase == .recording {
                    if state.capWarning {
                        CapRing(startedAt: state.startedAt)
                            .frame(width: 14, height: 14)
                    } else {
                        RecordingDot()
                    }
                }
                TimerText(state: state)
                    .font(.subheadline.monospacedDigit())
            }

            TranscriptHero(state: state, isStale: isStale, lineLimit: 3)

            if state.phase == .recording && !isStale {
                Button(intent: StopDictationIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            if state.phase == .ready {
                SummaryLine(state: state)
            }
        }
        .padding(16)
        // nil keeps the system material: StandBy night-mode red-shift and
        // wallpaper tinting stay correct.
        .activityBackgroundTint(nil)
        .activitySystemActionForegroundColor(FlowBridgeTheme.flowViolet)
    }
}

private struct WatchView: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                LiveWave(
                    levels: state.levels,
                    controlPoints: 5,
                    height: 12,
                    tint: PhaseStyle.waveTint(for: state.phase)
                )
                .frame(width: 36)
                Spacer()
                TimerText(state: state)
                    .font(.caption.monospacedDigit())
            }
            TranscriptHero(state: state, isStale: false, lineLimit: 1, font: .footnote)
        }
        .padding(10)
    }
}

// MARK: - Previews (Xcode canvas harness for every phase)

#if DEBUG
private extension DictationActivityAttributes.ContentState {
    static let quietLevels: [UInt8] = [
        4, 5, 6, 5, 7, 9, 8, 6, 5, 4, 6, 8,
        10, 9, 7, 5, 4, 5, 6, 7, 6, 5, 4, 4,
    ]
    static let loudLevels: [UInt8] = [
        12, 28, 55, 70, 62, 48, 80, 95, 88, 60, 42, 66,
        91, 77, 54, 38, 72, 99, 85, 58, 44, 63, 86, 70,
    ]

    static let previewQuiet = DictationActivityAttributes.ContentState(
        phase: .recording,
        transcriptPreview: "",
        startedAt: Date(),
        levels: quietLevels
    )
    static let previewSpeaking = DictationActivityAttributes.ContentState(
        phase: .recording,
        transcriptPreview: "questa è la dettatura che scorre in tempo reale dentro l'isola mentre parlo",
        startedAt: Date(timeIntervalSinceNow: -42),
        levels: loudLevels
    )
    static let previewCapWarning = DictationActivityAttributes.ContentState(
        phase: .recording,
        transcriptPreview: "ultimo minuto disponibile prima del limite di registrazione",
        startedAt: Date(timeIntervalSinceNow: -550),
        levels: loudLevels,
        capWarning: true
    )
    static let previewTranscribing = DictationActivityAttributes.ContentState(
        phase: .transcribing,
        transcriptPreview: "il testo appena dettato in attesa del polish on-device",
        startedAt: Date(timeIntervalSinceNow: -31),
        levels: quietLevels,
        recordedSeconds: 31
    )
    static let previewReady = DictationActivityAttributes.ContentState(
        phase: .ready,
        transcriptPreview: "Ecco il testo pulito, già copiato negli appunti.",
        startedAt: Date(timeIntervalSinceNow: -33),
        levels: DictationActivityAttributes.ContentState.restingLevels,
        wordCount: 42,
        recordedSeconds: 31
    )
    static let previewFailed = DictationActivityAttributes.ContentState(
        phase: .failed,
        transcriptPreview: "Nothing heard — the microphone stayed silent.",
        startedAt: Date(),
        levels: DictationActivityAttributes.ContentState.restingLevels
    )
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: DictationActivityAttributes(sessionID: UUID())) {
    DictationLiveActivity()
} contentStates: {
    DictationActivityAttributes.ContentState.previewQuiet
    DictationActivityAttributes.ContentState.previewSpeaking
    DictationActivityAttributes.ContentState.previewCapWarning
    DictationActivityAttributes.ContentState.previewTranscribing
    DictationActivityAttributes.ContentState.previewReady
    DictationActivityAttributes.ContentState.previewFailed
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: DictationActivityAttributes(sessionID: UUID())) {
    DictationLiveActivity()
} contentStates: {
    DictationActivityAttributes.ContentState.previewQuiet
    DictationActivityAttributes.ContentState.previewSpeaking
    DictationActivityAttributes.ContentState.previewCapWarning
    DictationActivityAttributes.ContentState.previewReady
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: DictationActivityAttributes(sessionID: UUID())) {
    DictationLiveActivity()
} contentStates: {
    DictationActivityAttributes.ContentState.previewSpeaking
    DictationActivityAttributes.ContentState.previewTranscribing
}

#Preview("Lock Screen", as: .content, using: DictationActivityAttributes(sessionID: UUID())) {
    DictationLiveActivity()
} contentStates: {
    DictationActivityAttributes.ContentState.previewSpeaking
    DictationActivityAttributes.ContentState.previewTranscribing
    DictationActivityAttributes.ContentState.previewReady
    DictationActivityAttributes.ContentState.previewFailed
}
#endif
