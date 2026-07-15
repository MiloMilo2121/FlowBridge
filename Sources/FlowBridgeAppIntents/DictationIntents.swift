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
/// iOS 26's dynamic foreground mode replaces the older conditional
/// `ForegroundContinuableIntent` conformance and compiles consistently in the
/// app and widget targets. The intent still executes in the app process.
struct StartDictationIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription("Start FlowBridge dictation in the background, with live progress in the Dynamic Island.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            try await DictationCommandHub.shared.requestStart()
            return .result()
        } catch {
            // Background start is not possible right now (first run, missing
            // permission, audio-session failure): open the app and let the
            // foreground pipeline take over.
            guard systemContext.currentMode.canContinueInForeground else {
                throw error
            }
            try await continueInForeground()
            await DictationCommandHub.shared.requestToggle()
            return .result()
        }
    }
}

/// Stops the active dictation. Wired to the Live Activity's stop button and
/// exposed to Shortcuts. Runs in the app process (`LiveActivityIntent`),
/// where the recorder and the audio session live.
struct PauseDictationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Dictation"
    static let description = IntentDescription("Pause the active FlowBridge dictation without ending it.")
    static let supportedModes: IntentModes = [.background]

    func perform() async throws -> some IntentResult {
        await DictationCommandHub.shared.requestPause()
        return .result()
    }
}

struct ResumeDictationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Dictation"
    static let description = IntentDescription("Resume the paused FlowBridge dictation.")
    static let supportedModes: IntentModes = [.background]

    func perform() async throws -> some IntentResult {
        await DictationCommandHub.shared.requestResume()
        return .result()
    }
}

/// One tap in the island optionally refines the already-delivered verbatim
/// transcript and refreshes the clipboard. Delivery never waits for this.
struct ApplyToneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Copy Tone Variant"
    static let description = IntentDescription("Optionally refine the last delivered transcript and copy the result.")
    static let supportedModes: IntentModes = [.background]

    @Parameter(title: "Tone")
    var tone: String

    init() {
        tone = "formal"
    }

    init(tone: String) {
        self.tone = tone
    }

    func perform() async throws -> some IntentResult {
        await DictationCommandHub.shared.requestApplyTone(tone)
        return .result()
    }
}

/// Executes the one action the delivered dictation clearly implies. The
/// Activity carries only its label; the app process owns the structured
/// Calendar/Reminder/Message/Mail payload.
struct PerformSuggestedActionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Perform Suggested Action"
    static let description = IntentDescription("Perform the action suggested by the latest FlowBridge dictation.")
    static let supportedModes: IntentModes = [.background]

    func perform() async throws -> some IntentResult {
        await DictationCommandHub.shared.requestPerformSuggestedAction()
        return .result()
    }
}

struct StopDictationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Dictation"
    static let description = IntentDescription("Stop the active FlowBridge dictation and deliver the transcript.")
    static let supportedModes: IntentModes = [.background]

    @MainActor
    func perform() async throws -> some IntentResult {
        await DictationCommandHub.shared.requestStop()
        return .result()
    }
}
