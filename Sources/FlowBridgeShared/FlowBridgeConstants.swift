import Foundation

public enum FlowBridgeConstants {
    public static let appGroupIdentifier = "group.com.marcomilanello.flowbridge"
    public static let latestTranscriptKey = "latestTranscriptRecord"
    public static let pendingCommandKey = "pendingCommand"
    public static let queuedAudioPathKey = "queuedAudioPath"
    public static let modelFolderName = "WhisperSmall"
    public static let modelResourceSubdirectory = "WhisperModels"
    public static let maxRecordingSeconds: TimeInterval = 600
    public static let modelIdleTTLSeconds: TimeInterval = 180

    /// Darwin notification posted whenever a live transcript snapshot is
    /// written to the App Group. Payload-free; readers reload from the store.
    public static let liveTranscriptDidChangeDarwinName = "com.marcomilanello.flowbridge.liveTranscriptDidChange"

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
}
