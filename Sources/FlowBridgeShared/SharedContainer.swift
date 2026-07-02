import Foundation

public enum SharedContainer {
    public static func userDefaults(
        suiteName: String = FlowBridgeConstants.appGroupIdentifier
    ) throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw FlowBridgeError.appGroupUnavailable(suiteName)
        }
        return defaults
    }

    public static func containerURL(
        appGroupIdentifier: String = FlowBridgeConstants.appGroupIdentifier,
        allowTemporaryFallback: Bool = false
    ) throws -> URL {
        #if canImport(Darwin)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return url
        }
        #endif

        if allowTemporaryFallback {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FlowBridgeShared", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        throw FlowBridgeError.appGroupUnavailable(appGroupIdentifier)
    }

    public static func queuedAudioInboxURL() throws -> URL {
        let url = try containerURL().appendingPathComponent("QueuedAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

