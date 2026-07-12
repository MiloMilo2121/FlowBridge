import Foundation

/// Dev diagnostics that survive without a console: timestamped lines
/// appended to Documents/fb-diagnostics.log, pullable from the Mac via
/// `devicectl device copy from ... --domain-type appDataContainer`.
/// Thread-safe (called from audio callbacks, actors, and the main actor).
enum FBLog {
    private static let lock = NSLock()
    private static let fileURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("fb-diagnostics.log")
    }()

    static func log(_ message: String) {
        // Epoch with millis: sortable, needs no (non-Sendable) formatter.
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, message)
        print("[FB] \(message)")

        lock.lock()
        defer { lock.unlock() }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// Keeps the log from growing unbounded across sessions.
    static func rotateIfNeeded(maxBytes: Int = 512_000) {
        lock.lock()
        defer { lock.unlock() }
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? Int) ?? 0
        if size > maxBytes {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
