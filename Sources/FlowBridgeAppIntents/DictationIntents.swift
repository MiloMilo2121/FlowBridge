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
struct StartDictationIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription("Start FlowBridge dictation in the background, with live progress in the Dynamic Island.")

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            try await DictationCommandHub.shared.requestStart()
            return .result()
        } catch {
            // Background start is not possible right now (first run, missing
            // permission, audio-session failure): open the app and let the
            // foreground pipeline take over. The foreground hop only exists
            // in the app target — the SDK forbids it in extensions, and the
            // system executes intents in the app process anyway.
            #if FLOWBRIDGE_MAIN_APP
            try await requestToContinueInForeground()
            await DictationCommandHub.shared.requestToggle()
            return .result()
            #else
            throw error
            #endif
        }
    }
}

#if FLOWBRIDGE_MAIN_APP
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
