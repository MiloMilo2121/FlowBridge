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
    public var pauseHandler: (() async -> Void)?
    public var resumeHandler: (() async -> Void)?
    /// Re-polishes the delivered transcript with a tone (raw ToneProfile
    /// value) and refreshes clipboard + island.
    public var applyToneHandler: ((String) async -> Void)?
    /// Performs the single contextual action currently shown in the ready
    /// Live Activity. No persistence fallback: the offer only exists while
    /// the serving app process owns that ready window.
    public var performSuggestedActionHandler: (() async -> Void)?

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

    public func requestPause() async {
        guard let pauseHandler else {
            try? PendingCommandStore().write(.pauseRecording)
            return
        }
        await pauseHandler()
    }

    public func requestResume() async {
        guard let resumeHandler else {
            try? PendingCommandStore().write(.resumeRecording)
            return
        }
        await resumeHandler()
    }

    public func requestApplyTone(_ rawTone: String) async {
        // No pending-store fallback: the variants window only exists while
        // the app process is alive to serve it.
        await applyToneHandler?(rawTone)
    }

    public func requestPerformSuggestedAction() async {
        await performSuggestedActionHandler?()
    }
}
