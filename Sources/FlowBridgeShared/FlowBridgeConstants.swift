import Foundation

public enum FlowBridgeConstants {
    public static let appGroupIdentifier = "group.com.marcomilanello.flowbridge"
    public static let latestTranscriptKey = "latestTranscriptRecord"
    public static let pendingCommandKey = "pendingCommand"
    public static let queuedAudioPathKey = "queuedAudioPath"
    public static let maxRecordingSeconds: TimeInterval = 600

    /// Darwin notification posted whenever a live transcript snapshot is
    /// written to the App Group. Payload-free; readers reload from the store.
    public static let liveTranscriptDidChangeDarwinName = "com.marcomilanello.flowbridge.liveTranscriptDidChange"

    /// Darwin notification posted whenever a pending command is written, so
    /// the app process reacts immediately even while backgrounded under an
    /// active audio session.
    public static let pendingCommandDidChangeDarwinName = "com.marcomilanello.flowbridge.pendingCommandDidChange"

    /// UserDefaults key: onboarding was completed.
    public static let onboardingCompletedKey = "onboardingCompleted"

    /// How long the "ready" Live Activity stays in the Dynamic Island before
    /// dismissing itself.
    public static let liveActivityIdleDismissSeconds: TimeInterval = 6

    /// File name of the transcript history JSON in the App Group container.
    public static let historyFileName = "TranscriptHistory.json"
    /// Maximum records kept in the local history.
    public static let historyCapacity = 200

    // MARK: Cloud engine

    public static let cloudProviderName = "ElevenLabs Scribe"
    public static let cloudSpeechToTextURL = "https://api.elevenlabs.io/v1/speech-to-text"
    public static let cloudModelID = "scribe_v1"
    public static let cloudRequestTimeoutSeconds: TimeInterval = 60
    /// Keychain identifiers for the provider API key (never UserDefaults).
    public static let cloudKeychainService = "com.marcomilanello.flowbridge.cloud"
    public static let cloudKeychainAccount = "providerAPIKey"

    /// Minimum interval between Live Activity content updates while
    /// streaming; intermediate snapshots are dropped (the next one lands).
    public static let liveActivityMinUpdateInterval: TimeInterval = 0.3

    /// Keyboard live updates are Darwin-notification driven. The legacy
    /// 250ms polling loop is kept behind this flag as a fallback; when the
    /// flag is off the keyboard still runs a slow safety refresh so a missed
    /// notification can never strand a stale transcript.
    public static let keyboardLegacyPollingEnabled = false
    public static let keyboardLegacyPollingInterval: TimeInterval = 0.25
    public static let keyboardSafetyRefreshInterval: TimeInterval = 2.0

    public static let safetyBufferDirectoryName = "SafetyBuffer"
    public static let safetyBufferSampleRate: Double = 16_000
    public static let safetyBufferFlushInterval: TimeInterval = 1.0
    /// Interrupted recordings shorter than this are discarded instead of
    /// recovered: below ~1s there is no usable speech.
    public static let safetyBufferMinimumRecoverySeconds: TimeInterval = 1.0
    /// How many times an interrupted dictation is retried from the safety
    /// buffer before it is left alone. A file is renamed before each
    /// attempt, so an unrecoverable one (truncated header, engine that
    /// cannot read it, a decode that kills the process) stops being retried
    /// on every launch — and is never deleted: it is still the user's
    /// audio, retried or discarded by hand from Settings.
    public static let safetyBufferMaxRecoveryAttempts = 3
    /// A cloud upload body older than this is an orphan from a kill
    /// mid-upload (the request timeout is far shorter), safe to delete.
    public static let safetyBufferStaleUploadSeconds: TimeInterval = 60 * 60
}
