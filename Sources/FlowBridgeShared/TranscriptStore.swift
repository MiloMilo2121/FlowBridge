import Foundation

public actor TranscriptStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults? = nil) throws {
        self.defaults = try defaults ?? SharedContainer.userDefaults()
        encoder.dateEncodingStrategy = .deferredToDate
        decoder.dateDecodingStrategy = .deferredToDate
    }

    public func save(_ record: TranscriptRecord) throws {
        let data = try encoder.encode(record)
        defaults.set(data, forKey: FlowBridgeConstants.latestTranscriptKey)
    }

    public func latest() -> TranscriptRecord? {
        Self.latest(defaults: defaults)
    }

    public func clear() {
        defaults.removeObject(forKey: FlowBridgeConstants.latestTranscriptKey)
    }

    public static func latest(defaults: UserDefaults? = nil) -> TranscriptRecord? {
        let resolvedDefaults: UserDefaults
        if let defaults {
            resolvedDefaults = defaults
        } else if let appGroupDefaults = try? SharedContainer.userDefaults() {
            resolvedDefaults = appGroupDefaults
        } else {
            return nil
        }

        guard let data = resolvedDefaults.data(forKey: FlowBridgeConstants.latestTranscriptKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try? decoder.decode(TranscriptRecord.self, from: data)
    }
}
