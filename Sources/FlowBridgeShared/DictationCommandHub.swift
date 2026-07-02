import Foundation

/// In-process bridge between App Intents and the dictation coordinator.
///
/// `AudioRecordingIntent`/`LiveActivityIntent` implementations are compiled
/// into both the app and the widget extension, but the system always executes
/// them in the app's process. The app registers handlers here at launch; the
/// widget build never registers (nor runs) them, so intent code can call the
/// hub without referencing app-only types. If no handler is registered the
/// hub degrades to the pending-command store, which the app consumes on its
/// next activation.
@MainActor
public final class DictationCommandHub {
    public static let shared = DictationCommandHub()

    public var startHandler: (() async throws -> Void)?
    public var stopHandler: (() async -> Void)?
    public var toggleHandler: (() async -> Void)?

    private init() {}

    public func requestStart() async throws {
        guard let startHandler else {
            try PendingCommandStore().write(.toggleRecording)
            return
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
