import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The single legitimate opening in the network wall.
///
/// `NetworkGuard` registers a deny-all URLProtocol that every default
/// URLSession consults; this gate builds sessions whose configuration
/// strips protocol classes, so ONLY code that deliberately asks for the
/// cloud session can reach the network. The keyboard and the other
/// extensions never call this — their processes stay offline by
/// construction. Every request through the gate is counted, and the
/// Privacy Cockpit renders that count: the exception is visible, never
/// silent.
public enum CloudGate {
    private final class Usage: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var host: String?

        func note(host: String) {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            self.host = host
        }

        func snapshot() -> (count: Int, host: String?) {
            lock.lock()
            defer { lock.unlock() }
            return (count, host)
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            count = 0
            host = nil
        }
    }

    private static let usage = Usage()

    /// A session that bypasses the deny-all guard. Ephemeral: no cookie or
    /// cache persistence.
    public static func session(requestTimeout: TimeInterval = 30) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout * 4
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    /// Callers report each outbound request so the Cockpit stays truthful.
    public static func noteRequest(host: String) {
        usage.note(host: host)
    }

    /// Requests sent through the gate since launch, and the last host.
    public static var requestCount: Int {
        usage.snapshot().count
    }

    public static var lastHost: String? {
        usage.snapshot().host
    }

    public static func resetUsage() {
        usage.reset()
    }
}
