import ActivityKit
import FlowBridgeShared
import Foundation

/// Owns the dictation Live Activity: one activity per session, started the
/// moment recording begins (required for background starts through
/// `AudioRecordingIntent` — if no Live Activity is visible, the system stops
/// the audio), updated locally as the transcript streams, ended shortly
/// after the transcript is delivered.
///
/// Every ActivityKit call (request/update/end) is funneled through a single
/// serial task chain so operations apply in the order they were requested —
/// spawning an unordered `Task` per update let a stale snapshot land after a
/// newer one, or after the activity had already ended.
@MainActor
final class DictationActivityController {
    private var activity: Activity<DictationActivityAttributes>?
    private var tail: Task<Void, Never> = Task {}
    private var isCloud = false

    var isActive: Bool {
        activity != nil
    }

    func start(sessionID: UUID, startedAt: Date, isCloud: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(immediately: true)
        self.isCloud = isCloud

        let state = DictationActivityAttributes.ContentState(
            phase: .recording,
            transcriptPreview: "",
            startedAt: startedAt,
            isCloud: isCloud
        )
        activity = try? Activity.request(
            attributes: DictationActivityAttributes(sessionID: sessionID),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    func update(phase: DictationActivityAttributes.ContentState.Phase, transcriptPreview: String,
                startedAt: Date, level: UInt8 = 0) {
        guard let activity else { return }
        let state = DictationActivityAttributes.ContentState(
            phase: phase,
            transcriptPreview: transcriptPreview,
            startedAt: startedAt,
            level: level,
            finishedAt: phase == .transcribing ? Date() : nil,
            isCloud: isCloud
        )
        // ActivityKit's async surface is thread-safe by design; its types
        // just lack Sendable annotations in this SDK.
        nonisolated(unsafe) let handle = activity
        nonisolated(unsafe) let content = ActivityContent(state: state, staleDate: nil)
        enqueue {
            await handle.update(content)
        }
    }

    /// Shows the final state briefly, then dismisses.
    func finish(transcriptPreview: String, startedAt: Date, failed: Bool = false) {
        guard let activity else { return }
        self.activity = nil

        let state = DictationActivityAttributes.ContentState(
            phase: failed ? .failed : .ready,
            transcriptPreview: transcriptPreview,
            startedAt: startedAt,
            finishedAt: Date(),
            isCloud: isCloud
        )
        nonisolated(unsafe) let handle = activity
        nonisolated(unsafe) let content = ActivityContent(state: state, staleDate: nil)
        enqueue {
            await handle.end(
                content,
                dismissalPolicy: .after(.now + FlowBridgeConstants.liveActivityIdleDismissSeconds)
            )
        }
    }

    func end(immediately: Bool) {
        guard let activity else { return }
        self.activity = nil
        nonisolated(unsafe) let handle = activity
        enqueue {
            await handle.end(nil, dismissalPolicy: immediately ? .immediate : .default)
        }
    }

    /// Appends `operation` after whatever is already queued, preserving order.
    /// Main-actor closures, not @Sendable: the activity handle never leaves
    /// this actor, so captures stay region-safe under strict concurrency.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous.value
            await operation()
        }
    }
}
