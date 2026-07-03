import ActivityKit
import FlowBridgeShared
import Foundation

/// Owns the dictation Live Activity: one activity per session, started the
/// moment recording begins (required for background starts through
/// `AudioRecordingIntent` — if no Live Activity is visible, the system stops
/// the audio), updated locally as the transcript streams, ended shortly
/// after the transcript is delivered.
@MainActor
final class DictationActivityController {
    private var activity: Activity<DictationActivityAttributes>?

    var isActive: Bool {
        activity != nil
    }

    func start(sessionID: UUID, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(immediately: true)

        let state = DictationActivityAttributes.ContentState(
            phase: .recording,
            transcriptPreview: "",
            startedAt: startedAt,
            levels: DictationActivityAttributes.ContentState.restingLevels
        )
        activity = try? Activity.request(
            attributes: DictationActivityAttributes(sessionID: sessionID),
            content: content(for: state)
        )
    }

    func update(_ state: DictationActivityAttributes.ContentState) {
        guard let activity else { return }
        let content = content(for: state)
        Task {
            await activity.update(content)
        }
    }

    /// Shows the final state briefly, then dismisses.
    func finish(
        transcriptPreview: String,
        startedAt: Date,
        wordCount: Int? = nil,
        recordedSeconds: Int? = nil,
        failed: Bool = false
    ) {
        guard let activity else { return }
        self.activity = nil

        let state = DictationActivityAttributes.ContentState(
            phase: failed ? .failed : .ready,
            transcriptPreview: transcriptPreview,
            startedAt: startedAt,
            levels: DictationActivityAttributes.ContentState.restingLevels,
            wordCount: wordCount,
            recordedSeconds: recordedSeconds
        )
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(.now + FlowBridgeConstants.liveActivityIdleDismissSeconds)
            )
        }
    }

    /// A start-time failure gets narrated in the island instead of a silent
    /// vanish.
    func markFailed(message: String, startedAt: Date) {
        finish(transcriptPreview: message, startedAt: startedAt, failed: true)
    }

    func end(immediately: Bool) {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: immediately ? .immediate : .default)
        }
    }

    /// Recording content goes stale 15s after its last update: if the app
    /// process dies mid-session the island dims and says so
    /// (`context.isStale` in the widget) instead of keeping a dead waveform
    /// alive. Final states never go stale.
    private func content(
        for state: DictationActivityAttributes.ContentState
    ) -> ActivityContent<DictationActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: state.phase == .recording ? Date(timeIntervalSinceNow: 15) : nil
        )
    }
}
