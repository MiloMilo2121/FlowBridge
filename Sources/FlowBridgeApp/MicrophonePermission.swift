import AVFoundation
import Foundation

struct RecordedAudio: Sendable {
    let url: URL
    let duration: TimeInterval
}

/// Microphone permission, and nothing else: capture lives in `CloudEngine`.
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
