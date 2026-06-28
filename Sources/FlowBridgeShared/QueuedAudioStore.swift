import Foundation

public enum QueuedAudioStore {
    public static func copyIntoInbox(sourceURL: URL, defaults: UserDefaults? = nil) throws -> URL {
        let inbox = try SharedContainer.queuedAudioInboxURL()
        let extensionName = sourceURL.pathExtension.isEmpty ? "caf" : sourceURL.pathExtension
        let destination = inbox.appendingPathComponent(UUID().uuidString).appendingPathExtension(extensionName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try setLatestQueuedAudioURL(destination, defaults: defaults)
        return destination
    }

    public static func setLatestQueuedAudioURL(_ url: URL, defaults: UserDefaults? = nil) throws {
        let resolvedDefaults = try defaults ?? SharedContainer.userDefaults()
        resolvedDefaults.set(url.path, forKey: FlowBridgeConstants.queuedAudioPathKey)
    }

    public static func latestQueuedAudioURL(defaults: UserDefaults? = nil) -> URL? {
        let resolvedDefaults: UserDefaults
        if let defaults {
            resolvedDefaults = defaults
        } else if let appGroupDefaults = try? SharedContainer.userDefaults() {
            resolvedDefaults = appGroupDefaults
        } else {
            return nil
        }

        guard let path = resolvedDefaults.string(forKey: FlowBridgeConstants.queuedAudioPathKey) else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    public static func clear(defaults: UserDefaults? = nil, removeFile: Bool = false) throws {
        let resolvedDefaults = try defaults ?? SharedContainer.userDefaults()
        let url = latestQueuedAudioURL(defaults: resolvedDefaults)
        resolvedDefaults.removeObject(forKey: FlowBridgeConstants.queuedAudioPathKey)

        if removeFile, let url, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

