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
    /// Auto-close of the interactive ready window.
    private var windowTask: Task<Void, Never>?

    var isActive: Bool {
        activity != nil
    }

    /// Ends every activity of this type — including orphans left behind by
    /// a crashed process, which this controller instance no longer tracks
    /// and which would otherwise sit in the island for hours. Called at app
    /// bootstrap and before each new session.
    func endAllActivities() {
        windowTask?.cancel()
        windowTask = nil
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
            attributes: DictationActivityAttributes(
                sessionID: sessionID,
                language: DictationLanguage.current.whisperCode
            ),
            content: content(for: state)
        )
    }

    // MARK: - Interactive ready window (tone variants)

    /// Delivery WITHOUT ending: the island stays alive ~30s with the tone
    /// variant buttons; each tap renews the window; a new session or the
    /// timer closes it.
    func deliverInteractive(
        transcriptPreview: String,
        startedAt: Date,
        wordCount: Int?,
        recordedSeconds: Int?
    ) {
        guard let activity else { return }
        let state = DictationActivityAttributes.ContentState(
            phase: .ready,
            transcriptPreview: transcriptPreview,
            startedAt: startedAt,
            levels: DictationActivityAttributes.ContentState.restingLevels,
            wordCount: wordCount,
            recordedSeconds: recordedSeconds,
            variantsAvailable: true
        )
        enqueue {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        scheduleWindowEnd(finalState: state)
    }

    /// A variant landed: confirm in place and renew the window.
    func noteVariantApplied(_ note: String, preview: String) {
        guard let activity else { return }
        var state = DictationActivityAttributes.ContentState(
            phase: .ready,
            transcriptPreview: preview,
            startedAt: Date(),
            levels: DictationActivityAttributes.ContentState.restingLevels,
            variantsAvailable: true,
            toneNote: note
        )
        state.recordedSeconds = nil
        enqueue {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        scheduleWindowEnd(finalState: state)
    }

    private func scheduleWindowEnd(finalState: DictationActivityAttributes.ContentState, after seconds: TimeInterval = 30) {
        windowTask?.cancel()
        windowTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return // cancelled: the window was renewed or superseded
            }
            guard !Task.isCancelled else { return }
            self?.closeWindow(finalState: finalState)
        }
    }

    private func closeWindow(finalState: DictationActivityAttributes.ContentState) {
        guard let activity else { return }
        self.activity = nil
        var settled = finalState
        settled.variantsAvailable = false
        enqueue {
            await activity.end(
                ActivityContent(state: settled, staleDate: nil),
                dismissalPolicy: .after(.now + 2)
            )
        }
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
        windowTask?.cancel()
        windowTask = nil
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
                // Error copy needs reading time; success needs a beat.
                dismissalPolicy: .after(.now + (failed ? 10 : FlowBridgeConstants.liveActivityIdleDismissSeconds))
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
        windowTask?.cancel()
        windowTask = nil
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
        let staleSeconds: TimeInterval? = state.pausedAt != nil ? 45
            : (state.phase == .recording ? 15 : nil)
        return ActivityContent(
            state: state,
            staleDate: staleSeconds.map { Date(timeIntervalSinceNow: $0) }
        )
    }
}
