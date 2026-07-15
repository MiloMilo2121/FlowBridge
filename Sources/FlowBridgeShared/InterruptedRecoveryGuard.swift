import Foundation

/// Prevents an interrupted recording from turning into a launch-time crash
/// loop. The marker lives beside the WAV, so it is durably written before a
/// recovery model is loaded and disappears with the recording after success.
public enum InterruptedRecoveryGuard {
    private static let markerExtension = "recovery-attempted"

    public static func hasAttempted(_ recordingURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(for: recordingURL).path)
    }

    public static func markAttempted(_ recordingURL: URL) throws {
        try Data().write(to: markerURL(for: recordingURL), options: .atomic)
    }

    public static func clear(_ recordingURL: URL) {
        try? FileManager.default.removeItem(at: markerURL(for: recordingURL))
    }

    public static func markerURL(for recordingURL: URL) -> URL {
        recordingURL.appendingPathExtension(markerExtension)
    }
}
