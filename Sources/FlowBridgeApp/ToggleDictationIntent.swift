import AppIntents
import FlowBridgeShared
import Foundation

struct ToggleDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Dictation"
    static let description = IntentDescription("Start or stop FlowBridge dictation.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        try PendingCommandStore().write(.toggleRecording)
        return .result()
    }
}

struct TranscribeQueuedAudioIntent: AppIntent {
    static let title: LocalizedStringResource = "Transcribe Queued Audio"
    static let description = IntentDescription("Transcribe the latest audio file queued by FlowBridge.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        try PendingCommandStore().write(.transcribeQueuedAudio)
        return .result()
    }
}

struct FlowBridgeShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Dictate with \(.applicationName)",
                "\(.applicationName) dictation"
            ],
            shortTitle: "Quick Dictation",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: [
                "Toggle \(.applicationName)",
                "Start \(.applicationName) dictation"
            ],
            shortTitle: "Dictate",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: StartAssistantIntent(),
            phrases: [
                "Act with \(.applicationName)",
                "Start a \(.applicationName) voice action"
            ],
            shortTitle: "Voice Action",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: TranscribeQueuedAudioIntent(),
            phrases: [
                "Transcribe with \(.applicationName)"
            ],
            shortTitle: "Transcribe",
            systemImageName: "waveform"
        )
    }
}
