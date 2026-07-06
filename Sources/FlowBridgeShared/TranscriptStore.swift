import Foundation

/// Stores the single latest transcript in the App Group.
///
/// A `@unchecked Sendable` class (not an actor) to match its sibling stores
/// (`LiveTranscriptStore`, `PendingCommandStore`): `UserDefaults` is
/// thread-safe, and there is no mutable shared state to serialize.
public final class TranscriptStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) throws {
        self.defaults = try defaults ?? SharedContainer.userDefaults()
    }

    public func save(_ record: TranscriptRecord) throws {
        let data = try FlowBridgeJSON.encoder().encode(record)
        defaults.set(data, forKey: FlowBridgeConstants.latestTranscriptKey)
    }

    public func latest() -> TranscriptRecord? {
        Self.latest(defaults: defaults)
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

        return try? FlowBridgeJSON.decoder().decode(TranscriptRecord.self, from: data)
    }
}
