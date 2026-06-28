import Foundation

public enum FlowBridgeConstants {
    public static let appGroupIdentifier = "group.com.marcomilanello.flowbridge"
    public static let latestTranscriptKey = "latestTranscriptRecord"
    public static let pendingCommandKey = "pendingCommand"
    public static let queuedAudioPathKey = "queuedAudioPath"
    public static let modelFolderName = "WhisperSmall"
    public static let modelResourceSubdirectory = "WhisperModels"
    public static let maxRecordingSeconds: TimeInterval = 90
    public static let modelIdleTTLSeconds: TimeInterval = 180
}

