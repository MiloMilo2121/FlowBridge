import AVFoundation
import Foundation

struct RecordedAudio: Sendable {
    let url: URL
    let duration: TimeInterval
}

/// Microphone permission, and nothing else. Audio capture itself lives in
/// the engines (`AppleSpeechEngine.startCapture`, WhisperKit's audio
/// processor) — this used to be a full `AVAudioRecorder` wrapper whose
/// recording path was never called, which made it read like the component
/// that records the dictation. It is not.
enum MicrophonePermission {
    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    /// Whether recording can start without showing a permission prompt —
    /// the prerequisite for background starts, where no prompt can appear.
    static var isGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }
}
