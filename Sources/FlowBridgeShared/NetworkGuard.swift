import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class NetworkDeniedURLProtocol: URLProtocol {
    public override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }
        // Claim (and kill) every request except the one deliberate,
        // user-enabled exception — see CloudGate. In extension processes
        // CloudGate never opens, so this remains an absolute block there.
        return !CloudGate.isAllowed(request.url)
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        let error = URLError(.notConnectedToInternet)
        client?.urlProtocol(self, didFailWithError: error)
    }

    public override func stopLoading() {}
}

public enum NetworkGuard {
    public static func install() {
        URLProtocol.registerClass(NetworkDeniedURLProtocol.self)
    }
}

