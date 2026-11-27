import Foundation

public enum FlowBridgeError: Error, Equatable, LocalizedError, Sendable {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case appGroupUnavailable(String)
    case emptyTranscript
    case queuedAudioMissing
    case unsupportedShareItem
    case recorderFailed(String)
    case transcriptionFailed(String)
    case liveActivityUnavailable
    case noDictationHandler
    case dictationBusy

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
        case .liveActivityUnavailable:
            return "Live Activities are off, so a background dictation cannot stay alive."
        case .noDictationHandler:
            return "Dictation is not available in this process."
        case .dictationBusy:
            return "FlowBridge is still finishing the previous dictation."
        }
    }
}

