import AppIntents
import FlowBridgeShared
import Foundation

/// Starts dictation without opening the app (Action Button, Control Center,
/// Lock Screen control, Shortcuts).
///
/// `AudioRecordingIntent` makes the system run this in the app's process and
/// permits starting the microphone from the background — on the documented
/// condition that a Live Activity starts immediately and stays up for the
/// whole recording (the coordinator guarantees that). If the background start
/// fails (permission not yet granted, audio session denied), the intent falls
/// back to continuing in the foreground, which is the V1 behavior.
///
/// This file is compiled into both the app and the widget extension; the
/// system always executes the intents in the app process, where
/// `DictationCommandHub` has handlers registered.
///
/// `ForegroundContinuableIntent` is unavailable in app extensions, so the
/// widget build (which only needs the type to exist for its buttons) gets
/// the conformance and its foreground fallback conditioned out. The intent
/// always runs in the app process regardless.
struct StartDictationIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription("Start FlowBridge dictation in the background, with live progress in the Dynamic Island.")

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            try await DictationCommandHub.shared.requestStart()
            return .result()
        } catch {
            #if FLOWBRIDGE_EXTENSION
            // Unreachable at runtime (the app process runs this intent), but
            // the extension build cannot see requestToContinueInForeground.
            throw error
            #else
            // Background start is not possible right now (first run, missing
            // permission, audio-session failure): open the app and let the
            // foreground pipeline take over.
            try await requestToContinueInForeground()
            await DictationCommandHub.shared.requestToggle()
            return .result()
            #endif
        }
    }
}

// The foreground-continuation path exists only in the app, not the extension.
#if !FLOWBRIDGE_EXTENSION
extension StartDictationIntent: ForegroundContinuableIntent {}
#endif

/// Stops the active dictation. Wired to the Live Activity's stop button and
/// exposed to Shortcuts. Runs in the app process (`LiveActivityIntent`),
/// where the recorder and the audio session live.
struct StopDictationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Dictation"
    static let description = IntentDescription("Stop the active FlowBridge dictation and deliver the transcript.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await DictationCommandHub.shared.requestStop()
        return .result()
    }
}
