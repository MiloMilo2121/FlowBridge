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
    /// Latest ready payload, retained so late intent classification can
    /// replace the generic refinement action without losing summary data.
    private var readyState: DictationActivityAttributes.ContentState?

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
        readyState = nil
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
        readyState = nil

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

    // MARK: - Interactive ready window

    /// Delivery WITHOUT ending: the island stays alive ~30s with one useful
    /// follow-up action. Each tap renews the window; a new session or the
    /// timer closes it.
    func deliverInteractive(
        transcriptPreview: String,
        startedAt: Date,
        wordCount: Int?,
        recordedSeconds: Int?,
        variantsAvailable: Bool
    ) {
        guard let activity else { return }
        let state = DictationActivityAttributes.ContentState(
            phase: .ready,
            transcriptPreview: transcriptPreview,
            startedAt: startedAt,
            levels: DictationActivityAttributes.ContentState.restingLevels,
            wordCount: wordCount,
            recordedSeconds: recordedSeconds,
            variantsAvailable: variantsAvailable
        )
        readyState = state
        enqueue {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        scheduleWindowEnd(finalState: state)
    }

    /// A variant landed: confirm in place and renew the window.
    func noteVariantApplied(_ note: String, preview: String) {
        guard let activity else { return }
        var state = readyState ?? DictationActivityAttributes.ContentState(
            phase: .ready,
            transcriptPreview: preview,
            startedAt: Date(),
            levels: DictationActivityAttributes.ContentState.restingLevels,
            variantsAvailable: true
        )
        state.transcriptPreview = String(preview.suffix(220))
        state.toneNote = note
        readyState = state
        enqueue {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        scheduleWindowEnd(finalState: state)
    }

    /// Intent classification finishes after delivery. Replace the generic
    /// "Refine" fallback with the useful real-world action in-place.
    func offerSuggestedAction(
        kind: DictationActivityAttributes.ContentState.SuggestedActionKind,
        title: String,
        detail: String
    ) {
        guard let activity, var state = readyState else { return }
        state.suggestedActionKind = kind
        state.suggestedActionTitle = String(title.prefix(44))
        state.suggestedActionDetail = detail.isEmpty ? nil : String(detail.prefix(72))
        state.toneNote = nil
        readyState = state
        enqueue {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        scheduleWindowEnd(finalState: state)
    }

    func clearSuggestedAction() {
        guard let activity, var state = readyState else { return }
        state.suggestedActionKind = nil
        state.suggestedActionTitle = nil
        state.suggestedActionDetail = nil
        readyState = state
        enqueue {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        scheduleWindowEnd(finalState: state)
    }

    func noteActionCompleted(_ note: String) {
        guard let activity, var state = readyState else { return }
        state.suggestedActionKind = nil
        state.suggestedActionTitle = nil
        state.suggestedActionDetail = nil
        state.variantsAvailable = false
        state.toneNote = note
        readyState = state
        enqueue {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        scheduleWindowEnd(finalState: state, after: 7)
    }

    /// A failed system hand-off must not leave a tappable action whose
    /// in-memory payload has already been cleared by the coordinator.
    func noteActionFailed() {
        guard let activity, var state = readyState else { return }
        state.suggestedActionKind = nil
        state.suggestedActionTitle = nil
        state.suggestedActionDetail = nil
        state.variantsAvailable = false
        readyState = state
        enqueue {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        scheduleWindowEnd(finalState: state, after: 7)
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
        readyState = nil
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
        readyState = nil
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
        readyState = nil
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
