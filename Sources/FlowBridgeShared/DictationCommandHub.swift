import Foundation

/// In-process bridge between App Intents and the dictation coordinator.
///
/// `AudioRecordingIntent`/`LiveActivityIntent` implementations are compiled
/// into both the app and the widget extension, but the system always executes
/// them in the app's process. The app registers handlers here when the
/// coordinator is constructed; the widget build never registers (nor runs)
/// them, so intent code can call the hub without referencing app-only types.
///
/// Stop and toggle degrade to the pending-command store when unhandled: they
/// are safe to defer, because the app picks the command up on its next
/// activation. `requestStart` does not — a background start that isn't
/// actually running must not report success.
@MainActor
public final class DictationCommandHub {
    public static let shared = DictationCommandHub()

    public var startHandler: (() async throws -> Void)?
    public var stopHandler: (() async -> Void)?
    public var toggleHandler: (() async -> Void)?

    private init() {}

    /// Starts a background dictation. Throws `noDictationHandler` when no
    /// handler is registered: the start needs the live audio session and the
    /// Live Activity, both owned by the app, so a silent success here would
    /// report a dictation that is not running. `StartDictationIntent` falls
    /// back to opening the app, which does work.
    public func requestStart() async throws {
        guard let startHandler else {
            throw FlowBridgeError.noDictationHandler
        }
        try await startHandler()
    }

    public func requestStop() async {
        guard let stopHandler else {
            try? PendingCommandStore().write(.stopRecording)
            return
        }
        await stopHandler()
    }

    public func requestToggle() async {
        guard let toggleHandler else {
            try? PendingCommandStore().write(.toggleRecording)
            return
        }
        await toggleHandler()
    }
}
