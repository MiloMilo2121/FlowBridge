@preconcurrency import ActivityKit
import FlowBridgeShared
import Foundation

/// Owns the dictation Live Activity: one activity per session, started the
/// moment recording begins (required for background starts through
/// `AudioRecordingIntent` — if no Live Activity is visible, the system stops
/// the audio), updated locally as the transcript streams, ended shortly
/// after the transcript is delivered.
///
/// Every ActivityKit call is chained on the previous one: `update`/`end`
/// are async and unordered across detached Tasks, so without the chain a
/// stale waveform frame could land after a newer one — or after the final
/// content.
@MainActor
final class DictationActivityController {
    private var activity: Activity<DictationActivityAttributes>?
    private var pipeline: Task<Void, Never>?

    var isActive: Bool {
        activity != nil
    }

    /// Ends every activity of this type — including orphans left behind by
    /// a crashed process, which this controller instance no longer tracks
    /// and which would otherwise sit in the island for hours. Called at app
    /// bootstrap and before each new session.
    func endAllActivities() {
        activity = nil
        let all = Activity<DictationActivityAttributes>.activities
        guard !all.isEmpty else { return }
        enqueue {
            for orphan in all {
                await orphan.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func start(sessionID: UUID, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endAllActivities()

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
        enqueue {
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
        enqueue {
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
        enqueue {
            await activity.end(nil, dismissalPolicy: immediately ? .immediate : .default)
        }
    }

    /// Serializes ActivityKit work. The task is pinned to the main actor so
    /// the captured (non-Sendable) `Activity` never crosses an isolation
    /// boundary, while still chaining after the previous operation.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        pipeline = Task { @MainActor [previous = pipeline] in
            await previous?.value
            await operation()
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
