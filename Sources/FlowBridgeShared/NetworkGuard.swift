import Foundation

public final class NetworkDeniedURLProtocol: URLProtocol {
    public override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
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

