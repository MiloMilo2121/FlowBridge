import ActivityKit
import FlowBridgeShared
import SwiftUI
import WidgetKit

/// The dictation session in the Dynamic Island and on the Lock Screen.
///
/// One shape morphs through the phases (waveform → thinking dots → check):
/// the compact view is waveform + self-updating timer (`Text(timerInterval:)`
/// costs no update budget), the expanded view adds the streaming transcript
/// preview and the Stop button (`StopDictationIntent` runs in the app
/// process, where the audio session lives).
struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseSymbol(phase: context.state.phase)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: context.state)
                        .font(.title3.monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    TranscriptPreview(state: context.state, lineLimit: 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedControls(state: context.state)
                }
            } compactLeading: {
                PhaseSymbol(phase: context.state.phase)
            } compactTrailing: {
                TimerText(state: context.state)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                PhaseSymbol(phase: context.state.phase)
            }
        }
    }
}

private struct PhaseSymbol: View {
    let phase: DictationActivityAttributes.ContentState.Phase

    var body: some View {
        switch phase {
        case .recording:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(.red)
        case .transcribing:
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(.purple)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct TimerText: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        if state.phase == .recording {
            Text(timerInterval: state.startedAt...state.startedAt.addingTimeInterval(FlowBridgeConstants.maxRecordingSeconds), countsDown: false)
        } else {
            Text(state.startedAt, style: .relative)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TranscriptPreview: View {
    let state: DictationActivityAttributes.ContentState
    var lineLimit = 2

    var body: some View {
        Text(previewText)
            .font(.callout)
            .lineLimit(lineLimit)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(state.transcriptPreview.isEmpty ? .secondary : .primary)
    }

    private var previewText: String {
        if !state.transcriptPreview.isEmpty {
            return state.transcriptPreview
        }
        switch state.phase {
        case .recording: return "Listening…"
        case .transcribing: return "Finishing up…"
        case .ready: return "Transcript copied"
        case .failed: return "Something went wrong"
        }
    }
}

private struct ExpandedControls: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        if state.phase == .recording {
            Button(intent: StopDictationIntent()) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}

private struct LockScreenView: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PhaseSymbol(phase: state.phase)
                Text("FlowBridge")
                    .font(.headline)
                Spacer()
                TimerText(state: state)
                    .font(.subheadline.monospacedDigit())
            }
            TranscriptPreview(state: state, lineLimit: 3)
            if state.phase == .recording {
                ExpandedControls(state: state)
            }
        }
        .padding(14)
        .activityBackgroundTint(nil)
    }
}
