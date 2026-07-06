import Foundation

/// The single, deliberate exception to FlowBridge's network ban.
///
/// Default state — and the only state extensions can ever be in — is
/// "everything blocked", identical to the original guarantee. Three
/// conditions must ALL hold for one request to pass:
///   1. the process opted in (`enableForAppProcess()` — called only by the
///      main app at launch; the keyboard/share/widget processes never call
///      it, so their block is absolute and not even a corrupted preference
///      can open it),
///   2. the user enabled the cloud engine in Settings (opt-in, off by
///      default, behind an explicit consent screen),
///   3. the request targets exactly the configured provider host.
public enum CloudGate {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var processMayAllowCloud = false

    /// Main app only. Extensions never call this.
    public static func enableForAppProcess() {
        lock.lock()
        processMayAllowCloud = true
        lock.unlock()
    }

    public static var isCloudEngineEnabled: Bool {
        guard let defaults = try? SharedContainer.userDefaults() else { return false }
        return defaults.bool(forKey: FlowBridgeConstants.cloudEngineEnabledKey)
    }

    public static func setCloudEngineEnabled(_ enabled: Bool) {
        let defaults = try? SharedContainer.userDefaults()
        defaults?.set(enabled, forKey: FlowBridgeConstants.cloudEngineEnabledKey)
    }

    public static func isAllowed(_ url: URL?) -> Bool {
        lock.lock()
        let processAllows = processMayAllowCloud
        lock.unlock()

        guard processAllows,
              isCloudEngineEnabled,
              let host = url?.host()?.lowercased() else {
            return false
        }
        return host == FlowBridgeConstants.cloudProviderHost
    }
}
