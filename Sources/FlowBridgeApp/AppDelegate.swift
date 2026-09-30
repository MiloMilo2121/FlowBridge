import FlowBridgeShared
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Only the app process may ever open the single cloud exception;
        // extensions never call this, so their network ban stays absolute.
        CloudGate.enableForAppProcess()
        NetworkGuard.install()
        DiagnosticsCollector.shared.startIfEnabled()
        // Build the coordinator now, not when SwiftUI first reads it: its
        // init registers the App Intent handlers, and an intent can be the
        // first thing this process runs.
        _ = FlowBridgeCoordinator.shared
        return true
    }
}

