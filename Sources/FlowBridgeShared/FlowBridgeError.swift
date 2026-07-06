import Foundation

public enum FlowBridgeError: Error, Equatable, LocalizedError, Sendable {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case appGroupUnavailable(String)
    case modelMissing(String)
    case emptyTranscript
    case queuedAudioMissing
    case unsupportedShareItem
    case recorderFailed(String)
    case transcriptionFailed(String)
    case warmupTimedOut

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is not enabled."
        case .alreadyRecording:
            return "Recording is already active."
        case .notRecording:
            return "No active recording is available."
        case .appGroupUnavailable(let identifier):
            return "App Group is unavailable: \(identifier)."
        case .modelMissing(let path):
            return "Whisper model assets are missing at \(path)."
        case .emptyTranscript:
            return "The transcription result was empty."
        case .queuedAudioMissing:
            return "No queued audio file was found."
        case .unsupportedShareItem:
            return "The shared item is not an audio or movie file."
        case .recorderFailed(let message):
            return "Recorder failed: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .warmupTimedOut:
            return "The speech engine took too long to start."
        }
    }
}

