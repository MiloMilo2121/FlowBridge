import ActivityKit
import FlowBridgeShared
import SwiftUI
import WidgetKit

/// The dictation session in the Dynamic Island and on the Lock Screen,
/// in the Linea Viva language: orange is the live capture, violet is the
/// "thinking" phase, green appears only for privacy/done, red only on Stop.
///
/// ActivityKit constraints shape this deliberately: updates are throttled
/// and payloads capped, so continuous motion comes from local symbol
/// effects (never from pushed frames), and the timer is the system's
/// self-updating `Text(timerInterval:)`, which costs no update budget.
struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseSymbol(phase: context.state.phase, level: context.state.level ?? 0)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 6) {
                        if context.state.phase == .recording {
                            Circle()
                                .fill(FlowPalette.orange400)
                                .frame(width: 5, height: 5)
                                .shadow(color: FlowPalette.orange400.opacity(0.9), radius: 3)
                        }
                        TimerText(state: context.state)
                            .font(.title3.weight(.medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    TranscriptPreview(state: context.state, lineLimit: 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedControls(state: context.state)
                }
            } compactLeading: {
                PhaseSymbol(phase: context.state.phase, level: context.state.level ?? 0)
            } compactTrailing: {
                TimerText(state: context.state)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: 44)
            } minimal: {
                PhaseSymbol(phase: context.state.phase, level: context.state.level ?? 0)
            }
        }
        // One implementation, four surfaces: the small family relays the
        // activity to the Apple Watch Smart Stack and CarPlay for free.
        .supplementalActivityFamilies([.small])
    }
}

private struct PhaseSymbol: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    let phase: DictationActivityAttributes.ContentState.Phase
    var level: UInt8 = 0

    var body: some View {
        symbol
            .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var symbol: some View {
        switch phase {
        case .recording:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative,
                              options: reduceMotion || luminanceReduced ? .nonRepeating : .repeating)
                .foregroundStyle(FlowPalette.orange400)
                .scaleEffect(reduceMotion || luminanceReduced ? 1 : 1 + CGFloat(level) / 1_020)
                .animation(reduceMotion || luminanceReduced ? nil : .easeOut(duration: 0.45), value: level)
        case .transcribing:
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative, options: reduceMotion ? .nonRepeating : .repeating)
                .foregroundStyle(FlowPalette.violet400)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(FlowPalette.green500)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(FlowPalette.orange400)
        }
    }

    private var accessibilityDescription: String {
        switch phase {
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .ready: return "Transcript copied"
        case .failed: return "Dictation failed"
        }
    }
}

private struct TimerText: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        if state.phase == .recording {
            Text(timerInterval: state.startedAt...state.startedAt.addingTimeInterval(FlowBridgeConstants.maxRecordingSeconds), countsDown: false)
        } else {
            let seconds = max(0, Int((state.finishedAt ?? Date()).timeIntervalSince(state.startedAt)))
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TranscriptPreview: View {
    let state: DictationActivityAttributes.ContentState
    var lineLimit = 2

    var body: some View {
        transcriptText
            .lineLimit(lineLimit)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var transcriptText: some View {
        if state.transcriptPreview.isEmpty {
            Text(placeholder)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if state.phase == .recording {
            // Live words in the transcript voice (serif italic) with the
            // design's orange caret closing the line.
            (Text(state.transcriptPreview) + Text(" ▎").foregroundStyle(FlowPalette.orange400))
                .font(.callout.italic())
                .fontDesign(.serif)
        } else {
            Text(state.transcriptPreview)
                .font(.callout.italic())
                .fontDesign(.serif)
        }
    }

    private var placeholder: String {
        switch state.phase {
        case .recording: return state.isCloud == true ? "Listening · AssemblyAI EU" : "Listening…"
        case .transcribing: return "Transcribing…"
        case .ready: return "Copied to clipboard"
        case .failed: return "Something went wrong"
        }
    }
}

private struct ExpandedControls: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        if state.phase == .recording {
            Button(intent: StopDictationIntent()) {
                HStack(spacing: 8) {
                    LineaVivaIcon(.stop)
                        .frame(width: 14, height: 14)
                    Text("Stop")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(FlowPalette.red500)
        } else if state.phase == .ready {
            Link(destination: URL(string: "flowbridge://diary")!) {
                Label("Open transcript", systemImage: "text.alignleft")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(FlowPalette.violet500)
        } else if state.phase == .failed {
            Link(destination: URL(string: "flowbridge://recover")!) {
                Label("Recover or retry", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(FlowPalette.orange500)
        }
    }
}

private struct LockScreenView: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LineaVivaIcon(.waveform)
                    .foregroundStyle(FlowPalette.violet400)
                    .frame(width: 15, height: 15)
                Text("FlowBridge")
                    .font(.headline)
                if state.isCloud == true {
                    Text("EU CLOUD").font(.caption2.weight(.bold)).foregroundStyle(FlowPalette.orange400)
                }
                Spacer()
                PhaseSymbol(phase: state.phase, level: state.level ?? 0)
                    .font(.subheadline)
                TimerText(state: state)
                    .font(.subheadline.monospacedDigit())
            }
            TranscriptPreview(state: state, lineLimit: 3)
            ExpandedControls(state: state)
        }
        .padding(14)
        .activityBackgroundTint(nil)
    }
}
