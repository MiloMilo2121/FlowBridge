import Foundation

/// Minimal on-device diagnostic log. Appends timestamped lines to
/// `fb-diagnostics.log` in the CALLING process's Documents directory, so the
/// app and each extension write to their own container (pull via
/// `devicectl device copy from --domain-type appDataContainer
/// --domain-identifier <bundle id> --source Documents/fb-diagnostics.log`).
///
/// Deliberately trivial and best-effort: never throws, never blocks the UI,
/// writes nothing off-device. Remove instrumentation before release.
public enum FBLog {
    private static let queue = DispatchQueue(label: "com.marcomilanello.flowbridge.fblog")

    public static var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("fb-diagnostics.log")
    }

    public static func log(_ message: String, category: String = "app") {
        let stamp = Self.stamp()
        queue.async {
            guard let url = fileURL, let data = "\(stamp) [\(category)] \(message)\n".data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
