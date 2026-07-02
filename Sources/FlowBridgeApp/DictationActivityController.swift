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
            startedAt: startedAt
        )
        activity = try? Activity.request(
            attributes: DictationActivityAttributes(sessionID: sessionID),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    func update(phase: DictationActivityAttributes.ContentState.Phase, transcriptPreview: String, startedAt: Date) {
        guard let activity else { return }
        let state = DictationActivityAttributes.ContentState(
            phase: phase,
            transcriptPreview: transcriptPreview,
            startedAt: startedAt
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// Shows the final state briefly, then dismisses.
    func finish(transcriptPreview: String, startedAt: Date, failed: Bool = false) {
        guard let activity else { return }
        self.activity = nil

        let state = DictationActivityAttributes.ContentState(
            phase: failed ? .failed : .ready,
            transcriptPreview: transcriptPreview,
            startedAt: startedAt
        )
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(.now + FlowBridgeConstants.liveActivityIdleDismissSeconds)
            )
        }
    }

    func end(immediately: Bool) {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: immediately ? .immediate : .default)
        }
    }
}
