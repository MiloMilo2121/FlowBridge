import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class NetworkDeniedURLProtocol: URLProtocol {
    public override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        NetworkGuard.noteBlockedRequest()
        let error = URLError(.notConnectedToInternet)
        client?.urlProtocol(self, didFailWithError: error)
    }

    public override func stopLoading() {}
}

public enum NetworkGuard {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            defer { lock.unlock() }
            value += 1
        }

        func current() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            value = 0
        }
    }

    private static let blocked = Counter()

    public static func install() {
        URLProtocol.registerClass(NetworkDeniedURLProtocol.self)
    }

    /// Requests denied since launch. The Privacy Cockpit shows it live:
    /// the guard is architecture, the counter makes it visible.
    public static var blockedRequestCount: Int {
        blocked.current()
    }

    static func noteBlockedRequest() {
        blocked.increment()
    }

    public static func resetBlockedRequestCount() {
        blocked.reset()
    }
}
